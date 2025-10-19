// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ISubscriptions
 * @dev Interface for VibesFlow subscription management
 * Handles monthly subscriptions for accessing the Vibe Market
 */
interface ISubscriptions {
    /**
     * @dev Subscription data structure
     */
    struct Subscription {
        uint256 startTime;      // When subscription started
        uint256 endTime;        // When subscription expires
        uint256 amountPaid;     // Amount paid in POL
        bool isActive;          // Current subscription status
        uint256 renewalCount;   // Number of times renewed
    }

    /**
     * @dev Emitted when a user subscribes
     */
    event Subscribed(
        address indexed user,
        uint256 startTime,
        uint256 endTime,
        uint256 amountPaid
    );

    /**
     * @dev Emitted when a subscription is renewed
     */
    event SubscriptionRenewed(
        address indexed user,
        uint256 newEndTime,
        uint256 amountPaid,
        uint256 renewalCount
    );

    /**
     * @dev Emitted when subscription price is updated
     */
    event SubscriptionPriceUpdated(
        uint256 oldPrice,
        uint256 newPrice
    );

    /**
     * @dev Emitted when subscription duration is updated
     */
    event SubscriptionDurationUpdated(
        uint256 oldDuration,
        uint256 newDuration
    );

    /**
     * @dev Emitted when treasury receiver is updated
     */
    event TreasuryReceiverUpdated(
        address indexed oldTreasury,
        address indexed newTreasury
    );

    /**
     * @dev Subscribe to Vibe Market access
     * @notice Requires exactly subscriptionPrice POL to be sent
     */
    function subscribe() external payable;

    /**
     * @dev Renew an existing subscription
     * @notice Can be called even if subscription has expired
     */
    function renewSubscription() external payable;

    /**
     * @dev Check if a user has an active subscription
     * @param user The user address to check
     * @return bool True if user has active subscription
     */
    function isSubscribed(address user) external view returns (bool);

    /**
     * @dev Get subscription details for a user
     * @param user The user address to query
     * @return Subscription struct with all subscription data
     */
    function getSubscription(address user) external view returns (Subscription memory);

    /**
     * @dev Get time remaining on subscription
     * @param user The user address to check
     * @return uint256 Seconds remaining (0 if expired or no subscription)
     */
    function getTimeRemaining(address user) external view returns (uint256);

    /**
     * @dev Get total number of active subscribers
     * @return uint256 Count of active subscribers
     */
    function getActiveSubscriberCount() external view returns (uint256);

    /**
     * @dev Get total revenue collected
     * @return uint256 Total POL collected from subscriptions
     */
    function getTotalRevenue() external view returns (uint256);

    /**
     * @dev Get current subscription price
     * @return uint256 Price in POL (wei)
     */
    function getSubscriptionPrice() external view returns (uint256);

    /**
     * @dev Get subscription duration
     * @return uint256 Duration in seconds
     */
    function getSubscriptionDuration() external view returns (uint256);

    /**
     * @dev Check if subscription has expired
     * @param user The user address to check
     * @return bool True if subscription exists but has expired
     */
    function hasExpiredSubscription(address user) external view returns (bool);

    // Admin functions
    
    /**
     * @dev Update subscription price (only owner)
     * @param newPrice New price in POL
     */
    function setSubscriptionPrice(uint256 newPrice) external;

    /**
     * @dev Update subscription duration (only owner)
     * @param newDuration New duration in seconds
     */
    function setSubscriptionDuration(uint256 newDuration) external;

    /**
     * @dev Update treasury receiver (only owner)
     * @param newTreasury New treasury address
     */
    function setTreasuryReceiver(address newTreasury) external;

    /**
     * @dev Emergency pause subscriptions (only owner)
     */
    function pause() external;

    /**
     * @dev Resume subscriptions (only owner)
     */
    function unpause() external;

    /**
     * @dev Check if contract is paused
     * @return bool True if paused
     */
    function paused() external view returns (bool);
}
