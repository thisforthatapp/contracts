// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/TFTV1Escrow.sol";

contract DeployTFTV1Escrow is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address feeRecipient = 0x1234567890123456789012345678901234567890; // Replace with actual fee recipient address

        vm.startBroadcast(deployerPrivateKey);

        TFTV1Escrow escrow = new TFTV1Escrow(feeRecipient);

        console.log("TFTV1Escrow deployed to:", address(escrow));

        vm.stopBroadcast();
    }
}