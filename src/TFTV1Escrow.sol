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

/**
 * @title TFTV1Escrow
 * @dev A contract for facilitating multi-party trades of various asset types (ERC20, ERC721, ERC1155, CryptoPunks)
 */
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
    uint256 public constant MAX_BATCH_DEPOSITS = 20;
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
    error TradeNotFound();

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Creates a new trade with the given participants and assets
     * @param _participants Array of participant addresses
     * @param _assets 2D array of assets, where each inner array corresponds to a participant
     * @return tradeId The ID of the newly created trade
     */
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

    /**
     * @dev Allows a participant to deposit an asset for a trade
     * @param _tradeId The ID of the trade
     * @param _token The address of the token contract
     * @param _tokenId The ID of the token (for ERC721 and ERC1155)
     * @param _amount The amount of tokens (for ERC20 and ERC1155)
     * @param _assetType The type of asset being deposited
     */
    function depositAsset(
        uint256 _tradeId,
        address _token,
        uint256 _tokenId,
        uint256 _amount,
        AssetType _assetType
    ) external nonReentrant {
        Trade storage trade = trades[_tradeId];
        if (!trade.isActive) revert TradeNotActive();

        bool assetFound = false;
        for (uint i = 0; i < trade.participants.length; i++) {
            Asset[] storage assets = trade.assets[trade.participants[i]];
            for (uint j = 0; j < assets.length; j++) {
                Asset storage asset = assets[j];
                if (asset.token == _token && asset.tokenId == _tokenId && asset.assetType == _assetType) {
                    if (asset.isDeposited) revert AssetAlreadyDeposited();
                    _transferAsset(asset, msg.sender, address(this));
                    asset.isDeposited = true;
                    assetFound = true;
                    trade.depositedAssetCount++;
                    emit AssetDeposited(_tradeId, msg.sender, _token, _tokenId, _amount, _assetType, asset.recipient);
                    return;
                }
            }
        }

        if (!assetFound) revert AssetNotFound();

        if (trade.depositedAssetCount == trade.totalAssetCount) {
            _executeTrade(_tradeId);
        }
    }

    /**
    * @dev Allows a user to deposit multiple assets for a trade in a single transaction
    * @param _tradeId The ID of the trade
    * @param _tokens Array of token addresses
    * @param _tokenIds Array of token IDs (for ERC721 and ERC1155)
    * @param _amounts Array of token amounts (for ERC20 and ERC1155)
    * @param _assetTypes Array of asset types
    */
    function batchDepositAssets(
        uint256 _tradeId,
        address[] calldata _tokens,
        uint256[] calldata _tokenIds,
        uint256[] calldata _amounts,
        AssetType[] calldata _assetTypes
    ) external nonReentrant {
        require(_tokens.length == _tokenIds.length && _tokens.length == _amounts.length && _tokens.length == _assetTypes.length, "Input arrays must have the same length");
        require(_tokens.length <= MAX_BATCH_DEPOSITS, "Batch size exceeds maximum allowed");

        Trade storage trade = trades[_tradeId];
        if (!trade.isActive) revert TradeNotActive();

        for (uint i = 0; i < _tokens.length; i++) {
            bool assetFound = false;
            for (uint j = 0; j < trade.participants.length; j++) {
                Asset[] storage assets = trade.assets[trade.participants[j]];
                for (uint k = 0; k < assets.length; k++) {
                    Asset storage asset = assets[k];
                    if (asset.token == _tokens[i] && asset.tokenId == _tokenIds[i] && asset.assetType == _assetTypes[i]) {
                        if (asset.isDeposited) revert AssetAlreadyDeposited();
                        _transferAsset(asset, msg.sender, address(this));
                        asset.isDeposited = true;
                        assetFound = true;
                        trade.depositedAssetCount++;
                        emit AssetDeposited(_tradeId, msg.sender, _tokens[i], _tokenIds[i], _amounts[i], _assetTypes[i], asset.recipient);
                        break;
                    }
                }
                if (assetFound) break;
            }
            if (!assetFound) revert AssetNotFound();
        }

        if (trade.depositedAssetCount == trade.totalAssetCount) {
            _executeTrade(_tradeId);
        }
    }

    /**
     * @dev Cancels an active trade and returns deposited assets to their owners
     * @param _tradeId The ID of the trade to cancel
     */
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

    /**
     * @dev Internal function to execute a trade once all assets are deposited
     * @param _tradeId The ID of the trade to execute
     * @notice This function transfers all deposited assets to their respective recipients and marks the trade as inactive
     */
    function _executeTrade(uint256 _tradeId) internal {
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

    /**
     * @dev Internal function to transfer an asset between addresses
     * @param asset The asset to transfer
     * @param from The address to transfer from
     * @param to The address to transfer to
     * @notice This function handles the transfer of different asset types (ERC20, ERC721, ERC1155, CryptoPunk)
     * @notice It uses the appropriate transfer method based on the asset type
     */
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

    /**
     * @dev Retrieves the status of a single trade
     * @param _tradeId The ID of the trade
     * @return isActive Whether the trade is still active
     * @return depositedAssetCount The number of assets deposited for this trade
     * @return totalAssetCount The total number of assets involved in this trade
     */
    function getTradeStatus(uint256 _tradeId) external view returns (bool isActive, uint256 depositedAssetCount, uint256 totalAssetCount) {
        Trade storage trade = trades[_tradeId];
        return (trade.isActive, trade.depositedAssetCount, trade.totalAssetCount);
    }

    /**
     * @dev Retrieves the status of multiple trades
     * @param _tradeIds An array of trade IDs to query (max 10)
     * @return isActive An array of booleans indicating whether each trade is active
     * @return depositedAssetCount An array of deposited asset counts for each trade
     * @return totalAssetCount An array of total asset counts for each trade
     */
    function getMultipleTradeStatuses(uint256[] calldata _tradeIds) external view returns (
        bool[] memory isActive,
        uint256[] memory depositedAssetCount,
        uint256[] memory totalAssetCount
    ) {
        require(_tradeIds.length <= 10, "Too many trade IDs requested");

        isActive = new bool[](_tradeIds.length);
        depositedAssetCount = new uint256[](_tradeIds.length);
        totalAssetCount = new uint256[](_tradeIds.length);

        for (uint256 i = 0; i < _tradeIds.length; i++) {
            Trade storage trade = trades[_tradeIds[i]];
            isActive[i] = trade.isActive;
            depositedAssetCount[i] = trade.depositedAssetCount;
            totalAssetCount[i] = trade.totalAssetCount;
        }

        return (isActive, depositedAssetCount, totalAssetCount);
    }

    /**
     * @dev Retrieves detailed information about a trade
     * @param _tradeId The ID of the trade
     * @return participants An array of participant addresses
     * @return assets A 2D array of assets involved in the trade
     * @return isActive Whether the trade is still active
     * @return depositedAssetCount The number of assets deposited for this trade
     * @return totalAssetCount The total number of assets involved in this trade
     */
    function getTradeAssets(uint256 _tradeId) external view returns (
        address[] memory participants,
        Asset[][] memory assets,
        bool isActive,
        uint256 depositedAssetCount,
        uint256 totalAssetCount
    ) {
        Trade storage trade = trades[_tradeId];
        if (trade.participants.length == 0) revert TradeNotFound();

        participants = trade.participants;
        assets = new Asset[][](participants.length);

        for (uint i = 0; i < participants.length; i++) {
            assets[i] = trade.assets[participants[i]];
        }

        isActive = trade.isActive;
        depositedAssetCount = trade.depositedAssetCount;
        totalAssetCount = trade.totalAssetCount;
    }
}