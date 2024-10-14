// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "../src/TFTV1Escrow.sol";
import "../test/mocks/MockERC20.sol";
import "../test/mocks/MockERC721.sol";
import "../test/mocks/MockERC1155.sol";

contract SimulateTFTV1Escrow is Script {
    TFTV1Escrow escrow;
    MockERC20 erc20;
    MockERC721 erc721;
    MockERC1155 erc1155;

    address alice;
    address bob;

    function setUp() public {
        // Replace these addresses with the actual deployed contract addresses
        escrow = TFTV1Escrow(payable(vm.envAddress("ESCROW_ADDRESS")));
        erc20 = MockERC20(vm.envAddress("ERC20_ADDRESS"));
        erc721 = MockERC721(vm.envAddress("ERC721_ADDRESS"));
        erc1155 = MockERC1155(vm.envAddress("ERC1155_ADDRESS"));

        alice = vm.addr(vm.envUint("ALICE_PRIVATE_KEY"));
        bob = vm.addr(vm.envUint("BOB_PRIVATE_KEY"));
    }

    function run() external {
        uint256 alicePrivateKey = vm.envUint("ALICE_PRIVATE_KEY");
        uint256 bobPrivateKey = vm.envUint("BOB_PRIVATE_KEY");

        // Mint tokens to Alice and Bob
        vm.startBroadcast(alicePrivateKey);
        erc20.mint(alice, 1000 ether);
        erc721.mint(alice, 1);
        erc1155.mint(alice, 1, 100, "");
        vm.stopBroadcast();

        vm.startBroadcast(bobPrivateKey);
        erc20.mint(bob, 1000 ether);
        erc721.mint(bob, 2);
        erc1155.mint(bob, 2, 100, "");
        vm.stopBroadcast();

        // Create a trade
        vm.startBroadcast(alicePrivateKey);
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        TFTV1Escrow.Asset[] memory aliceAssets = new TFTV1Escrow.Asset[](3);
        aliceAssets[0] = TFTV1Escrow.Asset(address(erc20), 0, 100 ether, TFTV1Escrow.AssetType.ERC20, bob, false);
        aliceAssets[1] = TFTV1Escrow.Asset(address(erc721), 1, 1, TFTV1Escrow.AssetType.ERC721, bob, false);
        aliceAssets[2] = TFTV1Escrow.Asset(address(erc1155), 1, 50, TFTV1Escrow.AssetType.ERC1155, bob, false);

        TFTV1Escrow.Asset[] memory bobAssets = new TFTV1Escrow.Asset[](3);
        bobAssets[0] = TFTV1Escrow.Asset(address(erc20), 0, 50 ether, TFTV1Escrow.AssetType.ERC20, alice, false);
        bobAssets[1] = TFTV1Escrow.Asset(address(erc721), 2, 1, TFTV1Escrow.AssetType.ERC721, alice, false);
        bobAssets[2] = TFTV1Escrow.Asset(address(erc1155), 2, 25, TFTV1Escrow.AssetType.ERC1155, alice, false);

        TFTV1Escrow.Asset[][] memory allAssets = new TFTV1Escrow.Asset[][](2);
        allAssets[0] = aliceAssets;
        allAssets[1] = bobAssets;

        uint256 tradeId = escrow.createTrade(participants, allAssets, 1 days);
        console.log("Trade created with ID:", tradeId);

        // Alice deposits assets
        erc20.approve(address(escrow), 100 ether);
        erc721.setApprovalForAll(address(escrow), true);
        erc1155.setApprovalForAll(address(escrow), true);

        escrow.batchDepositAssets(tradeId);
        escrow.confirmTrade(tradeId);
        console.log("Alice deposited assets and confirmed trade");
        vm.stopBroadcast();

        // Bob deposits assets and confirms trade
        vm.startBroadcast(bobPrivateKey);
        erc20.approve(address(escrow), 50 ether);
        erc721.setApprovalForAll(address(escrow), true);
        erc1155.setApprovalForAll(address(escrow), true);

        escrow.batchDepositAssets(tradeId);
        escrow.confirmTrade(tradeId);
        console.log("Bob deposited assets and confirmed trade");
        vm.stopBroadcast();

        // Print final balances
        console.log("Final ERC20 balance of Alice:", erc20.balanceOf(alice));
        console.log("Final ERC20 balance of Bob:", erc20.balanceOf(bob));
        console.log("ERC721 token 1 owner:", erc721.ownerOf(1));
        console.log("ERC721 token 2 owner:", erc721.ownerOf(2));
        console.log("Final ERC1155 balance of Alice for token 1:", erc1155.balanceOf(alice, 1));
        console.log("Final ERC1155 balance of Alice for token 2:", erc1155.balanceOf(alice, 2));
        console.log("Final ERC1155 balance of Bob for token 1:", erc1155.balanceOf(bob, 1));
        console.log("Final ERC1155 balance of Bob for token 2:", erc1155.balanceOf(bob, 2));
    }
}