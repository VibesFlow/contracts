// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDistributor {
    function registerEvent(uint256 vibeId, address creator) external;
    function enablePPMFromContract(uint256 eventId, address ppmContract) external;
}