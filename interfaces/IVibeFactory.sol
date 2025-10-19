// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/interfaces/IERC721.sol";

interface IVibeFactory is IERC721 {
    struct VibeData {
        address creator;        // 20 bytes
        address KioskAddress;   // 20 bytes (packed in slot 1)
        address ppmAddress; // 20 bytes (packed in slot 2) 
        uint96 startDate;       // 12 bytes (packed with creator in slot 0)
        bool finalized;
        string metadataURI;     // separate slot
        string mode;
    }

    function createVibestream(
        uint256 startDate,
        string calldata metadataURI,
        string calldata mode,
        uint256 ticketsAmount,
        uint256 ticketPrice
    ) external returns (uint256 vibeId);

    function createVibestreamForCreator(
        address creator,
        uint256 startDate,
        string calldata metadataURI,
        string calldata mode,
        uint256 ticketsAmount,
        uint256 ticketPrice
    ) external returns (uint256 vibeId);

    function deployPPMForVibestream(
        uint256 vibeId,
        uint256 scope,
        string calldata description
    ) external returns (address ppmAddress);

    function getPPMContract(uint256 vibeId) external view returns (address);
    function getVibeKiosk(uint256 vibeId) external view returns (address);
    function getVibestream(uint256 vibeId) external view returns (VibeData memory);
    function totalVibestreams() external view returns (uint256);
    function getCreatorVibestreams(address creator) external view returns (uint256[] memory);
    function getAllVibeKiosks() external view returns (uint256[] memory vibeIds, address[] memory kioskAddresses);
    
    // VibeManager functions
    function setMetadataURI(uint256 vibeId, string memory newMetadataURI) external;
    function setReservePrice(uint256 vibeId, uint256 newReservePrice) external;
    function finalizeAndTransfer(uint256 vibeId) external;

    event VibestreamCreated(
        uint256 indexed vibeId,
        address indexed creator,
        uint256 startDate,
        string metadataURI,
        string mode,
        address vibeKioskAddress
    );

    event PPMDeployed(
        uint256 indexed vibeId,
        address indexed creator,
        address ppmContract,
        uint256 scope
    );
}