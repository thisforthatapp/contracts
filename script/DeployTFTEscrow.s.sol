// forge script script/DeployTFTEscrow.s.sol:DeployTFTEscrow --rpc-url http://localhost:8545 --broadcast
// File: script/DeployTFTEscrow.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/TFTEscrow.sol";

contract DeployTFTEscrow is Script {
    function run() external {
        string memory pk = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
        uint256 deployerPrivateKey = vm.parseUint(pk);
        vm.startBroadcast(deployerPrivateKey);
        TFTEscrow escrow = new TFTEscrow();
        vm.stopBroadcast();
        console.log("TFTEscrow deployed at:", address(escrow));
    }
}
