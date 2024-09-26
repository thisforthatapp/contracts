// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TFTV1Escrow is ReentrancyGuard, Ownable {
    struct Asset {
        address token;
        uint256 tokenId;
        uint256 amount;
        bool isNFT;
    }

    struct Trade {
        address[] participants;
        mapping(address => Asset[]) assets;
        mapping(address => bool) hasConfirmed;
        mapping(address => bool) hasPaidFee;
        uint256 confirmations;
        uint256 feesPaid;
        bool isActive;
        uint256 deadline;
    }

    uint256 public tradeCounter;
    mapping(uint256 => Trade) public trades;
    uint256 public constant MAX_PARTICIPANTS = 10;
    uint256 public constant TRADE_DURATION = 1 days;
    uint256 public flatFee = 0.005 ether;
    address public feeRecipient;

    event TradeCreated(uint256 indexed tradeId, address[] participants);
    event AssetDeposited(uint256 indexed tradeId, address participant, address token, uint256 tokenId, uint256 amount, bool isNFT);
    event TradeConfirmed(uint256 indexed tradeId, address participant);
    event TradeCompleted(uint256 indexed tradeId);
    event TradeCancelled(uint256 indexed tradeId);
    event FeePaid(uint256 indexed tradeId, address participant);
    event FlatFeeUpdated(uint256 newFlatFee);
    event FeeRecipientUpdated(address newFeeRecipient);

    error InvalidParticipantCount();
    error TradeNotActive();
    error TradeDeadlinePassed();
    error NotParticipant();
    error FeeNotPaid();
    error IncorrectFeeAmount();
    error AlreadyConfirmed();
    error ERC20TransferFailed();

    constructor(address initialFeeRecipient) {
        feeRecipient = initialFeeRecipient;
    }

    function createTrade(address[] memory _participants) external returns (uint256) {
        if (_participants.length < 2 || _participants.length > MAX_PARTICIPANTS) {
            revert InvalidParticipantCount();
        }
        
        uint256 tradeId = tradeCounter++;
        Trade storage newTrade = trades[tradeId];
        newTrade.participants = _participants;
        newTrade.isActive = true;
        newTrade.deadline = block.timestamp + TRADE_DURATION;

        emit TradeCreated(tradeId, _participants);
        return tradeId;
    }

    function depositAsset(uint256 _tradeId, address _token, uint256 _tokenId, uint256 _amount, bool _isNFT) external payable nonReentrant {
        Trade storage trade = trades[_tradeId];
        if (!trade.isActive) revert TradeNotActive();
        if (block.timestamp >= trade.deadline) revert TradeDeadlinePassed();
        if (!isParticipant(_tradeId, msg.sender)) revert NotParticipant();

        if (!trade.hasPaidFee[msg.sender]) {
            if (msg.value != flatFee) revert IncorrectFeeAmount();
            trade.hasPaidFee[msg.sender] = true;
            trade.feesPaid++;
            emit FeePaid(_tradeId, msg.sender);
        }

        if (_isNFT) {
            IERC721(_token).transferFrom(msg.sender, address(this), _tokenId);
        } else {
            if (!IERC20(_token).transferFrom(msg.sender, address(this), _amount)) {
                revert ERC20TransferFailed();
            }
        }

        trade.assets[msg.sender].push(Asset(_token, _tokenId, _amount, _isNFT));
        emit AssetDeposited(_tradeId, msg.sender, _token, _tokenId, _amount, _isNFT);
    }

    function confirmTrade(uint256 _tradeId) external {
        Trade storage trade = trades[_tradeId];
        if (!trade.isActive) revert TradeNotActive();
        if (block.timestamp >= trade.deadline) revert TradeDeadlinePassed();
        if (!isParticipant(_tradeId, msg.sender)) revert NotParticipant();
        if (trade.hasConfirmed[msg.sender]) revert AlreadyConfirmed();
        if (!trade.hasPaidFee[msg.sender]) revert FeeNotPaid();

        trade.hasConfirmed[msg.sender] = true;
        trade.confirmations++;

        emit TradeConfirmed(_tradeId, msg.sender);

        if (trade.confirmations == trade.participants.length) {
            executeTrade(_tradeId);
        }
    }

    function cancelTrade(uint256 _tradeId) external {
        Trade storage trade = trades[_tradeId];
        if (!trade.isActive) revert TradeNotActive();
        if (!isParticipant(_tradeId, msg.sender)) revert NotParticipant();

        for (uint i = 0; i < trade.participants.length; i++) {
            address participant = trade.participants[i];
            Asset[] storage assets = trade.assets[participant];
            for (uint j = 0; j < assets.length; j++) {
                Asset memory asset = assets[j];
                if (asset.isNFT) {
                    IERC721(asset.token).transferFrom(address(this), participant, asset.tokenId);
                } else {
                    IERC20(asset.token).transfer(participant, asset.amount);
                }
            }
            delete trade.assets[participant];
        }

        trade.isActive = false;
        emit TradeCancelled(_tradeId);
    }

    function executeTrade(uint256 _tradeId) internal {
        Trade storage trade = trades[_tradeId];
        uint256 participantCount = trade.participants.length;

        for (uint i = 0; i < participantCount; i++) {
            address from = trade.participants[i];
            address to = trade.participants[(i + 1) % participantCount];
            Asset[] storage assets = trade.assets[from];

            for (uint j = 0; j < assets.length; j++) {
                Asset memory asset = assets[j];
                if (asset.isNFT) {
                    IERC721(asset.token).transferFrom(address(this), to, asset.tokenId);
                } else {
                    IERC20(asset.token).transfer(to, asset.amount);
                }
            }
            delete trade.assets[from];
        }

        payable(feeRecipient).transfer(trade.feesPaid * flatFee);

        trade.isActive = false;
        emit TradeCompleted(_tradeId);
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

    function setFlatFee(uint256 _newFlatFee) external onlyOwner {
        flatFee = _newFlatFee;
        emit FlatFeeUpdated(_newFlatFee);
    }

    function setFeeRecipient(address _newFeeRecipient) external onlyOwner {
        feeRecipient = _newFeeRecipient;
        emit FeeRecipientUpdated(_newFeeRecipient);
    }

    receive() external payable {}
}