// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// --- Import contract interfaces and implementations ---
// Note: Adjust paths if your project structure is different.
import {VibeFactory} from "../src/VibeFactory.sol";
import {VibeManager} from "../src/VibeManager.sol";
import {Delegation} from "../src/Delegation.sol";
import {Distributor} from "../src/Distributor.sol";
import {VibestreamWrapper} from "../src/VibestreamWrapper.sol";

contract Deploy is Script {
    // --- Configuration ---
    // forge script Deploy --rpc-url <rpc> --broadcast
    address treasuryReceiver = vm.envAddress("TREASURY_RECEIVER");
    
    // Proxy Agent Proxy Addresses - These will be automatically whitelisted
    address constant PLANNER_PROXY_ADDRESS = 0xF2aC15F3db8Fd24c83494fc7B2131A74DFCAA07b;
    address constant PROMOTER_PROXY_ADDRESS = 0x27B8c4E2E6AaF49527b62278D834497BA344b90D;
    address constant PRODUCER_PROXY_ADDRESS = 0xEb215ba313c12D58417674c810bAcd6C6badAD61;

    // --- Deployment artifacts ---
    ProxyAdmin public proxyAdmin;

    // Implementation contracts
    VibeFactory public vibeFactoryImpl;
    VibeManager public vibeManagerImpl;
    Distributor public distributorImpl;

    // Final contract instances (proxies or direct addresses)
    VibeFactory public vibeFactory;
    VibeManager public vibeManager;
    Distributor public distributor;
    // Note: No global ppm instance - deployed per-vibestream via VibeFactory
    VibestreamWrapper public vibestreamWrapper;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        console2.log("Deploying contracts with address:", deployerAddress);
        console2.log("Treasury receiver:", treasuryReceiver);
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy ProxyAdmin: Manages all proxy upgrades
        proxyAdmin = new ProxyAdmin(deployerAddress);
        
        // 2. Deploy all implementation contracts first
        _deployImplementations();
        
        // 3. Deploy proxies and final contracts, wiring them up
        _deployAndInitializeContracts(deployerAddress);

        // 4. Deploy the utility VibestreamWrapper
        vibestreamWrapper = new VibestreamWrapper(address(vibeFactory), address(vibeManager));
        
        // 5. Configure VibeManager with VibestreamWrapper address
        vibeManager.setVibestreamWrapper(address(vibestreamWrapper));
        
        // 6. Whitelist proxy agent proxy addresses for global authorization
        _whitelistProxyAgents();
        
        vm.stopBroadcast();
        _logDeploymentAddresses();
    }
    
    function _deployImplementations() internal {
        console2.log("\nDeploying implementations...");
        vibeFactoryImpl = new VibeFactory();
        vibeManagerImpl = new VibeManager();
        distributorImpl = new Distributor();
        
        console2.log("  VibeFactory Impl:", address(vibeFactoryImpl));
        console2.log("  VibeManager Impl:", address(vibeManagerImpl));
        console2.log("  Distributor Impl:", address(distributorImpl));
        console2.log("  Note: PPM contracts deployed per-vibestream (no global impl needed)");
    }
    
    function _deployAndInitializeContracts(address owner) internal {
        console2.log("\nDeploying proxies and initializing contracts...");

        // Deploy VibeFactory (non-upgradeable) FIRST to resolve circular dependencies
        // It's non-upgradeable by design to be a stable anchor for the system.
        vibeFactory = new VibeFactory();
        console2.log("VibeFactory deployed at:", address(vibeFactory));

        // Deploy VibeManager Proxy
        bytes memory vibeManagerInitData = abi.encodeWithSelector(VibeManager.initialize.selector, owner, address(vibeFactory));
        TransparentUpgradeableProxy vibeManagerProxy = new TransparentUpgradeableProxy(address(vibeManagerImpl), address(proxyAdmin), vibeManagerInitData);
        vibeManager = VibeManager(payable(address(vibeManagerProxy)));
        
        // Deploy Distributor Proxy with VibeFactory address and placeholders (ppm wired below)
        bytes memory distributorInitData = abi.encodeWithSelector(Distributor.initialize.selector, owner, address(vibeFactory), address(liveTipping), address(0), address(0), treasuryReceiver);
        TransparentUpgradeableProxy distributorProxy = new TransparentUpgradeableProxy(address(distributorImpl), address(proxyAdmin), distributorInitData);
        distributor = Distributor(payable(address(distributorProxy)));

        // Note: Individual PPM contracts are deployed per-vibestream ONLY when creators request ppm
        // via VibeFactory.deployPPMForVibestream() - same pattern as VibeKiosk deployment
        
        // Back-reference ppm implementation into Distributor (no global instance)
        distributor.updateContracts(address(0), address(0), address(0), address(0));

        // Initialize VibeFactory with deployed addresses
        vibeFactory.initialize(owner, address(vibeManager), address(distributor), address(liveTipping), treasuryReceiver);
        
        console2.log("All contracts deployed and initialized successfully.");
    }
    
    function _whitelistProxyAgents() internal {
        console2.log("\nWhitelisting proxy agent proxy addresses...");
        
        // Create array of proxy agent addresses
        address[] memory agents = new address[](3);
        agents[0] = AGENT_ZERO_PROXY_ADDRESS;
        agents[1] = AGENT_ONE_PROXY_ADDRESS;
        agents[2] = AGENT_TWO_PROXY_ADDRESS;
        
        // Batch whitelist all proxy agents
        vibeManager.batchSetGlobalWhitelist(agents, true);
        
        console2.log("  Agent Zero Agent:  ", AGENT_ZERO_PROXY_ADDRESS, "- WHITELISTED");
        console2.log("  Agent One Agent: ", AGENT_ONE_PROXY_ADDRESS_PROXY_ADDRESS, "- WHITELISTED");
        console2.log("  Agent Two Agent: ", AGENT_TWO_PROXY_ADDRESS_PROXY_ADDRESS, "- WHITELISTED");
        console2.log("Proxy agents whitelisted successfully.");
    }
    
    function _logDeploymentAddresses() internal view {
        console2.log("\n=== DEPLOYMENT SUMMARY ===");
        console2.log("ProxyAdmin:      ", address(proxyAdmin));
        console2.log("----------------------------------");
        console2.log("VibeFactory:    ", address(vibeFactory));
        console2.log("VibeManager:    ", address(vibeManager));
        console2.log("Distributor:     ", address(distributor));
        console2.log("Delegation Impl: ", vibeManager.delegationContract());
        console2.log("VibestreamWrapper: ", address(vibestreamWrapper));
        console2.log("----------------------------------");
        console2.log("WHITELISTED SCOPE AGENTS:");
        console2.log("  Planner:       ", PLANNER_PROXY_ADDRESS);
        console2.log("  Promoter:      ", PROMOTER_PROXY_ADDRESS);
        console2.log("  Producer:      ", PRODUCER_PROXY_ADDRESS);
        console2.log("----------------------------------");
        console2.log("Treasury:        ", treasuryReceiver);
        console2.log("=========================\n");
    }
}