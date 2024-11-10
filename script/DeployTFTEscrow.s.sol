// forge script script/DeployTFTEscrow.s.sol:DeployTFTEscrow --rpc-url http://localhost:8545 --broadcast
// File: script/DeployTFTEscrow.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/TFTEscrow.sol";

contract DeployTFTEscrow is Script {
    function run() external {
        // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast();
        TFTEscrow escrow = new TFTEscrow();
        vm.stopBroadcast();

        console.log("TFTEscrow deployed at:", address(escrow));
    }
}
