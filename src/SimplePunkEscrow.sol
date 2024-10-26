// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ICryptoPunks {
    function punkIndexToAddress(uint256 punkIndex) external view returns (address);
    function transferPunk(address to, uint256 punkIndex) external;
    function punksOfferedForSale(uint256 punkIndex) external view returns (
        bool isForSale,
        uint256 index,
        address seller,
        uint256 minValue,
        address onlySellTo
    );
    function buyPunk(uint256 punkIndex) external payable;
}
contract SimplePunkEscrow is ReentrancyGuard, Ownable {
    address public constant CRYPTOPUNKS_ADDRESS = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;
    
    struct Trade {
        uint256 punkId;
        address sender;
        address recipient;
        bool isActive;
        bool isDeposited;
    }
    
    mapping(uint256 => Trade) public trades;
    
    event TradeCreated(uint256 indexed tradeId, uint256 punkId, address sender, address recipient);
    event PunkDeposited(uint256 indexed tradeId, uint256 punkId);
    event TradeCompleted(uint256 indexed tradeId);
    event TradeCancelled(uint256 indexed tradeId);
    
    constructor() Ownable(msg.sender) {}
    
    function createTrade(uint256 punkId, address recipient) external returns (uint256) {
        uint256 tradeId = uint256(keccak256(abi.encode(block.timestamp, msg.sender, punkId)));
        
        // Verify sender owns the punk
        require(ICryptoPunks(CRYPTOPUNKS_ADDRESS).punkIndexToAddress(punkId) == msg.sender, "Not punk owner");
        
        trades[tradeId] = Trade({
            punkId: punkId,
            sender: msg.sender,
            recipient: recipient,
            isActive: true,
            isDeposited: false
        });
        
        emit TradeCreated(tradeId, punkId, msg.sender, recipient);
        return tradeId;
    }
    
    function depositPunk(uint256 tradeId) external nonReentrant {
        Trade storage trade = trades[tradeId];
        require(trade.isActive, "Trade not active");
        require(!trade.isDeposited, "Already deposited");
        require(trade.sender == msg.sender, "Not trade creator");
        
        // First verify the punk is properly offered to this contract
        (
            bool isForSale,
            ,
            address seller,
            uint256 minValue,
            address onlySellTo
        ) = ICryptoPunks(CRYPTOPUNKS_ADDRESS).punksOfferedForSale(trade.punkId);

        require(isForSale, "Punk not offered for sale");
        require(seller == msg.sender, "Not the seller");
        require(onlySellTo == address(this), "Not offered to escrow");
        require(minValue == 0, "Price must be 0");

        // Now we can claim the punk
        ICryptoPunks(CRYPTOPUNKS_ADDRESS).buyPunk(trade.punkId);
        
        // Verify the transfer worked
        address newOwner = ICryptoPunks(CRYPTOPUNKS_ADDRESS).punkIndexToAddress(trade.punkId);
        require(newOwner == address(this), "Transfer failed");
        
        trade.isDeposited = true;
        emit PunkDeposited(tradeId, trade.punkId);
    }
    
    function completeTrade(uint256 tradeId) external nonReentrant {
        Trade storage trade = trades[tradeId];
        require(trade.isActive, "Trade not active");
        require(trade.isDeposited, "Punk not deposited");
        
        trade.isActive = false;
        
        // Transfer punk to recipient
        try ICryptoPunks(CRYPTOPUNKS_ADDRESS).transferPunk(trade.recipient, trade.punkId) {
            emit TradeCompleted(tradeId);
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Completion failed: ", reason)));
        } catch {
            revert("Completion failed");
        }
    }
    
    function cancelTrade(uint256 tradeId) external nonReentrant {
        Trade storage trade = trades[tradeId];
        require(trade.isActive, "Trade not active");
        require(trade.sender == msg.sender, "Not trade creator");
        
        trade.isActive = false;
        
        if (trade.isDeposited) {
            // Return punk to sender
            try ICryptoPunks(CRYPTOPUNKS_ADDRESS).transferPunk(trade.sender, trade.punkId) {
                emit TradeCancelled(tradeId);
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("Cancellation failed: ", reason)));
            } catch {
                revert("Cancellation failed");
            }
        }
    }

    // Debug functions
    function getPunkOwner(uint256 punkId) external view returns (address) {
        return ICryptoPunks(CRYPTOPUNKS_ADDRESS).punkIndexToAddress(punkId);
    }
    
    function getTradeDetails(uint256 tradeId) external view returns (
        uint256 punkId,
        address sender,
        address recipient,
        bool isActive,
        bool isDeposited
    ) {
        Trade storage trade = trades[tradeId];
        return (
            trade.punkId,
            trade.sender,
            trade.recipient,
            trade.isActive,
            trade.isDeposited
        );
    }
}