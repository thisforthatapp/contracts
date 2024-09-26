// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/TFTV1Escrow.sol";
import "./MockERC20.sol";

contract TFTV1EscrowTest is Test {
    TFTV1Escrow public escrow;
    MockERC20 public mockToken;
    address public owner;
    address public feeRecipient;
    address public addr1;
    address public addr2;
    address public addr3;

    function setUp() public {
        owner = address(this);
        feeRecipient = address(0xfee);
        addr1 = address(0x1);
        addr2 = address(0x2);
        addr3 = address(0x3);

        escrow = new TFTV1Escrow(feeRecipient);
        mockToken = new MockERC20("MockToken", "MTK");

        vm.label(address(escrow), "Escrow");
        vm.label(address(mockToken), "MockToken");
        vm.label(owner, "Owner");
        vm.label(feeRecipient, "FeeRecipient");
        vm.label(addr1, "Addr1");
        vm.label(addr2, "Addr2");
        vm.label(addr3, "Addr3");
    }

    function testDeployment() public {
        assertEq(escrow.feeRecipient(), feeRecipient);
        assertEq(escrow.owner(), owner);
    }

    function testCreateTrade() public {
        address[] memory participants = new address[](2);
        participants[0] = addr1;
        participants[1] = addr2;

        uint256 tradeId = escrow.createTrade(participants);
        assertEq(tradeId, 0);

        vm.expectRevert(TFTV1Escrow.InvalidParticipantCount.selector);
        address[] memory invalidParticipants = new address[](1);
        invalidParticipants[0] = addr1;
        escrow.createTrade(invalidParticipants);
    }

    function testDepositAsset() public {
        address[] memory participants = new address[](2);
        participants[0] = addr1;
        participants[1] = addr2;
        uint256 tradeId = escrow.createTrade(participants);

        uint256 flatFee = escrow.flatFee();
        
        vm.deal(addr1, flatFee);
        vm.prank(addr1);
        escrow.depositAsset{value: flatFee}(tradeId, address(0), 0, 0, false);

        vm.expectRevert(TFTV1Escrow.IncorrectFeeAmount.selector);
        vm.prank(addr2);
        escrow.depositAsset(tradeId, address(0), 0, 0, false);
    }

    function testConfirmTrade() public {
        address[] memory participants = new address[](2);
        participants[0] = addr1;
        participants[1] = addr2;
        uint256 tradeId = escrow.createTrade(participants);

        uint256 flatFee = escrow.flatFee();
        
        vm.deal(addr1, flatFee);
        vm.prank(addr1);
        escrow.depositAsset{value: flatFee}(tradeId, address(0), 0, 0, false);

        vm.prank(addr1);
        escrow.confirmTrade(tradeId);

        vm.expectRevert(TFTV1Escrow.FeeNotPaid.selector);
        vm.prank(addr2);
        escrow.confirmTrade(tradeId);
    }

    function testExecuteTrade() public {
        address[] memory participants = new address[](2);
        participants[0] = addr1;
        participants[1] = addr2;
        uint256 tradeId = escrow.createTrade(participants);

        uint256 flatFee = escrow.flatFee();
        uint256 tokenAmount = 100 * 10**18;

        mockToken.mint(addr1, tokenAmount);

        vm.startPrank(addr1);
        mockToken.approve(address(escrow), tokenAmount);
        escrow.depositAsset{value: flatFee}(tradeId, address(mockToken), 0, tokenAmount, false);
        escrow.confirmTrade(tradeId);
        vm.stopPrank();

        vm.deal(addr2, flatFee);
        vm.startPrank(addr2);
        escrow.depositAsset{value: flatFee}(tradeId, address(0), 0, 0, false);
        escrow.confirmTrade(tradeId);
        vm.stopPrank();

        assertEq(mockToken.balanceOf(addr2), tokenAmount);
        assertEq(address(feeRecipient).balance, 2 * flatFee);
    }

    function testAdminFunctions() public {
        uint256 newFee = 0.01 ether;
        escrow.setFlatFee(newFee);
        assertEq(escrow.flatFee(), newFee);

        address newFeeRecipient = address(0x1234);
        escrow.setFeeRecipient(newFeeRecipient);
        assertEq(escrow.feeRecipient(), newFeeRecipient);

        vm.prank(addr1);
        vm.expectRevert("Ownable: caller is not the owner");
        escrow.setFlatFee(0.02 ether);
    }
}