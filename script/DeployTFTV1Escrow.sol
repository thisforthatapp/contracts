// File: script/DeployTFTV1Escrow.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/TFTV1Escrow.sol";
import "../test/mocks/MockERC20.sol";
import "../test/mocks/MockERC721.sol";
import "../test/mocks/MockERC1155.sol";

contract DeployTFTV1Escrow is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");

        vm.startBroadcast(deployerPrivateKey);

        TFTV1Escrow escrow = new TFTV1Escrow(feeRecipient);

        // Deploy mock tokens for testing
        MockERC20 erc20 = new MockERC20("Mock ERC20", "MERC20");
        MockERC721 erc721 = new MockERC721("Mock ERC721", "MERC721");
        MockERC1155 erc1155 = new MockERC1155();

        vm.stopBroadcast();

        console.log("TFTV1Escrow deployed at:", address(escrow));
        console.log("MockERC20 deployed at:", address(erc20));
        console.log("MockERC721 deployed at:", address(erc721));
        console.log("MockERC1155 deployed at:", address(erc1155));
    }
}
