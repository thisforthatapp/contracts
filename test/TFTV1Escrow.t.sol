// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/TFTV1Escrow.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockERC721.sol";
import "./mocks/MockERC1155.sol";

contract TFTV1EscrowTest is Test {
    TFTV1Escrow public escrow;
    MockERC20 public mockERC20;
    MockERC721 public mockERC721;
    MockERC1155 public mockERC1155;
    MockERC20 public anotherERC20;
    MockERC721 public anotherERC721;
    MockERC1155 public anotherERC1155;

    address public owner;
    address public addr1;
    address public addr2;
    address public addr3;

    function setUp() public {
        escrow = new TFTV1Escrow();
        mockERC20 = new MockERC20("MockToken", "MTK");
        mockERC721 = new MockERC721("MockNFT", "MNFT");
        mockERC1155 = new MockERC1155();
        anotherERC20 = new MockERC20("AnotherToken", "ATK");
        anotherERC721 = new MockERC721("AnotherNFT", "ANFT");
        anotherERC1155 = new MockERC1155();

        owner = address(this);
        addr1 = address(0x1);
        addr2 = address(0x2);
        addr3 = address(0x3);

        // Mint some tokens for testing
        mockERC20.mint(addr1, 1000 ether);
        mockERC20.mint(addr2, 1000 ether);
        mockERC721.mint(addr1, 1);
        mockERC721.mint(addr2, 2);
        mockERC1155.mint(addr1, 1, 100, "");
        mockERC1155.mint(addr2, 2, 50, "");

        // Mint some "another" tokens for failure case testing
        anotherERC20.mint(addr1, 1000 ether);
        anotherERC721.mint(addr1, 1);
        anotherERC1155.mint(addr1, 1, 100, "");
    }

    function testCreateTrade() public {
        address[] memory participants = new address[](2);
        participants[0] = addr1;
        participants[1] = addr2;

        TFTV1Escrow.Asset[][] memory assets = new TFTV1Escrow.Asset[][](2);
        assets[0] = new TFTV1Escrow.Asset[](2);
        assets[1] = new TFTV1Escrow.Asset[](1);

        assets[0][0] = TFTV1Escrow.Asset({
            token: address(mockERC20),
            tokenId: 0,
            amount: 100 ether,
            assetType: TFTV1Escrow.AssetType.ERC20,
            recipient: addr2,
            isDeposited: false
        });

        assets[0][1] = TFTV1Escrow.Asset({
            token: address(mockERC1155),
            tokenId: 1,
            amount: 50,
            assetType: TFTV1Escrow.AssetType.ERC1155,
            recipient: addr2,
            isDeposited: false
        });

        assets[1][0] = TFTV1Escrow.Asset({
            token: address(mockERC721),
            tokenId: 2,
            amount: 1,
            assetType: TFTV1Escrow.AssetType.ERC721,
            recipient: addr1,
            isDeposited: false
        });

        uint256 tradeId = escrow.createTrade(participants, assets);

        (bool isActive, uint256 depositedAssetCount, uint256 totalAssetCount) = escrow.getTradeStatus(tradeId);
        assertTrue(isActive);
        assertEq(depositedAssetCount, 0);
        assertEq(totalAssetCount, 3);
    }

    function testDepositAssets() public {
        // Create a trade first
        address[] memory participants = new address[](2);
        participants[0] = addr1;
        participants[1] = addr2;

        TFTV1Escrow.Asset[][] memory assets = new TFTV1Escrow.Asset[][](2);
        assets[0] = new TFTV1Escrow.Asset[](2);
        assets[1] = new TFTV1Escrow.Asset[](1);

        assets[0][0] = TFTV1Escrow.Asset({
            token: address(mockERC20),
            tokenId: 0,
            amount: 100 ether,
            assetType: TFTV1Escrow.AssetType.ERC20,
            recipient: addr2,
            isDeposited: false
        });

        assets[0][1] = TFTV1Escrow.Asset({
            token: address(mockERC1155),
            tokenId: 1,
            amount: 50,
            assetType: TFTV1Escrow.AssetType.ERC1155,
            recipient: addr2,
            isDeposited: false
        });

        assets[1][0] = TFTV1Escrow.Asset({
            token: address(mockERC721),
            tokenId: 2,
            amount: 1,
            assetType: TFTV1Escrow.AssetType.ERC721,
            recipient: addr1,
            isDeposited: false
        });

        uint256 tradeId = escrow.createTrade(participants, assets);

        // Approve and deposit assets
        vm.startPrank(addr1);
        mockERC20.approve(address(escrow), 100 ether);
        escrow.depositAsset(tradeId, address(mockERC20), 0, 100 ether, TFTV1Escrow.AssetType.ERC20);
        mockERC1155.setApprovalForAll(address(escrow), true);
        escrow.depositAsset(tradeId, address(mockERC1155), 1, 50, TFTV1Escrow.AssetType.ERC1155);
        vm.stopPrank();

        vm.startPrank(addr2);
        mockERC721.approve(address(escrow), 2);
        escrow.depositAsset(tradeId, address(mockERC721), 2, 1, TFTV1Escrow.AssetType.ERC721);
        vm.stopPrank();

        // Check trade status
        (bool isActive, uint256 depositedAssetCount, uint256 totalAssetCount) = escrow.getTradeStatus(tradeId);
        assertFalse(isActive);
        assertEq(depositedAssetCount, 3);
        assertEq(totalAssetCount, 3);

        // Check balances after trade execution
        assertEq(mockERC20.balanceOf(addr2), 1100 ether);
        assertEq(mockERC721.ownerOf(2), addr1);
        assertEq(mockERC1155.balanceOf(addr2, 1), 50);
    }

    function testCancelTrade() public {
        // Create a trade first
        address[] memory participants = new address[](2);
        participants[0] = addr1;
        participants[1] = addr2;

        TFTV1Escrow.Asset[][] memory assets = new TFTV1Escrow.Asset[][](2);
        assets[0] = new TFTV1Escrow.Asset[](2);
        assets[1] = new TFTV1Escrow.Asset[](1);

        assets[0][0] = TFTV1Escrow.Asset({
            token: address(mockERC20),
            tokenId: 0,
            amount: 100 ether,
            assetType: TFTV1Escrow.AssetType.ERC20,
            recipient: addr2,
            isDeposited: false
        });

        assets[0][1] = TFTV1Escrow.Asset({
            token: address(mockERC1155),
            tokenId: 1,
            amount: 50,
            assetType: TFTV1Escrow.AssetType.ERC1155,
            recipient: addr2,
            isDeposited: false
        });

        assets[1][0] = TFTV1Escrow.Asset({
            token: address(mockERC721),
            tokenId: 2,
            amount: 1,
            assetType: TFTV1Escrow.AssetType.ERC721,
            recipient: addr1,
            isDeposited: false
        });

        uint256 tradeId = escrow.createTrade(participants, assets);

        // Deposit two assets
        vm.startPrank(addr1);
        mockERC20.approve(address(escrow), 100 ether);
        escrow.depositAsset(tradeId, address(mockERC20), 0, 100 ether, TFTV1Escrow.AssetType.ERC20);
        mockERC1155.setApprovalForAll(address(escrow), true);
        escrow.depositAsset(tradeId, address(mockERC1155), 1, 50, TFTV1Escrow.AssetType.ERC1155);
        vm.stopPrank();

        // Cancel trade
        vm.prank(addr2);
        escrow.cancelTrade(tradeId);

        // Check trade status
        (bool isActive, uint256 depositedAssetCount, uint256 totalAssetCount) = escrow.getTradeStatus(tradeId);
        assertFalse(isActive);
        assertEq(depositedAssetCount, 0);
        assertEq(totalAssetCount, 3);

        // Check balances after cancellation
        assertEq(mockERC20.balanceOf(addr1), 1000 ether);
        assertEq(mockERC721.ownerOf(2), addr2);
        assertEq(mockERC1155.balanceOf(addr1, 1), 100);
    }

    function testFailDepositIncorrectERC20() public {
        uint256 tradeId = _createBasicTrade();

        vm.startPrank(addr1);
        anotherERC20.approve(address(escrow), 100 ether);
        vm.expectRevert(TFTV1Escrow.AssetNotFound.selector);
        escrow.depositAsset(tradeId, address(anotherERC20), 0, 100 ether, TFTV1Escrow.AssetType.ERC20);
        vm.stopPrank();
    }

    function testFailDepositIncorrectERC721() public {
        uint256 tradeId = _createBasicTrade();

        vm.startPrank(addr2);
        anotherERC721.approve(address(escrow), 1);
        vm.expectRevert(TFTV1Escrow.AssetNotFound.selector);
        escrow.depositAsset(tradeId, address(anotherERC721), 1, 1, TFTV1Escrow.AssetType.ERC721);
        vm.stopPrank();
    }

    function testFailDepositIncorrectERC1155() public {
        uint256 tradeId = _createBasicTrade();

        vm.startPrank(addr1);
        anotherERC1155.setApprovalForAll(address(escrow), true);
        vm.expectRevert(TFTV1Escrow.AssetNotFound.selector);
        escrow.depositAsset(tradeId, address(anotherERC1155), 1, 50, TFTV1Escrow.AssetType.ERC1155);
        vm.stopPrank();
    }

    function testFailDepositIncorrectTokenId() public {
        uint256 tradeId = _createBasicTrade();

        vm.startPrank(addr2);
        mockERC721.approve(address(escrow), 3);
        vm.expectRevert(TFTV1Escrow.AssetNotFound.selector);
        escrow.depositAsset(tradeId, address(mockERC721), 3, 1, TFTV1Escrow.AssetType.ERC721);
        vm.stopPrank();
    }

    function testFailDepositIncorrectAmount() public {
        uint256 tradeId = _createBasicTrade();

        vm.startPrank(addr1);
        mockERC20.approve(address(escrow), 200 ether);
        vm.expectRevert(TFTV1Escrow.AssetNotFound.selector);
        escrow.depositAsset(tradeId, address(mockERC20), 0, 200 ether, TFTV1Escrow.AssetType.ERC20);
        vm.stopPrank();
    }

    function testFailDepositAssetTwice() public {
        uint256 tradeId = _createBasicTrade();

        vm.startPrank(addr1);
        mockERC20.approve(address(escrow), 200 ether);
        escrow.depositAsset(tradeId, address(mockERC20), 0, 100 ether, TFTV1Escrow.AssetType.ERC20);
        vm.expectRevert(TFTV1Escrow.AssetAlreadyDeposited.selector);
        escrow.depositAsset(tradeId, address(mockERC20), 0, 100 ether, TFTV1Escrow.AssetType.ERC20);
        vm.stopPrank();
    }

    function testFailDepositAfterTradeCompleted() public {
        uint256 tradeId = _createBasicTrade();

        // Complete the trade
        vm.prank(addr1);
        mockERC20.approve(address(escrow), 100 ether);
        escrow.depositAsset(tradeId, address(mockERC20), 0, 100 ether, TFTV1Escrow.AssetType.ERC20);

        vm.prank(addr2);
        mockERC721.approve(address(escrow), 2);
        escrow.depositAsset(tradeId, address(mockERC721), 2, 1, TFTV1Escrow.AssetType.ERC721);

        // Try to deposit after trade is completed
        vm.prank(addr1);
        mockERC1155.setApprovalForAll(address(escrow), true);
        vm.expectRevert(TFTV1Escrow.TradeNotActive.selector);
        escrow.depositAsset(tradeId, address(mockERC1155), 1, 50, TFTV1Escrow.AssetType.ERC1155);
    }

    function _createBasicTrade() internal returns (uint256) {
        address[] memory participants = new address[](2);
        participants[0] = addr1;
        participants[1] = addr2;

        TFTV1Escrow.Asset[][] memory assets = new TFTV1Escrow.Asset[][](2);
        assets[0] = new TFTV1Escrow.Asset[](2);
        assets[1] = new TFTV1Escrow.Asset[](1);

        assets[0][0] = TFTV1Escrow.Asset({
            token: address(mockERC20),
            tokenId: 0,
            amount: 100 ether,
            assetType: TFTV1Escrow.AssetType.ERC20,
            recipient: addr2,
            isDeposited: false
        });

        assets[0][1] = TFTV1Escrow.Asset({
            token: address(mockERC1155),
            tokenId: 1,
            amount: 50,
            assetType: TFTV1Escrow.AssetType.ERC1155,
            recipient: addr2,
            isDeposited: false
        });

        assets[1][0] = TFTV1Escrow.Asset({
            token: address(mockERC721),
            tokenId: 2,
            amount: 1,
            assetType: TFTV1Escrow.AssetType.ERC721,
            recipient: addr1,
            isDeposited: false
        });

        return escrow.createTrade(participants, assets);
    }
}