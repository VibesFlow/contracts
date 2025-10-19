// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IVibeFactory.sol";

/**
 * @title IPPM (Pay-Per-Minute Interface)
 * @dev Interface for the Pay-Per-Minute contract that manages POL allowances
 * and automatic withdrawals for group vibestreams with pay-per-stream pricing.
 * Each allowance is tied to a specific vibeID to ensure isolated spending authorization.
 */
interface IPPM {
    // =============================================================================
    // STRUCTS
    // =============================================================================
    
    /**
     * @dev Represents a participant's allowance for a specific vibestream
     */
    struct ParticipantAllowance {
        uint256 vibeId;           // The vibestream ID this allowance is for
        address participant;      // The participant's address
        uint256 authorizedAmount; // Total amount authorized for spending (in wei)
        uint256 spentAmount;      // Amount already spent (in wei)
        uint256 payPerMinute;     // Amount to deduct per minute (in wei)
        uint256 joinedAt;         // Timestamp when participant joined
        uint256 lastDeduction;    // Timestamp of last deduction
        bool isActive;            // Whether the participant is currently in the stream
        address creator;          // The vibestream creator (receives payments)
    }

    /**
     * @dev Represents vibestream configuration for PPM
     */
    struct VibestreamConfig {
        uint256 vibeId;           // The vibestream ID
        address creator;          // The creator of the vibestream
        uint256 payPerMinute;     // Amount to charge per minute (in wei)
        bool isActive;            // Whether PPM is active for this vibestream
        uint256 totalParticipants; // Current number of active participants
        uint256 totalRevenue;     // Total revenue generated
    }

    // =============================================================================
    // EVENTS
    // =============================================================================
    
    /**
     * @dev Emitted when a vibestream is registered for PPM
     */
    event VibestreamRegistered(
        uint256 indexed vibeId,
        address indexed creator,
        uint256 payPerMinute
    );

    /**
     * @dev Emitted when a participant authorizes spending for a vibestream
     */
    event AllowanceAuthorized(
        uint256 indexed vibeId,
        address indexed participant,
        uint256 authorizedAmount,
        uint256 payPerMinute
    );

    /**
     * @dev Emitted when a participant joins a vibestream
     */
    event ParticipantJoined(
        uint256 indexed vibeId,
        address indexed participant,
        uint256 timestamp
    );

    /**
     * @dev Emitted when a participant leaves a vibestream
     */
    event ParticipantLeft(
        uint256 indexed vibeId,
        address indexed participant,
        uint256 timestamp,
        uint256 totalSpent
    );

    /**
     * @dev Emitted when payment is deducted from a participant
     */
    event PaymentDeducted(
        uint256 indexed vibeId,
        address indexed participant,
        address indexed creator,
        uint256 amount,
        uint256 timestamp
    );

    /**
     * @dev Emitted when a participant's allowance is insufficient
     */
    event InsufficientAllowance(
        uint256 indexed vibeId,
        address indexed participant,
        uint256 required,
        uint256 remaining
    );

    /**
     * @dev Emitted when allowance is increased
     */
    event AllowanceIncreased(
        uint256 indexed vibeId,
        address indexed participant,
        uint256 additionalAmount,
        uint256 newTotalAuthorized
    );

    /**
     * @dev Emitted when emergency stop is triggered
     */
    event EmergencyStop(
        uint256 indexed vibeId,
        address indexed participant,
        string reason
    );

    // =============================================================================
    // CORE FUNCTIONS
    // =============================================================================

    /**
     * @dev Registers a vibestream for pay-per-minute functionality
     * Can only be called by the VibeFactory contract
     * @param vibeId The ID of the vibestream
     * @param creator The creator of the vibestream
     * @param payPerMinute The amount to charge per minute (in wei)
     */
    function registerVibestream(
        uint256 vibeId,
        address creator,
        uint256 payPerMinute
    ) external;

    /**
     * @dev Authorizes spending allowance for a specific vibestream
     * @param vibeId The ID of the vibestream
     * @param authorizedAmount The total amount to authorize for spending (in wei)
     */
    function authorizeSpending(
        uint256 vibeId,
        uint256 authorizedAmount
    ) external payable;

    /**
     * @dev Increases the spending allowance for a specific vibestream
     * @param vibeId The ID of the vibestream
     * @param additionalAmount The additional amount to authorize (in wei)
     */
    function increaseAllowance(
        uint256 vibeId,
        uint256 additionalAmount
    ) external payable;

    /**
     * @dev Joins a vibestream and starts the payment timer
     * @param vibeId The ID of the vibestream to join
     */
    function joinVibestream(uint256 vibeId) external;

    /**
     * @dev Leaves a vibestream and stops the payment timer
     * @param vibeId The ID of the vibestream to leave
     */
    function leaveVibestream(uint256 vibeId) external;

    /**
     * @dev Processes payment deductions for active participants
     * This function can be called by anyone to trigger payment processing
     * @param vibeId The ID of the vibestream to process payments for
     */
    function processPayments(uint256 vibeId) external;

    /**
     * @dev Processes payment for a specific participant
     * @param vibeId The ID of the vibestream
     * @param participant The address of the participant
     */
    function processParticipantPayment(
        uint256 vibeId,
        address participant
    ) external;

    /**
     * @dev Emergency stop for a participant (removes them from stream)
     * @param vibeId The ID of the vibestream
     * @param participant The address of the participant
     * @param reason The reason for emergency stop
     */
    function emergencyStop(
        uint256 vibeId,
        address participant,
        string calldata reason
    ) external;

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================

    /**
     * @dev Gets the allowance information for a participant in a vibestream
     * @param vibeId The ID of the vibestream
     * @param participant The address of the participant
     * @return The participant's allowance struct
     */
    function getParticipantAllowance(
        uint256 vibeId,
        address participant
    ) external view returns (ParticipantAllowance memory);

    /**
     * @dev Gets the vibestream configuration
     * @param vibeId The ID of the vibestream
     * @return The vibestream configuration struct
     */
    function getVibestreamConfig(
        uint256 vibeId
    ) external view returns (VibestreamConfig memory);

    /**
     * @dev Gets the remaining allowance for a participant
     * @param vibeId The ID of the vibestream
     * @param participant The address of the participant
     * @return The remaining allowance amount (in wei)
     */
    function getRemainingAllowance(
        uint256 vibeId,
        address participant
    ) external view returns (uint256);

    /**
     * @dev Gets the total time a participant has been in a vibestream
     * @param vibeId The ID of the vibestream
     * @param participant The address of the participant
     * @return The total time in seconds
     */
    function getParticipantTime(
        uint256 vibeId,
        address participant
    ) external view returns (uint256);

    /**
     * @dev Gets the amount owed by a participant since last deduction
     * @param vibeId The ID of the vibestream
     * @param participant The address of the participant
     * @return The amount owed (in wei)
     */
    function getAmountOwed(
        uint256 vibeId,
        address participant
    ) external view returns (uint256);

    /**
     * @dev Checks if a participant is currently active in a vibestream
     * @param vibeId The ID of the vibestream
     * @param participant The address of the participant
     * @return True if participant is active, false otherwise
     */
    function isParticipantActive(
        uint256 vibeId,
        address participant
    ) external view returns (bool);

    /**
     * @dev Gets all active participants for a vibestream
     * @param vibeId The ID of the vibestream
     * @return Array of active participant addresses
     */
    function getActiveParticipants(
        uint256 vibeId
    ) external view returns (address[] memory);

    /**
     * @dev Gets the total revenue generated for a vibestream
     * @param vibeId The ID of the vibestream
     * @return The total revenue (in wei)
     */
    function getTotalRevenue(
        uint256 vibeId
    ) external view returns (uint256);

    /**
     * @dev Checks if a vibestream is registered for PPM
     * @param vibeId The ID of the vibestream
     * @return True if registered, false otherwise
     */
    function isVibestreamRegistered(
        uint256 vibeId
    ) external view returns (bool);

    /**
     * @dev Gets the treasury receiver address
     * @return The treasury receiver address
     */
    function treasuryReceiver() external view returns (address);

    /**
     * @dev Gets the treasury fee percentage
     * @return The treasury fee percentage (0-100)
     */
    function treasuryFeePercent() external view returns (uint256);

    /**
     * @dev Gets the VibeFactory contract address
     * @return The VibeFactory contract address
     */
    function vibeFactory() external view returns (IVibeFactory);

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================

    /**
     * @dev Sets the VibeFactory contract address (owner only)
     * @param _vibeFactory The address of the VibeFactory contract
     */
    function setVibeFactory(address _vibeFactory) external;

    /**
     * @dev Sets the treasury receiver address (owner only)
     * @param _treasuryReceiver The address to receive treasury fees
     */
    function setTreasuryReceiver(address _treasuryReceiver) external;

    /**
     * @dev Sets the treasury fee percentage (owner only)
     * @param _treasuryFeePercent The fee percentage (0-100)
     */
    function setTreasuryFeePercent(uint256 _treasuryFeePercent) external;

    /**
     * @dev Emergency withdraw function (owner only)
     */
    function emergencyWithdraw() external;

    /**
     * @dev Pauses the contract (owner only)
     */
    function pause() external;

    /**
     * @dev Unpauses the contract (owner only)
     */
    function unpause() external;
}