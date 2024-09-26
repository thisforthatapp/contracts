/* TODO: rewrite cross chain implementation to minimize onchain footprint. Users are already relying on trust of TFT. Minimize the gas. */

// SPDX-License-Identifier: MIT
/*
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract TFTV1MultiChainEscrow is Ownable, ReentrancyGuard {
    struct Asset {
        address token;
        uint256 tokenId;
        uint256 amount;
        bool isNFT;
        uint256 chainId;
    }

    struct Trade {
        address[] participants;
        mapping(address => Asset[]) assetsToReceive;
        mapping(address => bool) hasConfirmed;
        mapping(address => bool) hasReceived;
        uint256 confirmations;
        bool isActive;
        uint256 deadline;
        bool adminConfirmed;
    }

    uint256 public tradeCounter;
    mapping(uint256 => Trade) public trades;
    uint256 public constant MAX_PARTICIPANTS = 10;
    uint256 public constant TRADE_DURATION = 7 days;
    uint256 public constant FEE_PERCENTAGE = 5; // 0.5%

    event TradeCreated(uint256 indexed tradeId, address[] participants);
    event AssetRegistered(uint256 indexed tradeId, address participant, address token, uint256 tokenId, uint256 amount, bool isNFT, uint256 chainId);
    event TradeConfirmedByParticipant(uint256 indexed tradeId, address participant);
    event TradeConfirmedByAdmin(uint256 indexed tradeId);
    event AssetReceived(uint256 indexed tradeId, address participant);
    event TradeCancelled(uint256 indexed tradeId);

    modifier onlyAdmin() {
        require(owner() == _msgSender(), "Caller is not the admin");
        _;
    }

    function createTrade(address[] memory _participants) external returns (uint256) {
        require(_participants.length >= 2 && _participants.length <= MAX_PARTICIPANTS, "Invalid number of participants");
        
        uint256 tradeId = tradeCounter++;
        Trade storage newTrade = trades[tradeId];
        newTrade.participants = _participants;
        newTrade.isActive = true;
        newTrade.deadline = block.timestamp + TRADE_DURATION;

        emit TradeCreated(tradeId, _participants);
        return tradeId;
    }

    function registerAssetToReceive(
        uint256 _tradeId,
        address _token,
        uint256 _tokenId,
        uint256 _amount,
        bool _isNFT,
        uint256 _chainId
    ) external {
        Trade storage trade = trades[_tradeId];
        require(trade.isActive, "Trade is not active");
        require(block.timestamp < trade.deadline, "Trade deadline passed");
        require(isParticipant(_tradeId, msg.sender), "Not a participant in this trade");

        trade.assetsToReceive[msg.sender].push(Asset(_token, _tokenId, _amount, _isNFT, _chainId));
        emit AssetRegistered(_tradeId, msg.sender, _token, _tokenId, _amount, _isNFT, _chainId);
    }

    function confirmTrade(uint256 _tradeId) external {
        Trade storage trade = trades[_tradeId];
        require(trade.isActive, "Trade is not active");
        require(block.timestamp < trade.deadline, "Trade deadline passed");
        require(isParticipant(_tradeId, msg.sender), "Not a participant in this trade");
        require(!trade.hasConfirmed[msg.sender], "Already confirmed");

        trade.hasConfirmed[msg.sender] = true;
        trade.confirmations++;

        emit TradeConfirmedByParticipant(_tradeId, msg.sender);
    }

    function adminConfirmTrade(uint256 _tradeId) external onlyAdmin {
        Trade storage trade = trades[_tradeId];
        require(trade.isActive, "Trade is not active");
        require(trade.confirmations == trade.participants.length, "Not all participants have confirmed");
        require(!trade.adminConfirmed, "Admin already confirmed");

        trade.adminConfirmed = true;
        emit TradeConfirmedByAdmin(_tradeId);
    }

    function confirmReceived(uint256 _tradeId) external nonReentrant {
        Trade storage trade = trades[_tradeId];
        require(trade.isActive, "Trade is not active");
        require(trade.adminConfirmed, "Admin has not confirmed the trade");
        require(isParticipant(_tradeId, msg.sender), "Not a participant in this trade");
        require(!trade.hasReceived[msg.sender], "Already confirmed receipt");

        trade.hasReceived[msg.sender] = true;
        emit AssetReceived(_tradeId, msg.sender);

        // Check if all participants have received their assets
        bool allReceived = true;
        for (uint i = 0; i < trade.participants.length; i++) {
            if (!trade.hasReceived[trade.participants[i]]) {
                allReceived = false;
                break;
            }
        }

        if (allReceived) {
            trade.isActive = false;
        }
    }

    function cancelTrade(uint256 _tradeId) external onlyAdmin {
        Trade storage trade = trades[_tradeId];
        require(trade.isActive, "Trade is not active");

        trade.isActive = false;
        emit TradeCancelled(_tradeId);
    }

    function isParticipant(uint256 _tradeId, address _participant) public view returns (bool) {
        Trade storage trade = trades[_tradeId];
        for (uint i = 0; i < trade.participants.length; i++) {
            if (trade.participants[i] == _participant) {
                return true;
            }
        }
        return false;
    }

    // Function to withdraw collected fees (implement appropriate logic for cross-chain fee collection)
    function withdrawFees(address _token, uint256 _amount) external onlyAdmin {
        require(IERC20(_token).transfer(owner(), _amount), "Fee transfer failed");
    }

    // Additional helper functions can be added here (e.g., to view trade details, extend deadline, etc.)
}
*/