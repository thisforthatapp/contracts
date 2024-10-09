// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/TFTV1Escrow.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockERC721.sol";
import "./mocks/MockERC1155.sol";

contract TFTV1EscrowTest is Test {
    TFTV1Escrow public escrow;
    MockERC20 public erc20Token;
    MockERC721 public erc721Token;
    MockERC1155 public erc1155Token;

    address public owner;
    address public addr1;
    address public addr2;
    address public addr3;

    function setUp() public {
        owner = address(this);
        addr1 = address(0x1);
        addr2 = address(0x2);
        addr3 = address(0x3);

        vm.startPrank(owner);
        escrow = new TFTV1Escrow();
        erc20Token = new MockERC20("MockToken", "MTK");
        erc721Token = new MockERC721("MockNFT", "MNFT");
        erc1155Token = new MockERC1155();
        vm.stopPrank();

        // Mint tokens for testing
        erc20Token.mint(addr1, 1000 ether);
        erc721Token.mint(addr1, 1);
        erc1155Token.mint(addr1, 1, 100, "");

        vm.deal(addr1, 100 ether);
        vm.deal(addr2, 100 ether);
    }

    function testCreateTrade() public {
        address[] memory participants = new address[](2);
        participants[0] = addr1;
        participants[1] = addr2;

        vm.prank(addr1);
        uint256 tradeId = escrow.createTrade(participants, 0);

        assertEq(tradeId, 0, "First trade should have ID 0");
    }

    function testCreateTradeInvalidParticipantCount() public {
        address[] memory participants = new address[](1);
        participants[0] = addr1;

        vm.expectRevert(
            abi.encodeWithSelector(TFTV1Escrow.InvalidParticipantCount.selector)
        );
        escrow.createTrade(participants, 0);

        participants = new address[](11);
        for (uint i = 0; i < 11; i++) {
            participants[i] = address(uint160(i + 1));
        }

        vm.expectRevert(
            abi.encodeWithSelector(TFTV1Escrow.InvalidParticipantCount.selector)
        );
        escrow.createTrade(participants, 0);
    }

    function testCreateTradeInvalidDuration() public {
        address[] memory participants = new address[](2);
        participants[0] = addr1;
        participants[1] = addr2;

        vm.expectRevert(
            abi.encodeWithSelector(TFTV1Escrow.InvalidDuration.selector)
        );
        escrow.createTrade(participants, 12 hours);

        vm.expectRevert(
            abi.encodeWithSelector(TFTV1Escrow.InvalidDuration.selector)
        );
        escrow.createTrade(participants, 31 days);
    }

    function testDepositERC20() public {
        address[] memory participants = new address[](2);
        participants[0] = addr1;
        participants[1] = addr2;

        vm.startPrank(addr1);
        uint256 tradeId = escrow.createTrade(participants, 0);
        erc20Token.approve(address(escrow), 100 ether);
        escrow.depositAsset(
            tradeId,
            address(erc20Token),
            0,
            100 ether,
            TFTV1Escrow.AssetType.ERC20,
            addr2
        );
        vm.stopPrank();

        assertEq(
            erc20Token.balanceOf(address(escrow)),
            100 ether,
            "Escrow should have received 100 tokens"
        );
    }

    function testDepositERC721() public {
        address[] memory participants = new address[](2);
        participants[0] = addr1;
        participants[1] = addr2;

        vm.startPrank(addr1);
        uint256 tradeId = escrow.createTrade(participants, 0);
        erc721Token.approve(address(escrow), 1);
        escrow.depositAsset(
            tradeId,
            address(erc721Token),
            1,
            1,
            TFTV1Escrow.AssetType.ERC721,
            addr2
        );
        vm.stopPrank();

        assertEq(
            erc721Token.ownerOf(1),
            address(escrow),
            "Escrow should own the NFT"
        );
    }

    function testDepositERC1155() public {
        address[] memory participants = new address[](2);
        participants[0] = addr1;
        participants[1] = addr2;

        vm.startPrank(addr1);
        uint256 tradeId = escrow.createTrade(participants, 0);
        erc1155Token.setApprovalForAll(address(escrow), true);
        escrow.depositAsset(
            tradeId,
            address(erc1155Token),
            1,
            50,
            TFTV1Escrow.AssetType.ERC1155,
            addr2
        );
        vm.stopPrank();

        assertEq(
            erc1155Token.balanceOf(address(escrow), 1),
            50,
            "Escrow should have received 50 tokens"
        );
    }

    function testConfirmTrade() public {
        address[] memory participants = new address[](2);
        participants[0] = addr1;
        participants[1] = addr2;

        vm.startPrank(addr1);
        uint256 tradeId = escrow.createTrade(participants, 0);
        erc20Token.approve(address(escrow), 100 ether);
        escrow.depositAsset(
            tradeId,
            address(erc20Token),
            0,
            100 ether,
            TFTV1Escrow.AssetType.ERC20,
            addr2
        );
        escrow.confirmTrade(tradeId);
        vm.stopPrank();

        vm.startPrank(addr2);
        erc721Token.mint(addr2, 2);
        erc721Token.approve(address(escrow), 2);
        escrow.depositAsset(
            tradeId,
            address(erc721Token),
            2,
            1,
            TFTV1Escrow.AssetType.ERC721,
            addr1
        );
        vm.stopPrank();

        // Check balances before final confirmation
        uint256 addr2ERC20BalanceBefore = erc20Token.balanceOf(addr2);
        address nftOwnerBefore = erc721Token.ownerOf(2);

        // Final confirmation and trade execution
        vm.prank(addr2);
        escrow.confirmTrade(tradeId);

        // Check final balances
        assertEq(
            erc20Token.balanceOf(addr2),
            addr2ERC20BalanceBefore + 100 ether,
            "addr2 should have received 100 ERC20 tokens"
        );
        assertEq(erc721Token.ownerOf(2), addr1, "addr1 should own the NFT");
    }

    function testCancelTrade() public {
        address[] memory participants = new address[](2);
        participants[0] = addr1;
        participants[1] = addr2;

        uint256 initialBalance = erc20Token.balanceOf(addr1);

        vm.startPrank(addr1);
        uint256 tradeId = escrow.createTrade(participants, 0);
        erc20Token.approve(address(escrow), 100 ether);
        escrow.depositAsset(
            tradeId,
            address(erc20Token),
            0,
            100 ether,
            TFTV1Escrow.AssetType.ERC20,
            addr2
        );
        escrow.cancelTrade(tradeId);
        vm.stopPrank();

        assertEq(
            erc20Token.balanceOf(addr1),
            initialBalance,
            "addr1 should have received back their tokens"
        );
    }

    function testReclaimAssets() public {
        address[] memory participants = new address[](2);
        participants[0] = addr1;
        participants[1] = addr2;

        uint256 initialBalance = erc20Token.balanceOf(addr1);

        vm.startPrank(addr1);
        uint256 tradeId = escrow.createTrade(participants, 1 days);
        erc20Token.approve(address(escrow), 100 ether);
        escrow.depositAsset(
            tradeId,
            address(erc20Token),
            0,
            100 ether,
            TFTV1Escrow.AssetType.ERC20,
            addr2
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        vm.prank(addr1);
        escrow.reclaimAssets(tradeId);

        assertEq(
            erc20Token.balanceOf(addr1),
            initialBalance,
            "addr1 should have reclaimed their tokens"
        );
    }
}