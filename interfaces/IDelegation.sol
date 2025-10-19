// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDelegation {
    /**
     * @dev Initializes the delegation contract with immutable data.
     * @param vibeId The vibestream this delegation contract is for.
     * @param factory The address of the main VibeFactory.
     * @param delegatee The address being granted delegation permissions.
     */
    function initialize(uint256 vibeId, address factory, address delegatee) external;
}