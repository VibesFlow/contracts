// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/EventFactoryLib.sol";
import "../interfaces/IDistributor.sol";
import "../interfaces/IEventManager.sol";
import "../interfaces/ILiveTipping.sol";

/**
 * @title VibeFactory
 * @dev A lightweight, modular ERC721 NFT factory for Vibestream NFTs.
 * Responsibilities:
 * 1. Mint Vibestream NFTs (ERC721).
 * 2. Deploy a unique VibeKiosk for each vibestream.
 * 3. Act as a central registry linking vibeId to its data and associated contracts.
 * All other logic (PPM, Event Management) is handled by standalone contracts.
 */
contract VibeFactory is ERC721URIStorage, Ownable {
    struct VibeData {
        address creator;        // 20 bytes
        address KioskAddress;   // 20 bytes (packed in slot 1)
        address PPMAddress; // 20 bytes (packed in slot 2) 
        uint96 startDate;       // 12 bytes (packed with creator in slot 0)
        bool finalized;         // 1 byte (packed with reservePrice)
        string metadataURI;     // separate slot
        string mode;     // separate slot
    }

    // State variables
    mapping(uint256 => VibeData) public vibestreams;
    mapping(address => uint256[]) public creatorVibestreams;
    
    uint256 public currentVibeId;

    // Contract addresses
    address public vibeManagerContract;
    address public distributorContract;
    address public treasuryReceiver;

    // Vibestreams
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
    event MetadataUpdated(uint256 indexed vibeId, string newMetadataURI);
    event VibeFinalized(uint256 indexed vibeId);
    
    // Custom errors
    error InvalidInput();
    error DeploymentFailed();
    error OnlyVibeManager();
    error VibeAlreadyFinalized();
    error StartDateHasPassed();
    error EventNotEndedYet();
    error AlreadyInitialized();
    error OnlyOwner();

    /**
     * @dev Constructor that initializes the contract
     */
    constructor() ERC721("Real-Time Asset", "RTA") Ownable(msg.sender) {
        // Initialize with deployer as owner initially
        // The actual owner will be set during deployment
    }

    /**
     * @dev Initializes the contract addresses after deployment
     */
    function initialize(
        address _owner,
        address _vibeManager,
        address _distributor,
        address _treasuryReceiver
    ) external {
        if (vibeManagerContract != address(0)) revert AlreadyInitialized();
        if (msg.sender != owner()) revert OnlyOwner();
        
        vibeManagerContract = _vibeManager;
        distributorContract = _distributor;
        treasuryReceiver = _treasuryReceiver;
        
        // Transfer ownership to the intended owner if different
        if (_owner != owner()) {
            _transferOwnership(_owner);
        }
    }


    /**
     * @dev Creates a new Vibestream and deploys its associated VibeKiosk.
     */
    function createVibestream(
        uint256 startDate,
        string calldata metadataURI,
        string calldata mode,
        uint256 ticketsAmount,
        uint256 ticketPrice
    ) external returns (uint256 vibeId) {
        return createVibestreamForCreator(
            msg.sender,
            startDate,
            metadataURI,
            mode,
            ticketsAmount,
            ticketPrice
        );
    }

    /**
     * @dev Creates a new Vibestream for a specific creator and deploys its associated VibeKiosk.
     * This version allows specifying the creator address, useful for wrapper contracts.
     */
    function createVibestreamForCreator(
        address creator,
        uint256 startDate,
        string calldata metadataURI,
        string calldata mode,
        uint256 ticketsAmount,
        uint256 ticketPrice
    ) public returns (uint256 vibeId) {
        // Validate inputs fit in optimized storage
        require(startDate <= type(uint96).max, "Start date too large");
        uint256 newVibeId = currentVibeId++;

        // 1. Mint Vibestream NFT to the creator
        _safeMint(creator, newVibeId);
        _setTokenURI(newVibeId, metadataURI);

        // 2. Deploy VibeKiosk for this vibestream using CREATE2 for a deterministic address
        address vibeKioskAddress = VibeFactoryLib.deployVibeKiosk(
            newVibeId, address(this), creator, ticketsAmount, ticketPrice, mode, treasuryReceiver
        );
        if (vibeKioskAddress == address(0)) revert DeploymentFailed();

        // 3. Store Vibestream data (optimized storage packing)
        vibestreams[newVibeId] = VibeData({
            creator: creator,
            KioskAddress: vibeKioskAddress,
            PPMAddress: address(0), // Will be set when PPM is activated
            startDate: uint96(startDate),
            finalized: false,
            metadataURI: metadataURI,
            mode: mode
        });

        creatorVibestream[creator].push(newVibeId);

        // 4. Register with external contracts using library
        VibeFactoryLib.registerWithExternalContracts(
            newVibeId,
            creator,
            startDate,
            distributorContract,
        );

        emit VibestreamCreated(newVibeId, creator, startDate, metadataURI, mode, vibeKioskAddress);
        
        return newVibeId;
    }

    // --- Functions callable only by VibeManager ---

    /**
     * @dev Allows the authorized VibeManager contract to update the metadata URI.
     * The VibeManager is responsible for handling all permission logic (e.g., only creator or delegate).
     */
    function setMetadataURI(uint256 vibeId, string memory newMetadataURI) external {
        if (msg.sender != vibeManagerContract) revert OnlyVibeManager();
        if (vibestreams[vibeId].finalized) revert VibestreamAlreadyFinalized();
        
        vibestreams[vibeId].metadataURI = newMetadataURI;
        _setTokenURI(vibeId, newMetadataURI);
        
        emit MetadataUpdated(vibeId, newMetadataURI);
    }

    /**
     * @dev Allows the authorized VibeManager contract to finalize a Vibestream.
     */
    function setFinalized(uint256 vibeId) external {
        if (msg.sender != vibeManagerContract) revert OnlyVibeManager();
        if (vibestreams[vibeId].finalized) revert VibestreamAlreadyFinalized();

        vibestream[vibeId].finalized = true;
        emit VibestreamFinalized(vibeId);
    }
    
    /**
     * @dev Deploy PPM contract for a Vibestream (only by Vibestream creator)
     */
    function deployPPMForVibestream(
        uint256 vibeId
    ) external returns (address PPMAddress) {
        require(events[vibeId].creator == msg.sender, "Only Vibestream creator can deploy PPM");
        require(events[vibeId].PPMAddress == address(0), "PPM already deployed");

        // Deploy PPM contract using CREATE2 for deterministic address
        PPMAddress = VibeFactoryLib.deployPPM(
            vibeId, address(this), msg.sender, distributorContract
        );
        if (PPMAddress == address(0)) revert DeploymentFailed();

        // Update event data
        vibestreams[vibeId].curationAddress = curationAddress;

        // Register curation with Distributor using library
        EventFactoryLib.registerCurationWithDistributor(vibeId, curationAddress, distributorContract);

        emit CurationDeployed(vibeId, msg.sender, curationAddress, scope);
        
        return curationAddress;
    }

    /**
     * @dev Returns the VibeKiosk address for a specific Vibestream.
     */
    function getVibeKiosk(uint256 vibeId) external view returns (address) {
        return vibestreams[vibeId].KioskAddress;
    }

    /**
     * @dev Returns the PPM address for a specific Vibestream.
     */
    function getPPMContract(uint256 vibeId) external view returns (address) {
        return vibestreams[vibeId].PPMAddress;
    }

    /**
     * @dev Returns all VibeKiosk addresses and their corresponding Vibe IDs.
     */
    function getAllVibeKiosks() external view returns (uint256[] memory vibeIds, address[] memory kioskAddresses) {
        uint256 totalVibestreamsCount = currentVibeId;
        vibeIds = new uint256[](totalVibestreamsCount);
        kioskAddresses = new address[](totalVibestreamsCount);
        
        for (uint256 i = 0; i < totalVibestreamsCount; i++) {
            vibeIds[i] = i;
            kioskAddresses[i] = vibestreams[i].KioskAddress;
        }
        
        return (vibeIds, kioskAddresses);
    }

    /**
     * @dev Returns the full data struct for a given vibestream.
     * For other contracts to easily get vibestream data.
     */
    function getVibestream(uint256 vibeId) external view returns (VibeData memory) {
        return vibestreams[vibeId];
    }

    /**
     * @dev Returns the total number of vibestreams created.
     */
    function totalVibestreams() external view returns (uint256) {
        return currentVibeId;
    }

    /**
     * @dev Returns the vibestreams created by a specific creator.
     */
    function getCreatorVibestreams(address creator) external view returns (uint256[] memory) {
        return creatorVibestreams[creator];
    }

    /**
     * @dev Returns the addresses of the standalone contracts.
     */
    function getStandaloneContracts() external view returns (address, address, address, address) {
        return (address(0), address(0), distributorContract);
    }

    // Internal & View Functions

    function _baseURI() internal pure override returns (string memory) {
        return ""; // URIs are set individually
    }

    // Override required by Solidity for multiple inheritance
    function tokenURI(uint256 tokenId) public view override(ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}