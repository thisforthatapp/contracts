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
    address public feeRecipient;
    address public alice;
    address public bob;

    uint256 public constant FLAT_FEE = 0.005 ether;

    function setUp() public {
        owner = address(this);
        feeRecipient = address(0x123);
        alice = address(0xA11CE);
        bob = address(0xB0B);

        escrow = new TFTV1Escrow(feeRecipient);
        erc20Token = new MockERC20("Mock ERC20", "MERC20");
        erc721Token = new MockERC721("Mock ERC721", "MERC721");
        erc1155Token = new MockERC1155("https://token-uri.com/");

        // Mint tokens
        erc20Token.mint(alice, 1000 ether);
        erc721Token.mint(alice, 1);
        erc1155Token.mint(alice, 1, 100, "");

        // Approve escrow
        vm.startPrank(alice);
        erc20Token.approve(address(escrow), type(uint256).max);
        erc721Token.setApprovalForAll(address(escrow), true);
        erc1155Token.setApprovalForAll(address(escrow), true);
        vm.stopPrank();
    }

    function testCreateTrade() public {
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        vm.prank(alice);
        uint256 tradeId = escrow.createTrade(participants, 1 days);

        assertEq(tradeId, 0, "First trade should have ID 0");
    }

    function testDepositERC20() public {
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        vm.startPrank(alice);
        uint256 tradeId = escrow.createTrade(participants, 1 days);
        
        uint256 amount = 100 ether;
        escrow.depositAsset{value: FLAT_FEE}(tradeId, address(erc20Token), 0, amount, TFTV1Escrow.AssetType.ERC20, bob);
        vm.stopPrank();

        assertEq(erc20Token.balanceOf(address(escrow)), amount, "Escrow should have received ERC20 tokens");
    }

    function testDepositERC721() public {
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        vm.startPrank(alice);
        uint256 tradeId = escrow.createTrade(participants, 1 days);
        
        escrow.depositAsset{value: FLAT_FEE}(tradeId, address(erc721Token), 1, 1, TFTV1Escrow.AssetType.ERC721, bob);
        vm.stopPrank();

        assertEq(erc721Token.ownerOf(1), address(escrow), "Escrow should own the ERC721 token");
    }

    function testDepositERC1155() public {
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        vm.startPrank(alice);
        uint256 tradeId = escrow.createTrade(participants, 1 days);
        
        uint256 amount = 50;
        escrow.depositAsset{value: FLAT_FEE}(tradeId, address(erc1155Token), 1, amount, TFTV1Escrow.AssetType.ERC1155, bob);
        vm.stopPrank();

        assertEq(erc1155Token.balanceOf(address(escrow), 1), amount, "Escrow should have received ERC1155 tokens");
    }

    function testConfirmTrade() public {
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        vm.prank(alice);
        uint256 tradeId = escrow.createTrade(participants, 1 days);

        vm.startPrank(alice);
        escrow.depositAsset{value: FLAT_FEE}(tradeId, address(erc20Token), 0, 100 ether, TFTV1Escrow.AssetType.ERC20, bob);
        escrow.confirmTrade(tradeId);
        vm.stopPrank();

        vm.startPrank(bob);
        escrow.depositAsset{value: FLAT_FEE}(tradeId, address(erc721Token), 1, 1, TFTV1Escrow.AssetType.ERC721, alice);
        escrow.confirmTrade(tradeId);
        vm.stopPrank();

        // Check that the trade was executed
        assertEq(erc20Token.balanceOf(bob), 100 ether, "Bob should have received ERC20 tokens");
        assertEq(erc721Token.ownerOf(1), alice, "Alice should have received the ERC721 token");
    }

    function testCancelTrade() public {
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        vm.prank(alice);
        uint256 tradeId = escrow.createTrade(participants, 1 days);

        vm.startPrank(alice);
        escrow.depositAsset{value: FLAT_FEE}(tradeId, address(erc20Token), 0, 100 ether, TFTV1Escrow.AssetType.ERC20, bob);
        escrow.cancelTrade(tradeId);
        vm.stopPrank();

        assertEq(erc20Token.balanceOf(alice), 1000 ether, "Alice should have received back her ERC20 tokens");
    }

    function testReclaimAssets() public {
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        vm.prank(alice);
        uint256 tradeId = escrow.createTrade(participants, 1 days);

        vm.startPrank(alice);
        escrow.depositAsset{value: FLAT_FEE}(tradeId, address(erc20Token), 0, 100 ether, TFTV1Escrow.AssetType.ERC20, bob);
        vm.stopPrank();

        // Fast forward past the deadline
        vm.warp(block.timestamp + 2 days);

        vm.prank(alice);
        escrow.reclaimAssets(tradeId);

        assertEq(erc20Token.balanceOf(alice), 1000 ether, "Alice should have reclaimed her ERC20 tokens");
    }

    function testWithdrawFees() public {
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        vm.prank(alice);
        uint256 tradeId = escrow.createTrade(participants, 1 days);

        vm.prank(alice);
        escrow.depositAsset{value: FLAT_FEE}(tradeId, address(erc20Token), 0, 100 ether, TFTV1Escrow.AssetType.ERC20, bob);

        uint256 initialBalance = feeRecipient.balance;
        
        vm.prank(feeRecipient);
        escrow.withdrawFees(FLAT_FEE);

        assertEq(feeRecipient.balance, initialBalance + FLAT_FEE, "Fee recipient should have received the fee");
    }

    function testFailDepositAfterDeadline() public {
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        vm.prank(alice);
        uint256 tradeId = escrow.createTrade(participants, 1 days);

        // Fast forward past the deadline
        vm.warp(block.timestamp + 2 days);

        vm.prank(alice);
        escrow.depositAsset{value: FLAT_FEE}(tradeId, address(erc20Token), 0, 100 ether, TFTV1Escrow.AssetType.ERC20, bob);
    }

    function testFailDepositExceedingMaxAssets() public {
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        vm.prank(alice);
        uint256 tradeId = escrow.createTrade(participants, 1 days);

        vm.startPrank(alice);
        for (uint i = 0; i < 11; i++) {
            escrow.depositAsset{value: FLAT_FEE}(tradeId, address(erc20Token), 0, 1 ether, TFTV1Escrow.AssetType.ERC20, bob);
        }
        vm.stopPrank();
    }
}