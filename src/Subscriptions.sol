// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/ISubscriptions.sol";

/**
 * @title Subscriptions
 * @dev Manages monthly subscriptions for VibesFlow Vibe Market access
 * @notice Users pay 5 POL for 30-day access to the Vibe Market
 */
contract Subscriptions is ISubscriptions, Ownable, Pausable, ReentrancyGuard {
    // Constants
    uint256 public constant DEFAULT_SUBSCRIPTION_PRICE = 5 POL; 
    uint256 public constant DEFAULT_SUBSCRIPTION_DURATION = 30 days; // 30 days
    
    // State variables
    uint256 public subscriptionPrice;
    uint256 public subscriptionDuration;
    address public treasuryReceiver;
    uint256 public totalRevenue;
    uint256 public activeSubscriberCount;
    
    // Mapping from user address to subscription
    mapping(address => Subscription) public subscriptions;
    
    // Array to track active subscribers for counting
    mapping(address => bool) public isActiveSubscriber;

    /**
     * @dev Constructor
     * @param _owner Contract owner address
     * @param _treasuryReceiver Address to receive subscription payments
     */
    constructor(
        address _owner,
        address _treasuryReceiver
    ) Ownable(_owner) {
        require(_treasuryReceiver != address(0), "Subscriptions: Invalid treasury receiver");
        
        treasuryReceiver = _treasuryReceiver;
        subscriptionPrice = DEFAULT_SUBSCRIPTION_PRICE;
        subscriptionDuration = DEFAULT_SUBSCRIPTION_DURATION;
        
        emit TreasuryReceiverUpdated(address(0), _treasuryReceiver);
    }

    /**
     * @dev Subscribe to Vibe Market access
     * @notice Requires exactly subscriptionPrice POL to be sent
     */
    function subscribe() external payable nonReentrant whenNotPaused {
        require(msg.value == subscriptionPrice, "Subscriptions: Incorrect payment amount");
        require(msg.sender != address(0), "Subscriptions: Invalid subscriber");

        Subscription storage userSub = subscriptions[msg.sender];
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + subscriptionDuration;

        // If user already has a subscription (active or expired)
        if (userSub.startTime > 0) {
            // If current subscription is still active, extend it
            if (userSub.isActive && block.timestamp < userSub.endTime) {
                endTime = userSub.endTime + subscriptionDuration;
            }
            
            // Update existing subscription
            userSub.startTime = startTime;
            userSub.endTime = endTime;
            userSub.amountPaid += msg.value;
            userSub.isActive = true;
            userSub.renewalCount += 1;

            emit SubscriptionRenewed(msg.sender, endTime, msg.value, userSub.renewalCount);
        } else {
            // Create new subscription
            userSub.startTime = startTime;
            userSub.endTime = endTime;
            userSub.amountPaid = msg.value;
            userSub.isActive = true;
            userSub.renewalCount = 0;

            emit Subscribed(msg.sender, startTime, endTime, msg.value);
        }

        // Update active subscriber tracking
        if (!isActiveSubscriber[msg.sender]) {
            isActiveSubscriber[msg.sender] = true;
            activeSubscriberCount++;
        }

        // Update total revenue
        totalRevenue += msg.value;

        // Send payment to treasury
        (bool success, ) = payable(treasuryReceiver).call{value: msg.value}("");
        require(success, "Subscriptions: Payment to treasury failed");
    }

    /**
     * @dev Renew an existing subscription
     * @notice Can be called even if subscription has expired
     */
    function renewSubscription() external payable nonReentrant whenNotPaused {
        require(msg.value == subscriptionPrice, "Subscriptions: Incorrect payment amount");
        require(subscriptions[msg.sender].startTime > 0, "Subscriptions: No existing subscription");

        Subscription storage userSub = subscriptions[msg.sender];
        uint256 newEndTime;

        // If subscription is still active, extend from current end time
        if (userSub.isActive && block.timestamp < userSub.endTime) {
            newEndTime = userSub.endTime + subscriptionDuration;
        } else {
            // If expired, start new period from now
            newEndTime = block.timestamp + subscriptionDuration;
        }

        userSub.endTime = newEndTime;
        userSub.amountPaid += msg.value;
        userSub.isActive = true;
        userSub.renewalCount += 1;

        // Update active subscriber tracking
        if (!isActiveSubscriber[msg.sender]) {
            isActiveSubscriber[msg.sender] = true;
            activeSubscriberCount++;
        }

        // Update total revenue
        totalRevenue += msg.value;

        emit SubscriptionRenewed(msg.sender, newEndTime, msg.value, userSub.renewalCount);

        // Send payment to treasury
        (bool success, ) = payable(treasuryReceiver).call{value: msg.value}("");
        require(success, "Subscriptions: Payment to treasury failed");
    }

    /**
     * @dev Check if a user has an active subscription
     * @param user The user address to check
     * @return bool True if user has active subscription
     */
    function isSubscribed(address user) external view returns (bool) {
        Subscription memory userSub = subscriptions[user];
        return userSub.isActive && block.timestamp < userSub.endTime;
    }

    /**
     * @dev Get subscription details for a user
     * @param user The user address to query
     * @return Subscription struct with all subscription data
     */
    function getSubscription(address user) external view returns (Subscription memory) {
        return subscriptions[user];
    }

    /**
     * @dev Get time remaining on subscription
     * @param user The user address to check
     * @return uint256 Seconds remaining (0 if expired or no subscription)
     */
    function getTimeRemaining(address user) external view returns (uint256) {
        Subscription memory userSub = subscriptions[user];
        if (!userSub.isActive || block.timestamp >= userSub.endTime) {
            return 0;
        }
        return userSub.endTime - block.timestamp;
    }

    /**
     * @dev Get total number of active subscribers
     * @return uint256 Count of active subscribers
     */
    function getActiveSubscriberCount() external view returns (uint256) {
        return activeSubscriberCount;
    }

    /**
     * @dev Get total revenue collected
     * @return uint256 Total POL collected from subscriptions
     */
    function getTotalRevenue() external view returns (uint256) {
        return totalRevenue;
    }

    /**
     * @dev Get current subscription price
     * @return uint256 Price in POL
     */
    function getSubscriptionPrice() external view returns (uint256) {
        return subscriptionPrice;
    }

    /**
     * @dev Get subscription duration
     * @return uint256 Duration in seconds
     */
    function getSubscriptionDuration() external view returns (uint256) {
        return subscriptionDuration;
    }

    /**
     * @dev Check if subscription has expired
     * @param user The user address to check
     * @return bool True if subscription exists but has expired
     */
    function hasExpiredSubscription(address user) external view returns (bool) {
        Subscription memory userSub = subscriptions[user];
        return userSub.startTime > 0 && block.timestamp >= userSub.endTime;
    }

    // Admin functions

    /**
     * @dev Update subscription price (only owner)
     * @param newPrice New price in POL (wei)
     */
    function setSubscriptionPrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Subscriptions: Price must be greater than 0");
        uint256 oldPrice = subscriptionPrice;
        subscriptionPrice = newPrice;
        emit SubscriptionPriceUpdated(oldPrice, newPrice);
    }

    /**
     * @dev Update subscription duration (only owner)
     * @param newDuration New duration in seconds
     */
    function setSubscriptionDuration(uint256 newDuration) external onlyOwner {
        require(newDuration > 0, "Subscriptions: Duration must be greater than 0");
        uint256 oldDuration = subscriptionDuration;
        subscriptionDuration = newDuration;
        emit SubscriptionDurationUpdated(oldDuration, newDuration);
    }

    /**
     * @dev Update treasury receiver (only owner)
     * @param newTreasury New treasury address
     */
    function setTreasuryReceiver(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Subscriptions: Invalid treasury address");
        address oldTreasury = treasuryReceiver;
        treasuryReceiver = newTreasury;
        emit TreasuryReceiverUpdated(oldTreasury, newTreasury);
    }

    /**
     * @dev Emergency pause subscriptions (only owner)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Resume subscriptions (only owner)
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Check if contract is paused
     * @return bool True if paused
     */
    function paused() public view override(ISubscriptions, Pausable) returns (bool) {
        return super.paused();
    }

    /**
     * @dev Clean up expired subscriptions to maintain accurate active count
     * @param users Array of user addresses to check and clean up
     * @notice This is a maintenance function to keep activeSubscriberCount accurate
     */
    function cleanupExpiredSubscriptions(address[] calldata users) external {
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            Subscription storage userSub = subscriptions[user];
            
            // If subscription exists and has expired, mark as inactive
            if (userSub.startTime > 0 && block.timestamp >= userSub.endTime && userSub.isActive) {
                userSub.isActive = false;
                
                // Update active subscriber tracking
                if (isActiveSubscriber[user]) {
                    isActiveSubscriber[user] = false;
                    if (activeSubscriberCount > 0) {
                        activeSubscriberCount--;
                    }
                }
            }
        }
    }

    /**
     * @dev Emergency withdrawal function (only owner)
     * @notice Only for emergency situations, normal flow sends to treasury automatically
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "Subscriptions: No balance to withdraw");
        
        (bool success, ) = payable(treasuryReceiver).call{value: balance}("");
        require(success, "Subscriptions: Emergency withdrawal failed");
    }

    /**
     * @dev Get contract balance
     * @return uint256 Current contract balance in POL
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // Fallback functions
    receive() external payable {
        revert("Subscriptions: Use subscribe() function");
    }

    fallback() external payable {
        revert("Subscriptions: Use subscribe() function");
    }
}