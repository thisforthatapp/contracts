// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/TFTV1Escrow.sol";
import "../test/MockERC20.sol";

contract InteractWithTFTV1Escrow is Script {
    TFTV1Escrow escrow;
    MockERC20 mockToken;

    function setUp() public {
        escrow = TFTV1Escrow(0x... /* deployed escrow address */);
        mockToken = new MockERC20("TestToken", "TTK");
    }

    function run() public {
        uint256 privateKey1 = vm.envUint("PRIVATE_KEY_1");
        uint256 privateKey2 = vm.envUint("PRIVATE_KEY_2");
        address addr1 = vm.addr(privateKey1);
        address addr2 = vm.addr(privateKey2);

        // Create trade
        vm.startBroadcast(privateKey1);
        address[] memory participants = new address[](2);
        participants[0] = addr1;
        participants[1] = addr2;
        uint256 tradeId = escrow.createTrade(participants);
        vm.stopBroadcast();

        // Mint and approve tokens
        mockToken.mint(addr1, 100 ether);
        
        vm.startBroadcast(privateKey1);
        mockToken.approve(address(escrow), 100 ether);
        escrow.depositAsset{value: escrow.flatFee()}(tradeId, address(mockToken), 0, 100 ether, false);
        escrow.confirmTrade(tradeId);
        vm.stopBroadcast();

        vm.startBroadcast(privateKey2);
        escrow.depositAsset{value: escrow.flatFee()}(tradeId, address(0), 0, 0, false);
        escrow.confirmTrade(tradeId);
        vm.stopBroadcast();

        // Check final balances
        console.log("Addr1 token balance:", mockToken.balanceOf(addr1));
        console.log("Addr2 token balance:", mockToken.balanceOf(addr2));
    }
}