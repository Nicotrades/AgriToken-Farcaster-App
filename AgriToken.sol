// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";  // ✅ FIX: Nouveau chemin
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title AgriToken - Fractional Agricultural Investment
 * @notice ERC1155 NFT for investing in Normandy farms
 * @dev Each token ID = 1 asset type, quantity = number of parts owned
 */
contract AgriToken is ERC1155, Ownable, Pausable, ReentrancyGuard {
    using Strings for uint256;

    struct Asset {
        string name;                 // "Apple Orchard Share"
        uint256 pricePerPartWei;    // Price in wei (e.g., 0.001 ETH = 1000000000000000)
        uint256 maxParts;           // Total parts available
        uint256 soldParts;          // Parts sold so far
        bool active;                // Can be bought
    }

    mapping(uint256 => Asset) public assets;
    uint256 public assetCount;
    string private _baseMetadataURI;

    event AssetRegistered(
        uint256 indexed assetId, 
        string name,
        uint256 pricePerPartWei, 
        uint256 maxParts
    );
    
    event AssetBought(
        address indexed buyer, 
        uint256 indexed assetId, 
        uint256 numParts, 
        uint256 totalPaid
    );
    
    event FundsWithdrawn(address indexed to, uint256 amount);

    constructor(string memory baseURI_) 
        ERC1155("") 
        Ownable(msg.sender) 
    {
        _baseMetadataURI = baseURI_;
    }

    // ════════════════════════════════════════
    // 👑 ADMIN FUNCTIONS
    // ════════════════════════════════════════

    /**
     * @notice Register a new agricultural asset
     * @param name Asset name (e.g., "Apple Orchard Share")
     * @param pricePerPartWei Price per part in wei
     * @param maxParts Total number of parts available
     */
    function registerAsset(
        string memory name,
        uint256 pricePerPartWei, 
        uint256 maxParts
    ) external onlyOwner {
        require(pricePerPartWei > 0, "Invalid price");
        require(maxParts > 0, "Invalid max parts");

        assetCount++;
        assets[assetCount] = Asset({
            name: name,
            pricePerPartWei: pricePerPartWei,
            maxParts: maxParts,
            soldParts: 0,
            active: true
        });

        emit AssetRegistered(assetCount, name, pricePerPartWei, maxParts);
    }

    /**
     * @notice Update asset price
     */
    function updatePrice(uint256 assetId, uint256 newPriceWei) 
        external 
        onlyOwner 
    {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset");
        assets[assetId].pricePerPartWei = newPriceWei;
    }

    /**
     * @notice Deactivate asset (stop sales)
     */
    function deactivateAsset(uint256 assetId) external onlyOwner {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset");
        assets[assetId].active = false;
    }

    /**
     * @notice Set base URI for metadata
     */
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _baseMetadataURI = newBaseURI;
    }

    /**
     * @notice Pause all transactions
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause transactions
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Withdraw contract funds
     */
    function withdrawFunds(address payable to) 
        external 
        onlyOwner 
        nonReentrant 
    {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        
        (bool success, ) = to.call{value: balance}("");
        require(success, "Transfer failed");
        
        emit FundsWithdrawn(to, balance);
    }

    // ════════════════════════════════════════
    // 🛒 PUBLIC FUNCTION
    // ════════════════════════════════════════

    /**
     * @notice Buy parts and receive ERC1155 tokens
     * @param assetId Asset to invest in (1, 2, 3...)
     * @param numParts Number of parts to buy
     */
    function buyAndMint(uint256 assetId, uint256 numParts) 
        external 
        payable 
        whenNotPaused 
        nonReentrant 
    {
        Asset storage asset = assets[assetId];
        
        require(assetId > 0 && assetId <= assetCount, "Invalid asset ID");
        require(asset.active, "Asset not active");
        require(numParts > 0, "Must buy at least 1 part");
        require(numParts <= 100, "Max 100 parts per tx");
        require(
            asset.soldParts + numParts <= asset.maxParts, 
            "Exceeds max parts"
        );

        uint256 totalCost = asset.pricePerPartWei * numParts;
        require(msg.value >= totalCost, "Insufficient payment");

        // Update sold count
        asset.soldParts += numParts;

        // Mint ERC1155 tokens (assetId = token ID, numParts = quantity)
        _mint(msg.sender, assetId, numParts, "");

        emit AssetBought(msg.sender, assetId, numParts, msg.value);

        // Refund excess payment
        if (msg.value > totalCost) {
            uint256 refund = msg.value - totalCost;
            (bool success, ) = payable(msg.sender).call{value: refund}("");
            require(success, "Refund failed");
        }
    }

    // ════════════════════════════════════════
    // 👀 VIEW FUNCTIONS
    // ════════════════════════════════════════

    /**
     * @notice Get asset details
     */
    function getAsset(uint256 assetId) 
        external 
        view 
        returns (Asset memory) 
    {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset");
        return assets[assetId];
    }

    /**
     * @notice Get remaining parts for an asset
     */
    function getRemainingParts(uint256 assetId) 
        external 
        view 
        returns (uint256) 
    {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset");
        return assets[assetId].maxParts - assets[assetId].soldParts;
    }

    /**
     * @notice Get user's balance for a specific asset
     */
    function getUserBalance(address user, uint256 assetId) 
        external 
        view 
        returns (uint256) 
    {
        return balanceOf(user, assetId);
    }

    /**
     * @notice Override URI to return metadata from IPFS
     */
    function uri(uint256 tokenId) 
        public 
        view 
        override 
        returns (string memory) 
    {
        require(tokenId > 0 && tokenId <= assetCount, "Invalid token ID");
        
        return bytes(_baseMetadataURI).length > 0
            ? string(abi.encodePacked(_baseMetadataURI, tokenId.toString(), ".json"))
            : super.uri(tokenId);
    }

    // Accept ETH payments
    receive() external payable {}
    fallback() external payable {}
}
