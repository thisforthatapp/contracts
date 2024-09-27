// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TFTV1Escrow is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    struct Asset {
        address token;
        uint256 tokenId;
        uint256 amount;
        bool isNFT;
        address recipient;
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
    mapping(uint256 => mapping(address => bool)) public isParticipant;
    uint256 public constant MAX_PARTICIPANTS = 10;
    uint256 public constant MAX_ASSETS_PER_PARTICIPANT = 10;
    uint256 public constant TRADE_DURATION = 7 days;
    uint256 public flatFee = 0.005 ether;
    uint256 public accumulatedFees;
    address public feeRecipient;

    event TradeCreated(uint256 indexed tradeId, address[] participants, uint256 duration);
    event AssetDeposited(uint256 indexed tradeId, address participant, address token, uint256 tokenId, uint256 amount, bool isNFT, address recipient);
    event AssetsReclaimed(uint256 indexed tradeId, address participant);
    event TradeConfirmed(uint256 indexed tradeId, address participant);
    event TradeCompleted(uint256 indexed tradeId);
    event TradeCancelled(uint256 indexed tradeId);
    event FeePaid(uint256 indexed tradeId, address participant);
    event FlatFeeUpdated(uint256 newFlatFee);
    event FeeRecipientUpdated(address newFeeRecipient);

    error InvalidDuration();
    error InvalidParticipantCount();
    error TradeNotActive();
    error TradeNotExpired();
    error TradeDeadlinePassed();
    error NotParticipant();
    error FeeNotPaid();
    error IncorrectFeeAmount();
    error AlreadyConfirmed();
    error MaxAssetsPerParticipantExceeded();
    error FeeRecipientCannotBeZeroAddress();
    error OnlyFeeRecipientCanWithdraw();
    error NoAssetsDeposited();
    error NoAssetsToReclaim();
    error InsufficientFees();
    error FeeTransferFailed();
    error InvalidRecipientAddress();
    error InvalidTokenAddress();

    constructor(address initialFeeRecipient) {
        feeRecipient = initialFeeRecipient;
    }

    function createTrade(address[] memory _participants, uint256 _duration) external returns (uint256) {
        if (_participants.length < 2 || _participants.length > MAX_PARTICIPANTS) {
            revert InvalidParticipantCount();
        }
        
        // Set default duration if not specified
        if (_duration == 0) {
            _duration = TRADE_DURATION;
        }

        // Ensure duration is within 1 day to 30 days
        if (_duration < 1 days || _duration > 30 days) {
            revert InvalidDuration();
        }

        uint256 tradeId = tradeCounter++;

        for (uint i = 0; i < _participants.length; i++) {
            isParticipant[tradeId][_participants[i]] = true;
        }

        Trade storage newTrade = trades[tradeId];
        newTrade.participants = _participants;
        newTrade.isActive = true;
        newTrade.deadline = block.timestamp + _duration;

        emit TradeCreated(tradeId, _participants, _duration);
        return tradeId;
    }

    function depositAsset(uint256 _tradeId, address _token, uint256 _tokenId, uint256 _amount, bool _isNFT, address memory _recipient) external payable nonReentrant {
        Trade storage trade = trades[_tradeId];
        if (!trade.isActive) revert TradeNotActive();
        if (block.timestamp >= trade.deadline) revert TradeDeadlinePassed();
        if (!isParticipant[_tradeId][msg.sender]) revert NotParticipant();
        if (!isParticipant[_tradeId][_recipient]) revert NotParticipant();
        if (trade.assets[msg.sender].length >= MAX_ASSETS_PER_PARTICIPANT) revert MaxAssetsPerParticipantExceeded();
        if (_recipient == address(0)) revert InvalidRecipientAddress();
        if (_token == address(0)) revert InvalidTokenAddress();

        if (!trade.hasPaidFee[msg.sender]) {
            if (msg.value != flatFee) revert IncorrectFeeAmount();
            trade.hasPaidFee[msg.sender] = true;
            trade.feesPaid++;
            accumulatedFees += flatFee;
            emit FeePaid(_tradeId, msg.sender);
        }

        if (_isNFT) {
            IERC721(_token).transferFrom(msg.sender, address(this), _tokenId);
        } else {
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        }

        trade.assets[msg.sender].push(Asset(_token, _tokenId, _amount, _isNFT, _recipient));
        emit AssetDeposited(_tradeId, msg.sender, _token, _tokenId, _amount, _isNFT, _recipient);
    }

    function confirmTrade(uint256 _tradeId) external nonReentrant {
        Trade storage trade = trades[_tradeId];
        if (!trade.isActive) revert TradeNotActive();
        if (block.timestamp >= trade.deadline) revert TradeDeadlinePassed();
        if (!isParticipant[_tradeId][msg.sender]) revert NotParticipant();
        if (trade.hasConfirmed[msg.sender]) revert AlreadyConfirmed();
        if (!trade.hasPaidFee[msg.sender]) revert FeeNotPaid();
        if (trade.assets[msg.sender].length == 0) revert NoAssetsDeposited();


        trade.hasConfirmed[msg.sender] = true;
        trade.confirmations++;

        emit TradeConfirmed(_tradeId, msg.sender);

        if (trade.confirmations == trade.participants.length) {
            executeTrade(_tradeId);
        }
    }

    function cancelTrade(uint256 _tradeId) external nonReentrant {
        Trade storage trade = trades[_tradeId];
        if (!trade.isActive) revert TradeNotActive();
        if (block.timestamp >= trade.deadline) revert TradeDeadlinePassed();
        if (!isParticipant[_tradeId][msg.sender]) revert NotParticipant();

        trade.isActive = false;

        for (uint i = 0; i < trade.participants.length; i++) {
            address participant = trade.participants[i];
            Asset[] storage assets = trade.assets[participant];
            for (uint j = 0; j < assets.length; j++) {
                Asset memory asset = assets[j];
                if (asset.isNFT) {
                    IERC721(asset.token).transferFrom(address(this), participant, asset.tokenId);
                } else {
                    IERC20(asset.token).safeTransfer(participant, asset.amount);
                }
            }
            delete trade.assets[participant];
        }

        emit TradeCancelled(_tradeId);
    }

    function executeTrade(uint256 _tradeId) internal nonReentrant {
        Trade storage trade = trades[_tradeId];
        uint256 participantCount = trade.participants.length;

        trade.isActive = false;

        for (uint i = 0; i < participantCount; i++) {
            address from = trade.participants[i];
            Asset[] storage assets = trade.assets[from];

            for (uint j = 0; j < assets.length; j++) {
                Asset memory asset = assets[j];
                address to = asset.recipient;

                if (asset.isNFT) {
                    IERC721(asset.token).transferFrom(address(this), to, asset.tokenId);
                } else {
                    IERC20(asset.token).safeTransfer(to, asset.amount);
                }
            }
            delete trade.assets[from];
        }
        
        emit TradeCompleted(_tradeId);
    }

    function reclaimAssets(uint256 _tradeId) external nonReentrant {
        Trade storage trade = trades[_tradeId];
        if (trade.isActive && block.timestamp < trade.deadline) {
            revert TradeNotExpired();
        }
        if (!isParticipant[_tradeId][msg.sender]) revert NotParticipant();

        Asset[] storage assets = trade.assets[msg.sender];
        if (assets.length == 0) revert NoAssetsToReclaim();

        // Transfer assets back to the participant
        for (uint i = 0; i < assets.length; i++) {
            Asset memory asset = assets[i];
            if (asset.isNFT) {
                IERC721(asset.token).transferFrom(address(this), msg.sender, asset.tokenId);
            } else {
                IERC20(asset.token).safeTransfer(msg.sender, asset.amount);
            }
        }
        delete trade.assets[msg.sender];

        emit AssetsReclaimed(_tradeId, msg.sender);

        // Check if all participants have reclaimed their assets
        bool allAssetsReclaimed = true;
        for (uint i = 0; i < trade.participants.length; i++) {
            if (trade.assets[trade.participants[i]].length > 0) {
                allAssetsReclaimed = false;
                break;
            }
        }
        if (allAssetsReclaimed) {
            trade.isActive = false;
            emit TradeCancelled(_tradeId);
        }
    }

    function setFlatFee(uint256 _newFlatFee) external onlyOwner {
        flatFee = _newFlatFee;
        emit FlatFeeUpdated(_newFlatFee);
    }

    function setFeeRecipient(address _newFeeRecipient) external onlyOwner {
        if (_newFeeRecipient == address(0)) revert FeeRecipientCannotBeZeroAddress();
        feeRecipient = _newFeeRecipient;
        emit FeeRecipientUpdated(_newFeeRecipient);
    }

    function withdrawFees(uint256 _amount) external nonReentrant {
        if (msg.sender != feeRecipient) revert OnlyFeeRecipientCanWithdraw();
        if (_amount > accumulatedFees) revert InsufficientFees();
        
        accumulatedFees -= _amount;
        (bool success, ) = payable(feeRecipient).call{value: _amount}("");
        if (!success) revert FeeTransferFailed();
    }

    receive() external payable {}
}
