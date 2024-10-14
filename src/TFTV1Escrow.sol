// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ICryptoPunks {
    function punkIndexToAddress(uint256 punkIndex) external view returns (address);
    function transferPunk(address to, uint256 punkIndex) external;
}

contract TFTV1Escrow is ReentrancyGuard, Ownable, ERC721Holder, ERC1155Holder {
    using SafeERC20 for IERC20;

    enum AssetType { ERC20, ERC721, ERC1155, CryptoPunk }

    struct Asset {
        address token;
        uint256 tokenId;
        uint256 amount;
        AssetType assetType;
        address recipient;
        bool isDeposited;
    }

    struct Trade {
        address[] participants;
        mapping(address => Asset[]) assets;
        mapping(address => bool) hasConfirmed;
        uint256 confirmations;
        bool isActive;
        uint256 deadline;
    }

    uint256 public tradeCounter;
    mapping(uint256 => Trade) public trades;
    mapping(uint256 => mapping(address => bool)) public isParticipant;
    uint256 public constant MAX_PARTICIPANTS = 10;
    uint256 public constant MAX_ASSETS_PER_PARTICIPANT = 10;
    uint256 public constant TRADE_DURATION = 7 days;
    address public constant CRYPTOPUNKS_ADDRESS = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;

    event TradeCreated(uint256 indexed tradeId, address[] participants, uint256 duration);
    event AssetDeposited(uint256 indexed tradeId, address participant, address token, uint256 tokenId, uint256 amount, AssetType assetType, address recipient);
    event AssetsReclaimed(uint256 indexed tradeId, address participant);
    event TradeConfirmed(uint256 indexed tradeId, address participant);
    event TradeCompleted(uint256 indexed tradeId);
    event TradeCancelled(uint256 indexed tradeId);

    error InvalidDuration();
    error InvalidParticipantCount();
    error TradeNotActive();
    error TradeNotExpired();
    error TradeDeadlinePassed();
    error NotParticipant();
    error AlreadyConfirmed();
    error MaxAssetsPerParticipantExceeded();
    error NoAssetsDeposited();
    error NoAssetsToReclaim();
    error InvalidRecipientAddress();
    error InvalidTokenAddress();
    error UnsupportedAssetType();
    error AssetAlreadyDeposited();
    error AssetNotFound();
    error AssetsNotFullyDeposited();

    constructor() Ownable(msg.sender) {}

    function createTrade(
        address[] memory _participants,
        Asset[][] memory _assets,
        uint256 _duration
    ) external returns (uint256) {
        if (_participants.length < 2 || _participants.length > MAX_PARTICIPANTS) {
            revert InvalidParticipantCount();
        }

        if (_duration == 0) {
            _duration = TRADE_DURATION;
        }

        if (_duration < 1 days || _duration > 30 days) {
            revert InvalidDuration();
        }

        uint256 tradeId = tradeCounter++;

        Trade storage newTrade = trades[tradeId];
        newTrade.participants = _participants;
        newTrade.isActive = true;
        newTrade.deadline = block.timestamp + _duration;

        for (uint i = 0; i < _participants.length; i++) {
            isParticipant[tradeId][_participants[i]] = true;
            if (_assets[i].length > MAX_ASSETS_PER_PARTICIPANT) {
                revert MaxAssetsPerParticipantExceeded();
            }
            for (uint j = 0; j < _assets[i].length; j++) {
                newTrade.assets[_participants[i]].push(_assets[i][j]);
            }
        }

        emit TradeCreated(tradeId, _participants, _duration);
        return tradeId;
    }

    function depositAsset(
        uint256 _tradeId,
        address _token,
        uint256 _tokenId,
        uint256 _amount,
        AssetType _assetType
    ) external nonReentrant {
        Trade storage trade = trades[_tradeId];
        if (!trade.isActive) revert TradeNotActive();
        if (block.timestamp >= trade.deadline) revert TradeDeadlinePassed();
        if (!isParticipant[_tradeId][msg.sender]) revert NotParticipant();

        Asset[] storage assets = trade.assets[msg.sender];
        bool assetFound = false;
        for (uint i = 0; i < assets.length; i++) {
            Asset storage asset = assets[i];
            if (asset.token == _token && asset.tokenId == _tokenId && asset.assetType == _assetType) {
                if (asset.isDeposited) revert AssetAlreadyDeposited();
                _transferAsset(asset, msg.sender, address(this));
                asset.isDeposited = true;
                assetFound = true;
                emit AssetDeposited(_tradeId, msg.sender, _token, _tokenId, _amount, _assetType, asset.recipient);
                break;
            }
        }

        if (!assetFound) revert AssetNotFound();
    }

    function batchDepositAssets(uint256 _tradeId) external nonReentrant {
        Trade storage trade = trades[_tradeId];
        if (!trade.isActive) revert TradeNotActive();
        if (block.timestamp >= trade.deadline) revert TradeDeadlinePassed();
        if (!isParticipant[_tradeId][msg.sender]) revert NotParticipant();

        Asset[] storage assets = trade.assets[msg.sender];
        for (uint i = 0; i < assets.length; i++) {
            Asset storage asset = assets[i];
            if (!asset.isDeposited) {
                _transferAsset(asset, msg.sender, address(this));
                asset.isDeposited = true;
                emit AssetDeposited(_tradeId, msg.sender, asset.token, asset.tokenId, asset.amount, asset.assetType, asset.recipient);
            }
        }
    }

    function confirmTrade(uint256 _tradeId) external nonReentrant {
        Trade storage trade = trades[_tradeId];
        if (!trade.isActive) revert TradeNotActive();
        if (block.timestamp >= trade.deadline) revert TradeDeadlinePassed();
        if (!isParticipant[_tradeId][msg.sender]) revert NotParticipant();
        if (trade.hasConfirmed[msg.sender]) revert AlreadyConfirmed();

        Asset[] storage assets = trade.assets[msg.sender];
        for (uint i = 0; i < assets.length; i++) {
            if (!assets[i].isDeposited) revert AssetsNotFullyDeposited();
        }

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
                Asset storage asset = assets[j];
                if (asset.isDeposited) {
                    _transferAsset(asset, address(this), participant);
                    asset.isDeposited = false;
                }
            }
        }

        emit TradeCancelled(_tradeId);
    }

    function executeTrade(uint256 _tradeId) internal {
        Trade storage trade = trades[_tradeId];
        uint256 participantCount = trade.participants.length;

        trade.isActive = false;

        for (uint i = 0; i < participantCount; i++) {
            address from = trade.participants[i];
            Asset[] storage assets = trade.assets[from];

            for (uint j = 0; j < assets.length; j++) {
                Asset storage asset = assets[j];
                _transferAsset(asset, address(this), asset.recipient);
                asset.isDeposited = false;
            }
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
        bool assetsReclaimed = false;
        for (uint i = 0; i < assets.length; i++) {
            Asset storage asset = assets[i];
            if (asset.isDeposited) {
                _transferAsset(asset, address(this), msg.sender);
                asset.isDeposited = false;
                assetsReclaimed = true;
            }
        }

        if (!assetsReclaimed) revert NoAssetsToReclaim();

        emit AssetsReclaimed(_tradeId, msg.sender);

        bool allAssetsReclaimed = true;
        for (uint i = 0; i < trade.participants.length; i++) {
            Asset[] storage participantAssets = trade.assets[trade.participants[i]];
            for (uint j = 0; j < participantAssets.length; j++) {
                if (participantAssets[j].isDeposited) {
                    allAssetsReclaimed = false;
                    break;
                }
            }
            if (!allAssetsReclaimed) break;
        }
        if (allAssetsReclaimed) {
            trade.isActive = false;
            emit TradeCancelled(_tradeId);
        }
    }

    function _transferAsset(
        Asset memory asset,
        address from,
        address to
    ) internal {
        if (asset.assetType == AssetType.ERC20) {
            IERC20(asset.token).safeTransferFrom(from, to, asset.amount);
        } else if (asset.assetType == AssetType.ERC721) {
            IERC721(asset.token).safeTransferFrom(from, to, asset.tokenId);
        } else if (asset.assetType == AssetType.ERC1155) {
            IERC1155(asset.token).safeTransferFrom(from, to, asset.tokenId, asset.amount, "");
        } else if (asset.assetType == AssetType.CryptoPunk) {
            ICryptoPunks(CRYPTOPUNKS_ADDRESS).transferPunk(to, asset.tokenId);
        } else {
            revert UnsupportedAssetType();
        }
    }

    function areAllAssetsDeposited(uint256 _tradeId) external view returns (bool) {
        Trade storage trade = trades[_tradeId];
        for (uint i = 0; i < trade.participants.length; i++) {
            Asset[] storage assets = trade.assets[trade.participants[i]];
            for (uint j = 0; j < assets.length; j++) {
                if (!assets[j].isDeposited) {
                    return false;
                }
            }
        }
        return true;
    }
}