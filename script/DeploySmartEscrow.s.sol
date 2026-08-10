// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import { SmartEscrow } from "../src/SmartEscrow.sol";
import { Script } from "forge-std/Script.sol";

contract DeploySmartEscrow is Script {
    function run() external returns (SmartEscrow escrow) {
        address client = vm.envAddress("CLIENT_ADDRESS");
        address contractor = vm.envAddress("CONTRACTOR_ADDRESS");
        address arbiter = vm.envAddress("ARBITER_ADDRESS");
        uint256 requiredFunding = vm.envUint("REQUIRED_FUNDING_WEI");

        vm.startBroadcast();
        escrow = new SmartEscrow(client, contractor, arbiter, requiredFunding);
        vm.stopBroadcast();
    }
}
