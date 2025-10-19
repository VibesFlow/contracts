// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Create2.sol";
import "../VibeKiosk.sol";
import "../PPM.sol";
import "../../interfaces/IDistributor.sol";

/**
 * @title VibeFactoryLib
 * @dev Library containing deployment logic for VibeFactory
 * Reduces main contract size while maintaining exact functionality
 */
library VibeFactoryLib {
    /**
     * @dev Deploy VibeKiosk for a Vibestream using CREATE2
     */
    function deployVibeKiosk(
        uint256 vibeId,
        address factoryAddress,
        address creator,
        uint256 ticketsAmount,
        uint256 ticketPrice,
        string memory artCategory,
        address treasuryReceiver
    ) external returns (address) {
        bytes memory bytecode = abi.encodePacked(
            type(VibeKiosk).creationCode,
            abi.encode(vibeId, factoryAddress, creator, ticketsAmount, ticketPrice, artCategory, treasuryReceiver)
        );
        bytes32 salt = keccak256(abi.encodePacked(vibeId, "ticketkiosk"));
        return Create2.deploy(0, salt, bytecode);
    }

    /**
     * @dev Deploy PPM contract for a vibestream using CREATE2
     */
    function deployPPM(
        uint256 vibeId,
        address factoryAddress,
        address creator,
        uint256 price,
        address distributorContract
    ) external returns (address) {
        
        bytes memory bytecode = abi.encodePacked(
            type(PPM).creationCode,
            abi.encode(
                vibeId,
                factoryAddress,
                creator,
                distributorContract
            )
        );
        bytes32 salt = keccak256(abi.encodePacked(vibeId, "ppm"));
        return Create2.deploy(0, salt, bytecode);
    }

    /**
     * @dev Register vibestream with external contracts
     */
    function registerWithExternalContracts(
        uint256 vibeId,
        address creator,
        uint256 startDate,
        uint256 mode,
        address distributorContract
    ) external {
        // Register with Distributor
        IDistributor(distributorContract).registerVibestream(vibeId, creator);
    }

    /**
     * @dev Register PPM with Distributor
     */
    function registerPPMWithDistributor(
        uint256 vibeId,
        address ppmAddress,
        address distributorContract
    ) external {
        IDistributor(distributorContract).enablePPMFromContract(vibeId, ppmAddress);
    }
}
