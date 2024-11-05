// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/TFTEscrow.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

// Mock contracts at the top
contract MockERC721 is ERC721 {
    constructor() ERC721("Mock NFT", "MNFT") {}
    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}

contract MockERC1155 is ERC1155 {
    constructor() ERC1155("") {}
    function mint(address to, uint256 id, uint256 amount) public {
        _mint(to, id, amount, "");
    }
}

contract MockCryptoPunks {
    mapping(uint256 => address) public punkIndexToAddress;
    
    struct Offer {
        bool isForSale;
        uint256 punkIndex;
        address seller;
        uint256 minValue;
        address onlySellTo;
    }
    
    mapping(uint256 => Offer) public punksOfferedForSale;
    
    event PunkTransfer(address indexed from, address indexed to, uint256 punkIndex);
    event PunkOffered(uint256 indexed punkIndex, uint256 minValue, address indexed toAddress);

    function setInitialOwner(address to, uint256 punkIndex) public {
        punkIndexToAddress[punkIndex] = to;
    }

    function transferPunk(address to, uint256 punkIndex) public {        
        address currentOwner = punkIndexToAddress[punkIndex];
        require(currentOwner == msg.sender, "Not owner");
        punkIndexToAddress[punkIndex] = to;
        emit PunkTransfer(msg.sender, to, punkIndex);        
    }
    
    function offerPunkForSaleToAddress(uint256 punkIndex, uint256 minSalePriceInWei, address toAddress) public {
        require(punkIndexToAddress[punkIndex] == msg.sender, "Not owner");
        punksOfferedForSale[punkIndex] = Offer(true, punkIndex, msg.sender, minSalePriceInWei, toAddress);
        emit PunkOffered(punkIndex, minSalePriceInWei, toAddress);
    }
    
    function buyPunk(uint256 punkIndex) public payable {
        Offer memory offer = punksOfferedForSale[punkIndex];
        require(offer.isForSale, "Punk not for sale");
        require(offer.onlySellTo == msg.sender, "Not offered to you");
        require(msg.value >= offer.minValue, "Insufficient payment");
        
        address seller = offer.seller;
        punkIndexToAddress[punkIndex] = msg.sender;
        punksOfferedForSale[punkIndex] = Offer(false, punkIndex, address(0), 0, address(0));
        
        emit PunkTransfer(seller, msg.sender, punkIndex);
        
        if (msg.value > 0) {
            payable(msg.sender).transfer(msg.value);
        }
    }
}

contract TFTEscrowTest is Test {
    // State variables
    TFTEscrow escrow;
    MockERC721 erc721Token;
    MockERC1155 erc1155Token;
    MockCryptoPunks cryptoPunks;

    address constant CRYPTOPUNKS_ADDRESS = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    // Events for tests
    event TradeCreated(uint256 indexed tradeId, bytes32 indexed tradeHash);
    event AssetDeposited(uint256 indexed tradeId, uint256 indexed assetIndex, address depositor);
    event TradeCompleted(uint256 indexed tradeId);
    event TradeCancelled(uint256 indexed tradeId, address indexed canceller);

    // Setup function
    function setUp() public {
        cryptoPunks = new MockCryptoPunks();
        vm.etch(CRYPTOPUNKS_ADDRESS, address(cryptoPunks).code);
        
        // Set up punk ownership
        MockCryptoPunks(CRYPTOPUNKS_ADDRESS).setInitialOwner(alice, 5577);
        
        escrow = new TFTEscrow();
        erc721Token = new MockERC721();
        erc1155Token = new MockERC1155();

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        erc721Token.mint(alice, 1);
        erc721Token.mint(alice, 2);
        erc721Token.mint(bob, 3);
        erc721Token.mint(bob, 4);
        
        erc1155Token.mint(alice, 1, 10);
        erc1155Token.mint(bob, 2, 20);
    }

    // Helper functions
    function createBasicTrade(
        address[] memory participants,
        TFTEscrow.Asset memory asset1,
        TFTEscrow.Asset memory asset2
    ) internal returns (uint256) {
        TFTEscrow.Asset[] memory assets = new TFTEscrow.Asset[](2);
        assets[0] = asset1;
        assets[1] = asset2;
        return escrow.createTrade(participants, assets);
    }

    function createParticipants() internal view returns (address[] memory) {
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;
        return participants;
    }

    function setupCryptoPunks() internal returns (MockCryptoPunks) {
        cryptoPunks = new MockCryptoPunks();
        bytes memory code = address(cryptoPunks).code;
        vm.etch(0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB, code);
        return MockCryptoPunks(0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB);
    }

    // ERC721 Tests
    function test_itShouldSwapERC721Tokens() public {
        address[] memory participants = createParticipants();

        TFTEscrow.Asset memory aliceAsset = TFTEscrow.Asset({
            token: address(erc721Token),
            recipient: bob,
            depositor: address(0),
            tokenId: 1,
            amount: 1,
            assetType: TFTEscrow.AssetType.ERC721,
            isDeposited: false
        });

        TFTEscrow.Asset memory bobAsset = TFTEscrow.Asset({
            token: address(erc721Token),
            recipient: alice,
            depositor: address(0),
            tokenId: 3,
            amount: 1,
            assetType: TFTEscrow.AssetType.ERC721,
            isDeposited: false
        });

        uint256 tradeId = createBasicTrade(participants, aliceAsset, bobAsset);

        vm.startPrank(alice);
        erc721Token.setApprovalForAll(address(escrow), true);
        escrow.depositAsset(tradeId, address(erc721Token), 1, 1, TFTEscrow.AssetType.ERC721);
        vm.stopPrank();

        vm.startPrank(bob);
        erc721Token.setApprovalForAll(address(escrow), true);
        escrow.depositAsset(tradeId, address(erc721Token), 3, 1, TFTEscrow.AssetType.ERC721);
        vm.stopPrank();

        assertEq(erc721Token.ownerOf(1), bob);
        assertEq(erc721Token.ownerOf(3), alice);
    }

    // ERC1155 Tests
    function test_itShouldSwapERC1155Tokens() public {
        address[] memory participants = createParticipants();

        TFTEscrow.Asset memory aliceAsset = TFTEscrow.Asset({
            token: address(erc1155Token),
            recipient: bob,
            depositor: address(0),
            tokenId: 1,
            amount: 5,
            assetType: TFTEscrow.AssetType.ERC1155,
            isDeposited: false
        });

        TFTEscrow.Asset memory bobAsset = TFTEscrow.Asset({
            token: address(erc1155Token),
            recipient: alice,
            depositor: address(0),
            tokenId: 2,
            amount: 10,
            assetType: TFTEscrow.AssetType.ERC1155,
            isDeposited: false
        });

        uint256 tradeId = createBasicTrade(participants, aliceAsset, bobAsset);

        uint256 aliceInitialBalance1 = erc1155Token.balanceOf(alice, 1);
        uint256 bobInitialBalance2 = erc1155Token.balanceOf(bob, 2);

        vm.startPrank(alice);
        erc1155Token.setApprovalForAll(address(escrow), true);
        escrow.depositAsset(tradeId, address(erc1155Token), 1, 5, TFTEscrow.AssetType.ERC1155);
        vm.stopPrank();

        vm.startPrank(bob);
        erc1155Token.setApprovalForAll(address(escrow), true);
        escrow.depositAsset(tradeId, address(erc1155Token), 2, 10, TFTEscrow.AssetType.ERC1155);
        vm.stopPrank();

        assertEq(erc1155Token.balanceOf(alice, 1), aliceInitialBalance1 - 5);
        assertEq(erc1155Token.balanceOf(bob, 2), bobInitialBalance2 - 10);
        assertEq(erc1155Token.balanceOf(bob, 1), 5);
        assertEq(erc1155Token.balanceOf(alice, 2), 10);
    }

    // CryptoPunks Tests
    function test_itShouldSwapCryptoPunks() public {
        MockCryptoPunks punks = setupCryptoPunks();
        punks.setInitialOwner(alice, 1);
        punks.setInitialOwner(bob, 2);

        address[] memory participants = createParticipants();

        TFTEscrow.Asset memory aliceAsset = TFTEscrow.Asset({
            token: 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB,
            recipient: bob,
            depositor: address(0),
            tokenId: 1,
            amount: 1,
            assetType: TFTEscrow.AssetType.CryptoPunk,
            isDeposited: false
        });

        TFTEscrow.Asset memory bobAsset = TFTEscrow.Asset({
            token: 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB,
            recipient: alice,
            depositor: address(0),
            tokenId: 2,
            amount: 1,
            assetType: TFTEscrow.AssetType.CryptoPunk,
            isDeposited: false
        });

        uint256 tradeId = createBasicTrade(participants, aliceAsset, bobAsset);

        vm.startPrank(alice);
        punks.offerPunkForSaleToAddress(1, 0, address(escrow));
        escrow.depositAsset(tradeId, 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB, 1, 1, TFTEscrow.AssetType.CryptoPunk);
        vm.stopPrank();

        vm.startPrank(bob);
        punks.offerPunkForSaleToAddress(2, 0, address(escrow));
        escrow.depositAsset(tradeId, 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB, 2, 1, TFTEscrow.AssetType.CryptoPunk);
        vm.stopPrank();

        assertEq(punks.punkIndexToAddress(1), bob, "Bob should now own punk 1");
        assertEq(punks.punkIndexToAddress(2), alice, "Alice should now own punk 2");
    }

    // Cancellation Tests
    // Reason this fails right now is because in prod, the msg.sender in the cryptopunks contract is the escrow contract, where here it's not.
    /*
    function test_itShouldAllowTradeCancellation() public {
        MockCryptoPunks punks = setupCryptoPunks();
        punks.setInitialOwner(alice, 1);

        address[] memory participants = createParticipants();
        
        TFTEscrow.Asset[] memory assets = new TFTEscrow.Asset[](1);
        assets[0] = _createCryptoPunkAsset(bob, 1);  // Using helper function

        uint256 tradeId = escrow.createTrade(participants, assets);

        (bool isActiveBefore,,, ) = escrow.getTradeInfo(tradeId);
        assertTrue(isActiveBefore, "Trade should be active after creation");

        vm.startPrank(alice);
        punks.offerPunkForSaleToAddress(1, 0, address(escrow));
        escrow.depositAsset(
            tradeId,
            0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB,
            1,
            1,
            TFTEscrow.AssetType.CryptoPunk
        );
        vm.stopPrank();

        assertEq(punks.punkIndexToAddress(1), address(escrow), "Escrow should own punk 1 before cancellation");

        vm.prank(bob);
        escrow.cancelTrade(tradeId);

        assertEq(punks.punkIndexToAddress(1), alice, "Alice should own punk 1 after cancellation");
        
        (bool isActive,,, ) = escrow.getTradeInfo(tradeId);
        assertFalse(isActive, "Trade should not be active after cancellation");
    }
    */

    // Error Tests
    function test_itShouldPreventInvalidParticipantCount() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        TFTEscrow.Asset[] memory assets = new TFTEscrow.Asset[](1);
        assets[0] = TFTEscrow.Asset({
            token: address(erc721Token),
            recipient: bob,
            depositor: address(0),
            tokenId: 1,
            amount: 1,
            assetType: TFTEscrow.AssetType.ERC721,
            isDeposited: false
        });

        vm.expectRevert(TFTEscrow.InvalidParticipantCount.selector);
        escrow.createTrade(participants, assets);
    }

    function test_itShouldPreventExceedingMaxAssets() public {
        address[] memory participants = createParticipants();

        // Create more assets than allowed per participant
        TFTEscrow.Asset[] memory assets = new TFTEscrow.Asset[](21); // MAX_ASSETS_PER_PARTICIPANT + 1
        
        for(uint i = 0; i < assets.length; i++) {
            assets[i] = TFTEscrow.Asset({
                token: address(erc721Token),
                recipient: bob,
                depositor: address(0),
                tokenId: uint96(i),
                amount: 1,
                assetType: TFTEscrow.AssetType.ERC721,
                isDeposited: false
            });
        }

        vm.expectRevert(TFTEscrow.MaxAssetsExceeded.selector);
        escrow.createTrade(participants, assets);
    }

    function test_itShouldPreventInvalidAssetDeposit() public {
        address[] memory participants = createParticipants();

        TFTEscrow.Asset memory validAsset = TFTEscrow.Asset({
            token: address(erc721Token),
            recipient: bob,
            depositor: address(0),
            tokenId: 1,
            amount: 1,
            assetType: TFTEscrow.AssetType.ERC721,
            isDeposited: false
        });

        uint256 tradeId = escrow.createTrade(participants, _wrapIntoArray(validAsset));

        // Try to deposit an asset that wasn't part of the original trade
        vm.startPrank(alice);
        erc721Token.setApprovalForAll(address(escrow), true);
        vm.expectRevert(TFTEscrow.InvalidAsset.selector);
        escrow.depositAsset(
            tradeId,
            address(erc721Token),
            2, // Different tokenId than what was in the trade
            1,
            TFTEscrow.AssetType.ERC721
        );
        vm.stopPrank();
    }

    function test_itShouldPreventDepositToInactiveTrade() public {
        address[] memory participants = createParticipants();

        TFTEscrow.Asset memory validAsset = TFTEscrow.Asset({
            token: address(erc721Token),
            recipient: bob,
            depositor: address(0),
            tokenId: 1,
            amount: 1,
            assetType: TFTEscrow.AssetType.ERC721,
            isDeposited: false
        });

        uint256 tradeId = escrow.createTrade(participants, _wrapIntoArray(validAsset));

        // Cancel the trade
        vm.prank(bob);
        escrow.cancelTrade(tradeId);

        // Try to deposit to cancelled trade
        vm.startPrank(alice);
        erc721Token.setApprovalForAll(address(escrow), true);
        vm.expectRevert(TFTEscrow.TradeNotActive.selector);
        escrow.depositAsset(
            tradeId,
            address(erc721Token),
            1,
            1,
            TFTEscrow.AssetType.ERC721
        );
        vm.stopPrank();
    }

    function test_itShouldPreventBatchDepositWithMismatchedArrays() public {
        address[] memory participants = createParticipants();

        TFTEscrow.Asset memory asset1 = TFTEscrow.Asset({
            token: address(erc721Token),
            recipient: bob,
            depositor: address(0),
            tokenId: 1,
            amount: 1,
            assetType: TFTEscrow.AssetType.ERC721,
            isDeposited: false
        });

        TFTEscrow.Asset memory asset2 = TFTEscrow.Asset({
            token: address(erc1155Token),
            recipient: bob,
            depositor: address(0),
            tokenId: 1,
            amount: 5,
            assetType: TFTEscrow.AssetType.ERC1155,
            isDeposited: false
        });

        uint256 tradeId = createBasicTrade(participants, asset1, asset2);

        // Create mismatched arrays
        address[] memory tokens = new address[](2);
        uint256[] memory tokenIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](1); // Mismatched length
        TFTEscrow.AssetType[] memory assetTypes = new TFTEscrow.AssetType[](2);

        vm.startPrank(alice);
        vm.expectRevert(TFTEscrow.ArrayLengthMismatch.selector);
        escrow.batchDepositAssets(
            tradeId,
            tokens,
            tokenIds,
            amounts,
            assetTypes
        );
        vm.stopPrank();
    }

    function test_itShouldPreventExcessiveBatchDeposits() public {
        address[] memory participants = createParticipants();

        TFTEscrow.Asset memory validAsset = TFTEscrow.Asset({
            token: address(erc721Token),
            recipient: bob,
            depositor: address(0),
            tokenId: 1,
            amount: 1,
            assetType: TFTEscrow.AssetType.ERC721,
            isDeposited: false
        });

        uint256 tradeId = escrow.createTrade(participants, _wrapIntoArray(validAsset));

        // Create arrays larger than MAX_BATCH_DEPOSITS
        address[] memory tokens = new address[](21);
        uint256[] memory tokenIds = new uint256[](21);
        uint256[] memory amounts = new uint256[](21);
        TFTEscrow.AssetType[] memory assetTypes = new TFTEscrow.AssetType[](21);

        vm.startPrank(alice);
        vm.expectRevert(TFTEscrow.BatchSizeExceeded.selector);
        escrow.batchDepositAssets(
            tradeId,
            tokens,
            tokenIds,
            amounts,
            assetTypes
        );
        vm.stopPrank();
    }

    function test_itShouldPreventUnauthorizedCancellation() public {
        address[] memory participants = createParticipants();

        TFTEscrow.Asset memory validAsset = TFTEscrow.Asset({
            token: address(erc721Token),
            recipient: bob,
            depositor: address(0),
            tokenId: 1,
            amount: 1,
            assetType: TFTEscrow.AssetType.ERC721,
            isDeposited: false
        });

        uint256 tradeId = escrow.createTrade(participants, _wrapIntoArray(validAsset));

        vm.prank(charlie);
        vm.expectRevert(TFTEscrow.NotParticipant.selector);
        escrow.cancelTrade(tradeId);
    }

    // Helper function to wrap a single asset into an array
    function _wrapIntoArray(TFTEscrow.Asset memory asset) internal pure returns (TFTEscrow.Asset[] memory) {
        TFTEscrow.Asset[] memory assets = new TFTEscrow.Asset[](1);
        assets[0] = asset;
        return assets;
    }

    // Helper to create standard ERC721 asset
    function _createERC721Asset(
        address token,
        address recipient,
        uint256 tokenId
    ) internal pure returns (TFTEscrow.Asset memory) {
        return TFTEscrow.Asset({
            token: token,
            recipient: recipient,
            depositor: address(0),
            tokenId: tokenId,
            amount: 1,
            assetType: TFTEscrow.AssetType.ERC721,
            isDeposited: false
        });
    }

    // Helper to create standard ERC1155 asset
    function _createERC1155Asset(
        address token,
        address recipient,
        uint256 tokenId,
        uint96 amount
    ) internal pure returns (TFTEscrow.Asset memory) {
        return TFTEscrow.Asset({
            token: token,
            recipient: recipient,
            depositor: address(0),
            tokenId: tokenId,
            amount: amount,
            assetType: TFTEscrow.AssetType.ERC1155,
            isDeposited: false
        });
    }

    // Helper to create CryptoPunk asset
    function _createCryptoPunkAsset(
        address recipient,
        uint256 tokenId
    ) internal pure returns (TFTEscrow.Asset memory) {
        return TFTEscrow.Asset({
            token: 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB,
            recipient: recipient,
            depositor: address(0),
            tokenId: tokenId,
            amount: 1,
            assetType: TFTEscrow.AssetType.CryptoPunk,
            isDeposited: false
        });
    }
}