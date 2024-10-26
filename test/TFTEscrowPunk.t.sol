// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/TFTEscrow.sol";

interface ICryptoPunksMarket {
    function transferPunk(address to, uint256 punkIndex) external;
    function punkIndexToAddress(uint256 punkIndex) external view returns (address);
    function punkNoLongerForSale(uint256 punkIndex) external;
}

contract TFTEscrowPunk is Test {
    TFTEscrow escrow;
    ICryptoPunksMarket punks;
    address constant PUNK_OWNER = 0x3924b7681c6110fCd3628164388c3307F79d1059;
    uint96 constant PUNK_ID = 5577;
    
    function setUp() public {
        escrow = new TFTEscrow();
        punks = ICryptoPunksMarket(escrow.CRYPTOPUNKS_ADDRESS());
        
        // Setup for forked environment
        vm.deal(PUNK_OWNER, 100 ether);
        
        // Verify ownership
        address currentOwner = punks.punkIndexToAddress(PUNK_ID);
        console.log("Current owner of punk %s: %s", PUNK_ID, currentOwner);
        console.log("Expected owner: %s", PUNK_OWNER);
        require(currentOwner == PUNK_OWNER, "Wrong punk owner");
    }

    function testCryptoPunkTrade() public {
        // Call our external function with the punk owner address
        vm.prank(PUNK_OWNER);
        this.executeTrade();
    }
    
    function executeTrade() external {
        console.log("Current msg.sender:", msg.sender);
        require(msg.sender == PUNK_OWNER, "Wrong sender");
        
        address[] memory participants = new address[](2);
        participants[0] = msg.sender; // Use actual sender
        participants[1] = address(0xBEEF);
        
        TFTEscrow.Asset[] memory assets = new TFTEscrow.Asset[](1);
        assets[0] = TFTEscrow.Asset({
            token: escrow.CRYPTOPUNKS_ADDRESS(),
            recipient: address(0xBEEF),
            depositor: address(0),
            tokenId: PUNK_ID,
            amount: 1,
            assetType: TFTEscrow.AssetType.CryptoPunk,
            isDeposited: false
        });
        
        uint256 tradeId = escrow.createTrade(participants, assets);
        console.log("Trade created with ID:", tradeId);

        // vm.prank(PUNK_OWNER);
        hoax(PUNK_OWNER);
        console.log("About to call depositAsset as:", msg.sender);
        escrow.depositAsset(
            tradeId,
            escrow.CRYPTOPUNKS_ADDRESS(),
            PUNK_ID,
            1,
            TFTEscrow.AssetType.CryptoPunk
        );
        
        // Verify final ownership
        assertEq(punks.punkIndexToAddress(PUNK_ID), address(0xBEEF));
    }
}