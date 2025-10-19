// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVibeManager {
    function createDelegationProxy(uint256 vibeId, address delegatee) external;
    function createDelegationProxyForUser(uint256 vibeId, address vibeCreator, address delegatee) external;
    function updateMetadata(uint256 vibeId, string memory newMetadataURI) external;
    function finalizeVibestream(uint256 vibeId) external;
    function setVibeWrapper(address _vibeWrapper) external;
}