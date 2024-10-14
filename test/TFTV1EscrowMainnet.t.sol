// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface ICryptoPunks {
    function transferPunk(address to, uint256 punkIndex) external;
}

contract NFTTestSetup is Test {
    address constant CRYPTOPUNKS_ADDRESS = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;
    address constant TEST_OWNER = address(0x1234);  // Replace with your desired test owner address

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork("mainnet");

        // Setup ERC721 NFT
        address erc721Address = 0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85;  // ENS
        uint256 erc721TokenId = 123;  // Replace with actual token ID
        address currentOwner = IERC721(erc721Address).ownerOf(erc721TokenId);
        vm.prank(currentOwner);
        IERC721(erc721Address).transferFrom(currentOwner, TEST_OWNER, erc721TokenId);

        // Setup ERC1155 NFT
        address erc1155Address = 0xa7d8d9ef8D8Ce8992Df33D8b8CF4Aebabd5bD270;  // Art Blocks
        uint256 erc1155TokenId = 456;  // Replace with actual token ID
        uint256 amount = 1;  // Or more if needed
        address erc1155Owner = 0x123456...;  // Replace with actual owner address
        vm.prank(erc1155Owner);
        IERC1155(erc1155Address).safeTransferFrom(erc1155Owner, TEST_OWNER, erc1155TokenId, amount, "");

        // Setup CryptoPunk
        uint256 punkIndex = 1000;  // Replace with actual punk index
        address punkOwner = 0x789abc...;  // Replace with actual punk owner
        vm.prank(punkOwner);
        ICryptoPunks(CRYPTOPUNKS_ADDRESS).transferPunk(TEST_OWNER, punkIndex);
    }

    function testNFTOwnership() public {
        // Add your tests here
    }
}