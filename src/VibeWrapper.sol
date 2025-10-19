// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IVibeFactory.sol";
import "../interfaces/IVibeManager.sol";

contract CreationWrapper {
    IVibeFactory public immutable vibeFactory;
    IVibeManager public immutable vibeManager;

    constructor(address _factory, address _manager) {
        vibeFactory = IVibeFactory(_factory);
        vibeManager = IVibeManager(_manager);
    }

    /**
     * @dev Bundles vibestream creation and proxy deployment into a single transaction.
     * The user calls this function once.
     */
    function createVibestreamAndDelegate(
        // Params for VibeFactory.createVibestream
        uint256 startDate,
        string calldata metadataURI,
        string calldata mode,
        uint256 ticketsAmount,
        uint256 ticketPrice,
        // Param for VibeManager.createDelegationProxyForUser
        address delegatee
    ) external {
        // 1. Call VibeFactory to create the vibestream for the user and get the new vibeId
        uint256 newVibeId = vibeFactory.createVibestreamForCreator(
            msg.sender, // The user who called this function
            startDate,
            metadataURI,
            mode,
            ticketsAmount,
            ticketPrice
        );

        // 2. Call VibeManager to create the delegation proxy for the new vibestream
        // Use the new function that allows the CreationWrapper to create proxies on behalf of users
        if (delegatee != address(0)) {
            vibeManager.createDelegationProxyForUser(newVibeId, msg.sender, delegatee);
        }
    }
}
