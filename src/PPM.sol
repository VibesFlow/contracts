// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IPPM.sol";
import "../interfaces/IVibeFactory.sol";

/**
 * @title PPM (Pay-Per-Minute)
 * @dev Production-ready contract for managing POL allowances and automatic withdrawals
 * for group vibestreams with pay-per-stream pricing. Each allowance is tied to a specific
 * vibeID to ensure isolated spending authorization.
 * 
 * Security Features:
 * - Per-vibeID allowance isolation
 * - Reentrancy protection
 * - Emergency stop functionality
 * - Pausable operations
 * - Time-based payment processing
 * - Treasury fee distribution
 */
contract PPM is IPPM, Ownable, ReentrancyGuard, Pausable {
    // =============================================================================
    // STATE VARIABLES
    // =============================================================================
    
    /// @dev The VibeFactory contract for validation
    IVibeFactory public vibeFactory;
    
    /// @dev Treasury receiver address
    address public treasuryReceiver;
    
    /// @dev Treasury fee percentage (0-100)
    uint256 public treasuryFeePercent = 20; // 20% default
    
    /// @dev Minimum payment interval (60 seconds)
    uint256 public constant MIN_PAYMENT_INTERVAL = 60;
    
    /// @dev Maximum allowance per transaction (safety limit)
    uint256 public constant MAX_ALLOWANCE = 1000 pol; // 1000 POL
    
    /// @dev Gas limit for external calls
    uint256 private constant GAS_LIMIT = 50000;

    // =============================================================================
    // MAPPINGS
    // =============================================================================
    
    /// @dev vibeId => VibestreamConfig
    mapping(uint256 => VibestreamConfig) public vibestreamConfigs;
    
    /// @dev vibeId => participant => ParticipantAllowance
    mapping(uint256 => mapping(address => ParticipantAllowance)) public participantAllowances;
    
    /// @dev vibeId => array of active participants
    mapping(uint256 => address[]) public activeParticipants;
    
    /// @dev vibeId => participant => index in activeParticipants array
    mapping(uint256 => mapping(address => uint256)) public participantIndex;
    
    /// @dev vibeId => participant => is in activeParticipants array
    mapping(uint256 => mapping(address => bool)) public isInActiveList;

    // =============================================================================
    // MODIFIERS
    // =============================================================================
    
    modifier onlyVibeFactory() {
        require(msg.sender == address(vibeFactory), "PPM: Only VibeFactory can call this");
        _;
    }
    
    modifier validVibeId(uint256 vibeId) {
        require(vibestreamConfigs[vibeId].isActive, "PPM: Vibestream not registered");
        _;
    }
    
    modifier hasAllowance(uint256 vibeId, address participant) {
        require(
            participantAllowances[vibeId][participant].authorizedAmount > 0,
            "PPM: No allowance authorized"
        );
        _;
    }

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================
    
    constructor(
        address _owner,
        address _vibeFactory,
        address _treasuryReceiver
    ) Ownable(_owner) {
        require(_vibeFactory != address(0), "PPM: Invalid VibeFactory address");
        require(_treasuryReceiver != address(0), "PPM: Invalid treasury receiver");
        
        vibeFactory = IVibeFactory(_vibeFactory);
        treasuryReceiver = _treasuryReceiver;
    }

    // =============================================================================
    // CORE FUNCTIONS
    // =============================================================================
    
    /**
     * @dev Registers a vibestream for pay-per-minute functionality
     */
    function registerVibestream(
        uint256 vibeId,
        address creator,
        uint256 payPerMinute
    ) external override onlyVibeFactory whenNotPaused {
        require(creator != address(0), "PPM: Invalid creator address");
        require(payPerMinute > 0, "PPM: Pay per minute must be greater than 0");
        require(!vibestreamConfigs[vibeId].isActive, "PPM: Vibestream already registered");
        
        vibestreamConfigs[vibeId] = VibestreamConfig({
            vibeId: vibeId,
            creator: creator,
            payPerMinute: payPerMinute,
            isActive: true,
            totalParticipants: 0,
            totalRevenue: 0
        });
        
        emit VibestreamRegistered(vibeId, creator, payPerMinute);
    }
    
    /**
     * @dev Authorizes spending allowance for a specific vibestream
     */
    function authorizeSpending(
        uint256 vibeId,
        uint256 authorizedAmount
    ) external payable override nonReentrant whenNotPaused validVibeId(vibeId) {
        require(authorizedAmount > 0, "PPM: Authorized amount must be greater than 0");
        require(authorizedAmount <= MAX_ALLOWANCE, "PPM: Amount exceeds maximum allowance");
        require(msg.value >= authorizedAmount, "PPM: Insufficient payment");
        
        VibestreamConfig storage config = vibestreamConfigs[vibeId];
        
        // Check if participant already has an allowance
        ParticipantAllowance storage allowance = participantAllowances[vibeId][msg.sender];
        
        if (allowance.authorizedAmount > 0) {
            // If participant is currently active, process pending payments first
            if (allowance.isActive) {
                _processParticipantPayment(vibeId, msg.sender);
            }
            
            // Add to existing allowance
            allowance.authorizedAmount += authorizedAmount;
        } else {
            // Create new allowance
            allowance.vibeId = vibeId;
            allowance.participant = msg.sender;
            allowance.authorizedAmount = authorizedAmount;
            allowance.spentAmount = 0;
            allowance.payPerMinute = config.payPerMinute;
            allowance.joinedAt = 0;
            allowance.lastDeduction = 0;
            allowance.isActive = false;
            allowance.creator = config.creator;
        }
        
        // Refund excess payment
        if (msg.value > authorizedAmount) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - authorizedAmount}("");
            require(success, "PPM: Refund failed");
        }
        
        emit AllowanceAuthorized(vibeId, msg.sender, authorizedAmount, config.payPerMinute);
    }
    
    /**
     * @dev Increases the spending allowance for a specific vibestream
     */
    function increaseAllowance(
        uint256 vibeId,
        uint256 additionalAmount
    ) external payable override nonReentrant whenNotPaused validVibeId(vibeId) hasAllowance(vibeId, msg.sender) {
        require(additionalAmount > 0, "PPM: Additional amount must be greater than 0");
        require(msg.value >= additionalAmount, "PPM: Insufficient payment");
        
        ParticipantAllowance storage allowance = participantAllowances[vibeId][msg.sender];
        
        // Process pending payments if participant is active
        if (allowance.isActive) {
            _processParticipantPayment(vibeId, msg.sender);
        }
        
        uint256 newTotalAuthorized = allowance.authorizedAmount + additionalAmount;
        require(newTotalAuthorized <= MAX_ALLOWANCE, "PPM: Total allowance exceeds maximum");
        
        allowance.authorizedAmount = newTotalAuthorized;
        
        // Refund excess payment
        if (msg.value > additionalAmount) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - additionalAmount}("");
            require(success, "PPM: Refund failed");
        }
        
        emit AllowanceIncreased(vibeId, msg.sender, additionalAmount, newTotalAuthorized);
    }
    
    /**
     * @dev Joins a vibestream and starts the payment timer
     */
    function joinVibestream(
        uint256 vibeId
    ) external override nonReentrant whenNotPaused validVibeId(vibeId) hasAllowance(vibeId, msg.sender) {
        ParticipantAllowance storage allowance = participantAllowances[vibeId][msg.sender];
        require(!allowance.isActive, "PPM: Already in vibestream");
        
        // Ensure participant has enough allowance for at least one minute
        uint256 remaining = allowance.authorizedAmount - allowance.spentAmount;
        require(remaining >= allowance.payPerMinute, "PPM: Insufficient remaining allowance");
        
        // Set participant as active
        allowance.isActive = true;
        allowance.joinedAt = block.timestamp;
        allowance.lastDeduction = block.timestamp;
        
        // Add to active participants list
        if (!isInActiveList[vibeId][msg.sender]) {
            participantIndex[vibeId][msg.sender] = activeParticipants[vibeId].length;
            activeParticipants[vibeId].push(msg.sender);
            isInActiveList[vibeId][msg.sender] = true;
            vibestreamConfigs[vibeId].totalParticipants++;
        }
        
        emit ParticipantJoined(vibeId, msg.sender, block.timestamp);
    }
    
    /**
     * @dev Leaves a vibestream and stops the payment timer
     */
    function leaveVibestream(
        uint256 vibeId
    ) external override nonReentrant whenNotPaused validVibeId(vibeId) {
        ParticipantAllowance storage allowance = participantAllowances[vibeId][msg.sender];
        require(allowance.isActive, "PPM: Not in vibestream");
        
        // Process final payment
        _processParticipantPayment(vibeId, msg.sender);
        
        // Set participant as inactive
        allowance.isActive = false;
        
        // Remove from active participants list
        _removeFromActiveList(vibeId, msg.sender);
        
        emit ParticipantLeft(vibeId, msg.sender, block.timestamp, allowance.spentAmount);
    }
    
    /**
     * @dev Processes payment deductions for active participants
     */
    function processPayments(uint256 vibeId) external override whenNotPaused validVibeId(vibeId) {
        address[] memory participants = activeParticipants[vibeId];
        
        for (uint256 i = 0; i < participants.length; i++) {
            if (participants[i] != address(0)) {
                _processParticipantPayment(vibeId, participants[i]);
            }
        }
    }
    
    /**
     * @dev Processes payment for a specific participant
     */
    function processParticipantPayment(
        uint256 vibeId,
        address participant
    ) external override whenNotPaused validVibeId(vibeId) {
        _processParticipantPayment(vibeId, participant);
    }
    
    /**
     * @dev Emergency stop for a participant
     */
    function emergencyStop(
        uint256 vibeId,
        address participant,
        string calldata reason
    ) external override whenNotPaused validVibeId(vibeId) {
        require(
            msg.sender == owner() || 
            msg.sender == participant || 
            msg.sender == vibestreamConfigs[vibeId].creator,
            "PPM: Not authorized for emergency stop"
        );
        
        ParticipantAllowance storage allowance = participantAllowances[vibeId][participant];
        
        if (allowance.isActive) {
            // Process final payment
            _processParticipantPayment(vibeId, participant);
            
            // Set participant as inactive
            allowance.isActive = false;
            
            // Remove from active participants list
            _removeFromActiveList(vibeId, participant);
        }
        
        emit EmergencyStop(vibeId, participant, reason);
    }

    // =============================================================================
    // INTERNAL FUNCTIONS
    // =============================================================================
    
    /**
     * @dev Internal function to process payment for a participant
     */
    function _processParticipantPayment(uint256 vibeId, address participant) internal {
        ParticipantAllowance storage allowance = participantAllowances[vibeId][participant];
        
        if (!allowance.isActive || allowance.lastDeduction == 0) {
            return; // Not active or no previous deduction timestamp
        }
        
        uint256 timeElapsed = block.timestamp - allowance.lastDeduction;
        
        // Only process if at least MIN_PAYMENT_INTERVAL has passed
        if (timeElapsed < MIN_PAYMENT_INTERVAL) {
            return;
        }
        
        uint256 minutesElapsed = timeElapsed / MIN_PAYMENT_INTERVAL;
        uint256 amountOwed = minutesElapsed * allowance.payPerMinute;
        
        if (amountOwed == 0) {
            return;
        }
        
        uint256 remainingAllowance = allowance.authorizedAmount - allowance.spentAmount;
        
        if (remainingAllowance < amountOwed) {
            // Insufficient allowance - use remaining amount and remove participant
            amountOwed = remainingAllowance;
            
            emit InsufficientAllowance(vibeId, participant, amountOwed, remainingAllowance);
            
            // Force leave the vibestream
            allowance.isActive = false;
            _removeFromActiveList(vibeId, participant);
        }
        
        if (amountOwed > 0) {
            // Update spent amount
            allowance.spentAmount += amountOwed;
            allowance.lastDeduction = block.timestamp;
            
            // Calculate distribution: 80% creator, 20% treasury
            uint256 treasuryFee = (amountOwed * treasuryFeePercent) / 100;
            uint256 creatorAmount = amountOwed - treasuryFee;
            
            // Update total revenue
            vibestreamConfigs[vibeId].totalRevenue += amountOwed;
            
            // Transfer to creator first
            bool creatorSuccess = false;
            if (creatorAmount > 0) {
                (creatorSuccess, ) = payable(allowance.creator).call{
                    value: creatorAmount,
                    gas: GAS_LIMIT
                }("");
            }
            
            // Transfer to treasury
            bool treasurySuccess = false;
            if (treasuryFee > 0) {
                (treasurySuccess, ) = payable(treasuryReceiver).call{
                    value: treasuryFee,
                    gas: GAS_LIMIT
                }("");
            }
            
            // If creator transfer failed, add their amount to treasury
            if (creatorAmount > 0 && !creatorSuccess) {
                uint256 totalForTreasury = treasuryFee + creatorAmount;
                (treasurySuccess, ) = payable(treasuryReceiver).call{
                    value: totalForTreasury,
                    gas: GAS_LIMIT
                }("");
                require(treasurySuccess, "PPM: All transfers failed - funds stuck");
            }
            
            // Ensure at least one transfer succeeded
            require(creatorSuccess || treasurySuccess, "PPM: All transfers failed");
            
            emit PaymentDeducted(vibeId, participant, allowance.creator, amountOwed, block.timestamp);
        }
    }
    
    /**
     * @dev Removes a participant from the active participants list
     */
    function _removeFromActiveList(uint256 vibeId, address participant) internal {
        if (!isInActiveList[vibeId][participant]) {
            return;
        }
        
        uint256 index = participantIndex[vibeId][participant];
        address[] storage participants = activeParticipants[vibeId];
        
        if (index < participants.length - 1) {
            // Move last element to the index being removed
            address lastParticipant = participants[participants.length - 1];
            participants[index] = lastParticipant;
            participantIndex[vibeId][lastParticipant] = index;
        }
        
        participants.pop();
        delete participantIndex[vibeId][participant];
        isInActiveList[vibeId][participant] = false;
        
        if (vibestreamConfigs[vibeId].totalParticipants > 0) {
            vibestreamConfigs[vibeId].totalParticipants--;
        }
    }

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================
    
    function getParticipantAllowance(
        uint256 vibeId,
        address participant
    ) external view override returns (ParticipantAllowance memory) {
        return participantAllowances[vibeId][participant];
    }
    
    function getVibestreamConfig(
        uint256 vibeId
    ) external view override returns (VibestreamConfig memory) {
        return vibestreamConfigs[vibeId];
    }
    
    function getRemainingAllowance(
        uint256 vibeId,
        address participant
    ) external view override returns (uint256) {
        ParticipantAllowance memory allowance = participantAllowances[vibeId][participant];
        if (allowance.authorizedAmount <= allowance.spentAmount) {
            return 0;
        }
        return allowance.authorizedAmount - allowance.spentAmount;
    }
    
    function getParticipantTime(
        uint256 vibeId,
        address participant
    ) external view override returns (uint256) {
        ParticipantAllowance memory allowance = participantAllowances[vibeId][participant];
        if (!allowance.isActive || allowance.joinedAt == 0) {
            return 0;
        }
        return block.timestamp - allowance.joinedAt;
    }
    
    function getAmountOwed(
        uint256 vibeId,
        address participant
    ) external view override returns (uint256) {
        ParticipantAllowance memory allowance = participantAllowances[vibeId][participant];
        
        if (!allowance.isActive || allowance.lastDeduction == 0) {
            return 0;
        }
        
        uint256 timeElapsed = block.timestamp - allowance.lastDeduction;
        uint256 minutesElapsed = timeElapsed / MIN_PAYMENT_INTERVAL;
        
        return minutesElapsed * allowance.payPerMinute;
    }
    
    function isParticipantActive(
        uint256 vibeId,
        address participant
    ) external view override returns (bool) {
        return participantAllowances[vibeId][participant].isActive;
    }
    
    function getActiveParticipants(
        uint256 vibeId
    ) external view override returns (address[] memory) {
        return activeParticipants[vibeId];
    }
    
    function getTotalRevenue(
        uint256 vibeId
    ) external view override returns (uint256) {
        return vibestreamConfigs[vibeId].totalRevenue;
    }
    
    function isVibestreamRegistered(
        uint256 vibeId
    ) external view override returns (bool) {
        return vibestreamConfigs[vibeId].isActive;
    }

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================
    
    function setVibeFactory(address _vibeFactory) external override onlyOwner {
        require(_vibeFactory != address(0), "PPM: Invalid VibeFactory address");
        vibeFactory = IVibeFactory(_vibeFactory);
    }
    
    function setTreasuryReceiver(address _treasuryReceiver) external override onlyOwner {
        require(_treasuryReceiver != address(0), "PPM: Invalid treasury receiver");
        treasuryReceiver = _treasuryReceiver;
    }
    
    function setTreasuryFeePercent(uint256 _treasuryFeePercent) external override onlyOwner {
        require(_treasuryFeePercent <= 100, "PPM: Fee percent cannot exceed 100");
        treasuryFeePercent = _treasuryFeePercent;
    }
    
    function emergencyWithdraw() external override onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = payable(owner()).call{value: balance}("");
            require(success, "PPM: Emergency withdraw failed");
        }
    }
    
    function pause() external override onlyOwner {
        _pause();
    }
    
    function unpause() external override onlyOwner {
        _unpause();
    }
    
    // =============================================================================
    // RECEIVE FUNCTION
    // =============================================================================
    
    receive() external payable {
        // Allow contract to receive POL
    }
}
