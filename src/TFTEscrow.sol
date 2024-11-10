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

/**
 * @notice Interface for interacting with the CryptoPunks contract
 * @dev Defines the required functions for buying, selling, and transferring CryptoPunks
 */
interface ICryptoPunks {
    function punkIndexToAddress(uint256 punkIndex) external view returns (address);
    function buyPunk(uint256 punkIndex) external payable;
    function punksOfferedForSale(uint256 punkIndex) external view returns (
        bool isForSale,
        uint256 pIndex,
        address seller,
        uint256 minValue,
        address onlySellTo
    );
    function offerPunkForSaleToAddress(uint256 punkIndex, uint256 minSalePriceInWei, address toAddress) external;
    function transferPunk(address to, uint256 punkIndex) external;
}

/**
████████╗███████╗████████╗
╚══██╔══╝██╔════╝╚══██╔══╝
   ██║   █████╗     ██║   
   ██║   ██╔══╝     ██║   
   ██║   ██║        ██║   
   ╚═╝   ╚═╝        ╚═╝

 * @title This For That - A Multi-Asset Escrow Contract
 * @notice This contract enables secure peer-to-peer trading of various crypto assets
 * @dev Supports ERC20, ERC721, ERC1155 tokens and CryptoPunks
 */
contract TFTEscrow is ReentrancyGuard, Ownable, ERC721Holder, ERC1155Holder {
    using SafeERC20 for IERC20;

    /**
     * @notice Enum defining the supported asset types
     */
    enum AssetType { ERC20, ERC721, ERC1155, CryptoPunk }

    /**
     * @notice Struct containing information about a single asset in a trade
     * @param token The contract address of the token
     * @param recipient The address that will receive the asset after trade completion
     * @param depositor The address that deposited the asset
     * @param tokenId The ID of the token (for ERC721, ERC1155, and CryptoPunks)
     * @param amount The amount of tokens (for ERC20 and ERC1155)
     * @param assetType The type of the asset (ERC20, ERC721, etc.)
     * @param isDeposited Whether the asset has been deposited into the contract
     */
    struct Asset {
        address token;
        address recipient;
        address depositor;
        uint256 tokenId;
        uint96 amount;
        AssetType assetType;
        bool isDeposited;
    }

    /**
     * @notice Struct containing information about a trade
     * @param depositedAssetCount Number of assets currently deposited
     * @param totalAssetCount Total number of assets in the trade
     * @param isActive Whether the trade is currently active
     * @param assets Array of assets involved in the trade
     */
    struct Trade {
        uint256 depositedAssetCount;
        uint256 totalAssetCount;
        bool isActive;
        Asset[] assets;
    }

    // Storage mappings
    mapping(uint256 => Trade) public trades;
    mapping(uint256 => mapping(address => bool)) public isParticipant;
    mapping(uint256 => mapping(bytes32 => bool)) private validAssets;

    // Constants
    uint256 public constant MAX_PARTICIPANTS = 10;
    uint256 public constant MAX_ASSETS_PER_PARTICIPANT = 10;
    uint256 public constant MAX_BATCH_DEPOSITS = 20;
    address public constant CRYPTOPUNKS_ADDRESS = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;

    // Events
    event TradeCreated(uint256 indexed tradeId, bytes32 indexed tradeHash);
    event AssetDeposited(
        uint256 indexed tradeId, 
        uint256 indexed assetIndex,
        address depositor
    );
    event TradeCompleted(uint256 indexed tradeId);
    event TradeCancelled(uint256 indexed tradeId, address indexed canceller);

    // Custom errors
    error InvalidParticipantCount();
    error MaxAssetsExceeded();
    error TradeNotActive();
    error NotParticipant();
    error AssetNotFound();
    error UnsupportedAssetType();
    error InvalidAsset();
    error ArrayLengthMismatch();
    error BatchSizeExceeded();

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Creates a new trade with specified participants and assets
     * @param participants Array of addresses that can participate in the trade
     * @param assets Array of assets to be traded
     * @return tradeId Unique identifier for the created trade
     */
    function createTrade(
        address[] calldata participants,
        Asset[] calldata assets
    ) external returns (uint256 tradeId) {
        if (participants.length < 2 || participants.length > MAX_PARTICIPANTS) {
            revert InvalidParticipantCount();
        }
        if (assets.length > participants.length * MAX_ASSETS_PER_PARTICIPANT) {
            revert MaxAssetsExceeded();
        }

        tradeId = uint256(keccak256(abi.encode(block.timestamp, msg.sender, assets)));
        Trade storage trade = trades[tradeId];
        require(!trade.isActive, "Trade ID collision");

        trade.isActive = true;
        trade.totalAssetCount = assets.length;

        for (uint i = 0; i < assets.length; i++) {
            trade.assets.push(assets[i]);
            bytes32 assetHash = keccak256(abi.encode(
                assets[i].token,
                assets[i].tokenId,
                assets[i].amount,
                assets[i].assetType
            ));
            validAssets[tradeId][assetHash] = true;
        }

        for (uint i = 0; i < participants.length; i++) {
            isParticipant[tradeId][participants[i]] = true;
        }

        emit TradeCreated(tradeId, keccak256(abi.encode(assets)));
        return tradeId;
    }

    /**
     * @notice Deposits a single asset into an active trade
     * @param tradeId ID of the trade
     * @param token Address of the token contract
     * @param tokenId ID of the token (for ERC721, ERC1155, and CryptoPunks)
     * @param amount Amount of tokens (for ERC20 and ERC1155)
     * @param assetType Type of the asset
     */
    function depositAsset(
        uint256 tradeId,
        address token,
        uint256 tokenId,
        uint256 amount,
        AssetType assetType
    ) external nonReentrant {
        Trade storage trade = trades[tradeId];
        if (!trade.isActive) revert TradeNotActive();

        bytes32 assetHash = keccak256(abi.encode(token, tokenId, amount, assetType));
        if (!validAssets[tradeId][assetHash]) revert InvalidAsset();

        bool assetFound = false;
        for (uint i = 0; i < trade.assets.length; i++) {
            Asset storage asset = trade.assets[i];
            if (!asset.isDeposited &&
                asset.token == token &&
                asset.tokenId == tokenId &&
                asset.amount == amount &&
                AssetType(asset.assetType) == assetType) {
                
                _transferAsset(asset, msg.sender, address(this));
                asset.isDeposited = true;
                asset.depositor = msg.sender;
                trade.depositedAssetCount++;
                assetFound = true;
                emit AssetDeposited(tradeId, i, msg.sender);
                break;
            }
        }

        if (!assetFound) revert AssetNotFound();

        if (trade.depositedAssetCount == trade.totalAssetCount) {
            _executeTrade(tradeId);
        }
    }

    /**
     * @notice Deposits multiple assets into an active trade in a single transaction
     * @param tradeId ID of the trade
     * @param tokens Array of token addresses
     * @param tokenIds Array of token IDs
     * @param amounts Array of token amounts
     * @param assetTypes Array of asset types
     */
    function batchDepositAssets(
        uint256 tradeId,
        address[] calldata tokens,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        AssetType[] calldata assetTypes
    ) external nonReentrant {
        if (tokens.length != tokenIds.length || 
            tokens.length != amounts.length || 
            tokens.length != assetTypes.length) {
            revert ArrayLengthMismatch();
        }
        if (tokens.length > MAX_BATCH_DEPOSITS) {
            revert BatchSizeExceeded();
        }

        Trade storage trade = trades[tradeId];
        if (!trade.isActive) revert TradeNotActive();

        for (uint i = 0; i < tokens.length; i++) {
            bytes32 assetHash = keccak256(abi.encode(
                tokens[i],
                tokenIds[i],
                amounts[i],
                assetTypes[i]
            ));
            
            if (!validAssets[tradeId][assetHash]) revert InvalidAsset();

            for (uint j = 0; j < trade.assets.length; j++) {
                Asset storage asset = trade.assets[j];
                if (!asset.isDeposited &&
                    asset.token == tokens[i] &&
                    asset.tokenId == tokenIds[i] &&
                    asset.amount == amounts[i] &&
                    AssetType(asset.assetType) == assetTypes[i]) {
                    
                    _transferAsset(asset, msg.sender, address(this));
                    asset.isDeposited = true;
                    asset.depositor = msg.sender;
                    trade.depositedAssetCount++;
                    
                    emit AssetDeposited(tradeId, j, msg.sender);
                    break;
                }
            }
        }

        if (trade.depositedAssetCount == trade.totalAssetCount) {
            _executeTrade(tradeId);
        }
    }

    /**
     * @notice Cancels an active trade and returns deposited assets to their depositors
     * @param tradeId ID of the trade to cancel
     */
    function cancelTrade(uint256 tradeId) external nonReentrant {
        Trade storage trade = trades[tradeId];
        if (!trade.isActive) revert TradeNotActive();
        if (!isParticipant[tradeId][msg.sender]) revert NotParticipant();

        trade.isActive = false;

        for (uint i = 0; i < trade.assets.length; i++) {
            Asset storage asset = trade.assets[i];
            if (asset.isDeposited) {
                _transferAsset(asset, address(this), asset.depositor);
                asset.isDeposited = false;
            }
        }

        emit TradeCancelled(tradeId, msg.sender);
    }

    /**
     * @notice Internal function to execute a trade once all assets are deposited
     * @param tradeId ID of the trade to execute
     */
    function _executeTrade(uint256 tradeId) internal {
        Trade storage trade = trades[tradeId];
        trade.isActive = false;

        for (uint i = 0; i < trade.assets.length; i++) {
            Asset storage asset = trade.assets[i];
            if (asset.isDeposited) {
                _transferAsset(asset, address(this), asset.recipient);
            }
        }

        emit TradeCompleted(tradeId);
    }

    /**
     * @notice Internal function to handle asset transfers based on asset type
     * @param asset The asset to transfer
     * @param from Address to transfer from
     * @param to Address to transfer to
     */
    function _transferAsset(
        Asset memory asset,
        address from,
        address to
    ) internal {
        if (asset.assetType == AssetType.ERC20) {
            IERC20(asset.token).transferFrom(from, to, asset.amount);
        } else if (asset.assetType == AssetType.ERC721) {
            IERC721(asset.token).safeTransferFrom(from, to, asset.tokenId);
        } else if (asset.assetType == AssetType.ERC1155) {
            IERC1155(asset.token).safeTransferFrom(from, to, asset.tokenId, asset.amount, "");
        } else if (asset.assetType == AssetType.CryptoPunk) {
            if (from == address(this)) {
                // Cancel or execute trade to transfer punk
                ICryptoPunks(CRYPTOPUNKS_ADDRESS).transferPunk(to, asset.tokenId);
            } else {
                // Verify ownership before depositing to trade
                address punkOwner = ICryptoPunks(CRYPTOPUNKS_ADDRESS).punkIndexToAddress(asset.tokenId);
                require(from == punkOwner, "Sender must be punk owner");

                // Verify the punk is properly offered to the contract
                (
                    bool isForSale,
                    ,
                    address seller,
                    uint256 minValue,
                    address onlySellTo
                ) = ICryptoPunks(CRYPTOPUNKS_ADDRESS).punksOfferedForSale(asset.tokenId);

                require(isForSale, "Punk not offered for sale");
                require(seller == from, "Seller mismatch");
                require(onlySellTo == address(this), "Punk not offered to escrow");
                require(minValue == 0, "Punk price must be 0");

                // Buy the punk to transfer it to the contract
                ICryptoPunks(CRYPTOPUNKS_ADDRESS).buyPunk(asset.tokenId);
            }
        } else {
            revert UnsupportedAssetType();
        }
    }

    /**
     * @notice Checks if an asset is valid for a given trade
     * @param tradeId ID of the trade to check
     * @param token Address of the token contract
     * @param tokenId ID of the token (for ERC721, ERC1155, and CryptoPunks)
     * @param amount Amount of tokens (for ERC20 and ERC1155)
     * @param assetType Type of the asset
     * @return bool True if the asset is valid for the trade, false otherwise
     * @dev Uses a hash of the asset parameters to check against the validAssets mapping
     */
    function isValidAsset(
        uint256 tradeId,
        address token,
        uint256 tokenId,
        uint256 amount,
        AssetType assetType
    ) public view returns (bool) {
        return validAssets[tradeId][keccak256(abi.encode(
            token,
            tokenId,
            amount,
            assetType
        ))];
    }

    /**
     * @notice Checks if an asset is valid for a given trade
     * @param tradeId ID of the trade to check
     * @return isActive True if the asset is valid for the trade, false otherwise
     * @return depositedAssetCount Number of assets currently deposited
     * @return totalAssetCount Total number of assets in the trade
     * @return assets Array of assets involved in the trade
     * @dev Uses a hash of the asset parameters to check against the validAssets mapping
     */
    function getTradeInfo(uint256 tradeId) external view returns (
        bool isActive,
        uint256 depositedAssetCount,
        uint256 totalAssetCount,
        Asset[] memory assets
    ) {
        Trade storage trade = trades[tradeId];
        return (
            trade.isActive,
            trade.depositedAssetCount,
            trade.totalAssetCount,
            trade.assets
        );
    }

    /**
     * @notice Retrieves status information for multiple trades in a single call
     * @param tradeIds Array of trade IDs to query
     * @return isActive Array of boolean values indicating if each trade is active
     * @return depositedAssetCount Array of numbers indicating deposited assets for each trade
     * @return totalAssetCount Array of numbers indicating total assets for each trade
     * @return assets 2D array containing all assets for each trade
     * @dev Useful for efficiently querying multiple trades at once
     * @dev Limited to 10 trades per call to prevent excessive gas usage
     */
    function getMultipleTradeStatuses(uint256[] calldata tradeIds) external view returns (
        bool[] memory isActive,
        uint256[] memory depositedAssetCount,
        uint256[] memory totalAssetCount,
        Asset[][] memory assets
    ) {
        if (tradeIds.length > 10) revert BatchSizeExceeded();

        isActive = new bool[](tradeIds.length);
        depositedAssetCount = new uint256[](tradeIds.length);
        totalAssetCount = new uint256[](tradeIds.length);
        assets = new Asset[][](tradeIds.length);

        for (uint256 i = 0; i < tradeIds.length; i++) {
            Trade storage trade = trades[tradeIds[i]];
            isActive[i] = trade.isActive;
            depositedAssetCount[i] = trade.depositedAssetCount;
            totalAssetCount[i] = trade.totalAssetCount;
            assets[i] = trade.assets;
        }

        return (isActive, depositedAssetCount, totalAssetCount, assets);
    }
}