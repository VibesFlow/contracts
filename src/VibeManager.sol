// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IVibeFactory.sol";
import "./Delegation.sol";

/**
 * @title VibeManager
 * @dev Manages post-creation operations for vibestreams, including delegation via proxies.
 * This contract is upgradeable and is the single point of contact for permissioned actions.
 */
contract VibeManager is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // Address of the main VibeFactory
    IVibeFactory public vibeFactory;
    
    // Address of the master implementation for our delegation proxies
    address public delegationContract;
    
    // Address of the CreationWrapper contract that can create delegation proxies on behalf of users
    address public creationWrapper;

    // Mapping from vibeId to its dedicated delegation proxy contract
    mapping(uint256 => address) public vibeDelegationProxy;
    
    // Mapping to store who is the authorized delegate for an vibe's proxy
    mapping(uint256 => address) public vibeDelegates;

    // Global whitelist for scope agents - these addresses can modify ANY vibestream
    mapping(address => bool) public globalWhitelist;

    // --- Events ---
    event GlobalWhitelistUpdated(address indexed agent, bool indexed whitelisted);
    event DelegationProxyCreated(uint256 indexed vibeId, address proxyAddress, address indexed delegatee);
    event DelegateUpdated(uint256 indexed vibeId, address indexed newDelegatee);
    event CreationWrapperUpdated(address indexed newCreationWrapper);

    // --- Errors ---
    error OnlyVibeCreator();
    error ProxyAlreadyExists();
    error NotAuthorized();
    error InvalidAddress();
    error OnlyCreationWrapper();

    /**
     * @dev Initializes the VibeManager.
     */
    function initialize(address _owner, address _vibeFactoryAddress) public initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();
        vibeFactory = IVibeFactory(_vibeFactoryAddress);
        
        // Deploy the master implementation for our delegation contract
        // This is a one-time deployment. All proxies will point to this logic.
        delegationContract = address(new Delegation());
    }

    /**
     * @dev Sets the CreationWrapper contract address. Only owner can call this.
     */
    function setCreationWrapper(address _creationWrapper) external onlyOwner {
        if (_creationWrapper == address(0)) {
            revert InvalidAddress();
        }
        creationWrapper = _creationWrapper;
        emit CreationWrapperUpdated(_creationWrapper);
    }

    /**
     * @dev Adds or removes an address from the global whitelist. Only owner can call this.
     * Whitelisted addresses can modify metadata for ANY vibe without per-vibe delegation.
     */
    function setGlobalWhitelist(address agent, bool whitelisted) external onlyOwner {
        if (agent == address(0)) {
            revert InvalidAddress();
        }
        globalWhitelist[agent] = whitelisted;
        emit GlobalWhitelistUpdated(agent, whitelisted);
    }

    /**
     * @dev Batch whitelist multiple agents at once. Only owner can call this.
     */
    function batchSetGlobalWhitelist(address[] calldata agents, bool whitelisted) external onlyOwner {
        for (uint256 i = 0; i < agents.length; i++) {
            if (agents[i] != address(0)) {
                globalWhitelist[agents[i]] = whitelisted;
                emit GlobalWhitelistUpdated(agents[i], whitelisted);
            }
        }
    }

    /**
     * @dev Deploys a lightweight, clonable proxy for an vibe to handle delegation.
     * Only the creator of the vibestream can initiate this.
     * @param vibeId The ID of the vibestream to create a delegation proxy for.
     * @param delegatee The address that will be granted delegation powers.
     */
    function createDelegationProxy(uint256 vibeId, address delegatee) external {
        // 1. Authorization Check: Only the original creator of the NFT can set up delegation.
        if (vibeFactory.ownerOf(vibeId) != msg.sender) {
            revert OnlyVibeCreator();
        }
        if (vibeDelegationProxy[vibeId] != address(0)) {
            revert ProxyAlreadyExists();
        }
        if (delegatee == address(0)) {
            revert InvalidAddress();
        }

        // 2. Deploy Proxy: Use the cheaper Clones library to deploy a minimal proxy.
        // This proxy points to 'delegationContract'.
        address proxy = Clones.clone(delegationContract);
        
        // 3. Initialize Proxy: Set the initial state of the new proxy contract.
        Delegation(proxy).initialize(vibeId, address(vibeFactory), delegatee);

        // 4. Store State
        vibeDelegationProxy[vibeId] = proxy;
        vibeDelegates[vibeId] = delegatee;

        emit DelegationProxyCreated(vibeId, proxy, delegatee);
    }

    /**
     * @dev Deploys a delegation proxy on behalf of a user. Only the CreationWrapper can call this.
     * This allows the CreationWrapper to create vibestreams and set up delegation in a single transaction.
     * @param vibeId The ID of the vibestream to create a delegation proxy for.
     * @param vibeCreator The address of the vibe creator (who owns the NFT).
     * @param delegatee The address that will be granted delegation powers.
     */
    function createDelegationProxyForUser(
        uint256 vibeId, 
        address vibeCreator, 
        address delegatee
    ) external {
        // 1. Authorization Check: Only the CreationWrapper contract can call this
        if (msg.sender != creationWrapper) {
            revert OnlyCreationWrapper();
        }
        
        // 2. Verify the vibeCreator actually owns the NFT
        if (vibeFactory.ownerOf(vibeId) != vibeCreator) {
            revert OnlyVibeCreator();
        }
        
        if (vibeDelegationProxy[vibeId] != address(0)) {
            revert ProxyAlreadyExists();
        }
        if (delegatee == address(0)) {
            revert InvalidAddress();
        }

        // 3. Deploy Proxy: Use the cheaper Clones library to deploy a minimal proxy.
        // This proxy points to 'delegationContract'.
        address proxy = Clones.clone(delegationContract);
        
        // 4. Initialize Proxy: Set the initial state of the new proxy contract.
        Delegation(proxy).initialize(vibeId, address(vibeFactory), delegatee);

        // 5. Store State
        vibeDelegationProxy[vibeId] = proxy;
        vibeDelegates[vibeId] = delegatee;

        emit DelegationProxyCreated(vibeId, proxy, delegatee);
    }

    /**
     * @dev Main function to update an vibestream's metadata.
     * Checks if the caller is the creator, authorized delegate, or globally whitelisted.
     */
    function updateMetadata(uint256 vibeId, string memory newMetadataURI) external {
        // Authorization: Caller must be the original creator, registered delegate, or globally whitelisted
        if (vibeFactory.ownerOf(vibeId) != msg.sender && 
            vibeDelegates[vibeId] != msg.sender && 
            !globalWhitelist[msg.sender]) {
            revert NotAuthorized();
        }
        
        // If authorized, this contract calls the VibeFactory to perform the state change.
        _authorize(vibeId);
        vibeFactory.setMetadataURI(vibeId, newMetadataURI);
    }
    
    function updateReservePrice(uint256 vibeId, uint256 newReservePrice) external {
        // Authorization: Caller must be the original creator, registered delegate, or globally whitelisted
        if (vibeFactory.ownerOf(vibeId) != msg.sender && 
            vibeDelegates[vibeId] != msg.sender && 
            !globalWhitelist[msg.sender]) {
            revert NotAuthorized();
        }
        
        _authorize(vibeId);
        vibeFactory.setReservePrice(vibeId, newReservePrice);
    }

    function finalizeRTA(uint256 vibeId) external {
        // Check authorization: only creator, delegatee, or globally whitelisted can finalize
        if (vibeFactory.ownerOf(vibeId) != msg.sender && 
            vibeDelegates[vibeId] != msg.sender && 
            !globalWhitelist[msg.sender]) {
            revert NotAuthorized();
        }
        
        // Finalize and transfer the NFT
        vibeFactory.finalizeAndTransfer(vibeId);
    }

    // --- Internal Functions ---
    
    /**
     * @dev Internal function to authorize access to vibestream operations.
     * Checks if the caller is the vibestream owner, authorized delegate, or globally whitelisted.
     */
    function _authorize(uint256 vibeId) internal view {
        if (vibeFactory.ownerOf(vibeId) != msg.sender && 
            vibeDelegates[vibeId] != msg.sender && 
            !globalWhitelist[msg.sender]) {
            revert NotAuthorized();
        }
    }

    // --- Other Management Functions ---
    
    function updateDelegate(uint256 vibeId, address newDelegatee) external {
        if (vibeFactory.ownerOf(vibeId) != msg.sender) {
            revert OnlyVibeCreator();
        }
        if (newDelegatee == address(0)) {
            revert InvalidAddress();
        }
        vibeDelegates[vibeId] = newDelegatee;
        emit DelegateUpdated(vibeId, newDelegatee);
    }

    // This contract itself is upgradeable.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}