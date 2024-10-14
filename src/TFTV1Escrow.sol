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
        bool isActive;
        uint256 depositedAssetCount;
        uint256 totalAssetCount;
    }

    uint256 public tradeCounter;
    mapping(uint256 => Trade) public trades;
    mapping(uint256 => mapping(address => bool)) public isParticipant;
    uint256 public constant MAX_PARTICIPANTS = 10;
    uint256 public constant MAX_ASSETS_PER_PARTICIPANT = 10;
    address public constant CRYPTOPUNKS_ADDRESS = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;

    event TradeCreated(uint256 indexed tradeId, address[] participants);
    event AssetDeposited(uint256 indexed tradeId, address participant, address token, uint256 tokenId, uint256 amount, AssetType assetType, address recipient);
    event TradeCompleted(uint256 indexed tradeId);
    event TradeCancelled(uint256 indexed tradeId);

    error InvalidParticipantCount();
    error TradeNotActive();
    error NotParticipant();
    error MaxAssetsPerParticipantExceeded();
    error AssetAlreadyDeposited();
    error AssetNotFound();
    error UnsupportedAssetType();

    constructor() Ownable(msg.sender) {}

    function createTrade(
        address[] memory _participants,
        Asset[][] memory _assets
    ) external returns (uint256) {
        if (_participants.length < 2 || _participants.length > MAX_PARTICIPANTS) {
            revert InvalidParticipantCount();
        }

        uint256 tradeId = tradeCounter++;

        Trade storage newTrade = trades[tradeId];
        newTrade.participants = _participants;
        newTrade.isActive = true;

        for (uint i = 0; i < _participants.length; i++) {
            isParticipant[tradeId][_participants[i]] = true;
            if (_assets[i].length > MAX_ASSETS_PER_PARTICIPANT) {
                revert MaxAssetsPerParticipantExceeded();
            }
            for (uint j = 0; j < _assets[i].length; j++) {
                newTrade.assets[_participants[i]].push(_assets[i][j]);
                newTrade.totalAssetCount++;
            }
        }

        emit TradeCreated(tradeId, _participants);
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
                trade.depositedAssetCount++;
                emit AssetDeposited(_tradeId, msg.sender, _token, _tokenId, _amount, _assetType, asset.recipient);
                break;
            }
        }

        if (!assetFound) revert AssetNotFound();

        if (trade.depositedAssetCount == trade.totalAssetCount) {
            executeTrade(_tradeId);
        }
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

    function cancelTrade(uint256 _tradeId) external nonReentrant {
        Trade storage trade = trades[_tradeId];
        if (!trade.isActive) revert TradeNotActive();
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

    function getTradeStatus(uint256 _tradeId) external view returns (bool isActive, uint256 depositedAssetCount, uint256 totalAssetCount) {
        Trade storage trade = trades[_tradeId];
        return (trade.isActive, trade.depositedAssetCount, trade.totalAssetCount);
    }
}