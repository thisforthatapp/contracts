// forge script script/DeployTFTEscrow.s.sol:DeployTFTEscrow --rpc-url http://localhost:8545 --broadcast
// File: script/DeployTFTEscrow.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/TFTEscrow.sol";
// import "../test/mocks/MockERC20.sol";
// import "../test/mocks/MockERC721.sol";
// import "../test/mocks/MockERC1155.sol";

contract DeployTFTEscrow is Script {
    function run() external {
        string memory pk = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
        uint256 deployerPrivateKey = vm.parseUint(pk);
        vm.startBroadcast(deployerPrivateKey);

        TFTEscrow escrow = new TFTEscrow();

        // Deploy mock tokens for testing
        // MockERC20 erc20 = new MockERC20("Mock ERC20", "MERC20");
        // MockERC721 erc721 = new MockERC721("Mock ERC721", "MERC721");
        // MockERC1155 erc1155 = new MockERC1155();

        vm.stopBroadcast();

        console.log("TFTEscrow deployed at:", address(escrow));
        // console.log("MockERC20 deployed at:", address(erc20));
        // console.log("MockERC721 deployed at:", address(erc721));
        // console.log("MockERC1155 deployed at:", address(erc1155));
    }
}
