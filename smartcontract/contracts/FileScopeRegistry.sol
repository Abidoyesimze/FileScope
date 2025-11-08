// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FileScopeRegistry is ReentrancyGuard, Ownable {
    struct Dataset {
        string datasetCID;
        string analysisCID;
        address uploader;
        bool isPublic;
        bool isPrivate;        
        uint256 timestamp;
        uint256 views;
        uint256 downloads;
        bool isPaid;          
        uint256 priceInFIL;   
        uint256 earnings;      
    }

    struct PaymentToken {
        address tokenAddress;
        bool isAccepted;
        string symbol;
    }

    mapping(string => bool) private cidExists;
    mapping(uint256 => Dataset) private datasets;
    mapping(address => uint256[]) private userUploads;
    mapping(uint256 => mapping(address => bool)) private hasAccess; // datasetId => user => hasAccess
    mapping(address => uint256) private publisherEarnings; // Total earnings per publisher in FIL
    
    // Supported payment tokens (FIL only)
    mapping(address => PaymentToken) public paymentTokens;
    address[] public acceptedTokens;

    uint256 private datasetCount;
    uint256 private totalPlatformEarnings; // Total earnings across all publishers

    event DatasetUploaded(
        uint256 indexed datasetId,
        address indexed uploader,
        string datasetCID,
        string analysisCID,
        bool isPublic,
        bool isPrivate,
        bool isPaid,
        uint256 priceInFIL
    );

    event DatasetViewed(uint256 indexed datasetId);
    event DatasetDownloaded(uint256 indexed datasetId, address indexed downloader);
    event DatasetPurchased(
        uint256 indexed datasetId,
        address indexed buyer,
        address indexed publisher,
        uint256 amount,
        address token
    );
    event PaymentTokenUpdated(address indexed tokenAddress, bool isAccepted, string symbol);

    modifier onlyUploader(uint256 datasetId) {
        require(datasets[datasetId].uploader == msg.sender, "Not the uploader");
        _;
    }

    modifier hasDownloadAccess(uint256 datasetId) {
        Dataset memory d = datasets[datasetId];
        require(
            d.uploader == msg.sender || 
            !d.isPaid || 
            hasAccess[datasetId][msg.sender],
            "Purchase required for download access"
        );
        _;
    }

    modifier canViewDataset(uint256 datasetId) {
        Dataset memory d = datasets[datasetId];
        require(
            d.uploader == msg.sender || 
            (!d.isPrivate && d.isPublic),
            "Private dataset - access denied"
        );
        _;
    }

    constructor() Ownable(msg.sender) {}

    // ===== PAYMENT TOKEN MANAGEMENT =====
    
    function addPaymentToken(address tokenAddress, string memory symbol) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token address");
        require(!paymentTokens[tokenAddress].isAccepted, "Token already added");
        
        paymentTokens[tokenAddress] = PaymentToken({
            tokenAddress: tokenAddress,
            isAccepted: true,
            symbol: symbol
        });
        
        acceptedTokens.push(tokenAddress);
        emit PaymentTokenUpdated(tokenAddress, true, symbol);
    }

    function removePaymentToken(address tokenAddress) external onlyOwner {
        require(paymentTokens[tokenAddress].isAccepted, "Token not accepted");
        paymentTokens[tokenAddress].isAccepted = false;
        emit PaymentTokenUpdated(tokenAddress, false, paymentTokens[tokenAddress].symbol);
    }

    function getAcceptedTokens() external view returns (address[] memory) {
        return acceptedTokens;
    }

    // ===== DATASET UPLOAD & MANAGEMENT =====

    function uploadDataset(
        string memory _datasetCID,
        string memory _analysisCID,
        bool _isPublic,
        bool _isPrivate,
        bool _isPaid,
        uint256 _priceInFIL
    ) external nonReentrant {
        require(!cidExists[_datasetCID], "Dataset already registered");
        require(bytes(_datasetCID).length > 0, "CID required");
        
        // Validation: Cannot be both public and private
        require(!(_isPublic && _isPrivate), "Cannot be both public and private");
        
        // If private, cannot be paid (private means only uploader can access)
        if (_isPrivate) {
            require(!_isPaid, "Private datasets cannot be paid");
        }
        
        if (_isPaid) {
            require(_priceInFIL > 0, "Price must be greater than 0");
        }

        cidExists[_datasetCID] = true;

        datasets[datasetCount] = Dataset({
            datasetCID: _datasetCID,
            analysisCID: _analysisCID,
            uploader: msg.sender,
            isPublic: _isPublic,
            isPrivate: _isPrivate,
            timestamp: block.timestamp,
            views: 0,
            downloads: 0,
            isPaid: _isPaid,
            priceInFIL: _priceInFIL,
            earnings: 0
        });

        userUploads[msg.sender].push(datasetCount);

        emit DatasetUploaded(
            datasetCount, 
            msg.sender, 
            _datasetCID, 
            _analysisCID, 
            _isPublic,
            _isPrivate,
            _isPaid,
            _priceInFIL
        );
        datasetCount++;
    }

    // ===== DATASET PURCHASE =====

    function purchaseDataset(
        uint256 datasetId,
        address paymentToken
    ) external nonReentrant {
        Dataset storage d = datasets[datasetId];
        
        require(!d.isPrivate, "Private dataset not for sale");
        require(d.isPublic, "Dataset not public");
        require(d.isPaid, "Dataset is free");
        require(!hasAccess[datasetId][msg.sender], "Already purchased");
        require(d.uploader != msg.sender, "Cannot purchase own dataset");
        require(paymentTokens[paymentToken].isAccepted, "Payment token not accepted");
        require(d.priceInFIL > 0, "Invalid price");
        
        // Transfer FIL payment directly from buyer to publisher (100% to publisher, no middleman)
        IERC20 token = IERC20(paymentToken);
        require(
            token.transferFrom(msg.sender, d.uploader, d.priceInFIL),
            "Payment transfer failed"
        );
        
        // Grant download access
        hasAccess[datasetId][msg.sender] = true;
        
        // Track earnings for analytics
        d.earnings += d.priceInFIL;
        publisherEarnings[d.uploader] += d.priceInFIL;
        totalPlatformEarnings += d.priceInFIL;
        
        emit DatasetPurchased(datasetId, msg.sender, d.uploader, d.priceInFIL, paymentToken);
    }

    function checkAccess(uint256 datasetId, address user) external view returns (bool) {
        Dataset memory d = datasets[datasetId];
        if (d.uploader == user) {
            return true;
        }
        if (d.isPrivate) {
            return false;
        }
        if (!d.isPaid) {
            return true;
        }
        return hasAccess[datasetId][user];
    }

    // ===== VIEW & DOWNLOAD TRACKING =====

    function getDataset(uint256 datasetId) 
        external 
        view 
        canViewDataset(datasetId)
        returns (Dataset memory) 
    {
        return datasets[datasetId];
    }

    function incrementViews(uint256 datasetId) 
        external 
        canViewDataset(datasetId)
    {
        Dataset storage d = datasets[datasetId];
        d.views++;
        emit DatasetViewed(datasetId);
    }

    function incrementDownloads(uint256 datasetId) 
        external 
        hasDownloadAccess(datasetId)
        canViewDataset(datasetId)
    {
        Dataset storage d = datasets[datasetId];
        d.downloads++;
        emit DatasetDownloaded(datasetId, msg.sender);
    }

    // ===== DATASET QUERIES =====

    function getAllPublicDatasets() external view returns (Dataset[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < datasetCount; i++) {
            if (datasets[i].isPublic && !datasets[i].isPrivate) {
                count++;
            }
        }

        Dataset[] memory publicDatasets = new Dataset[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < datasetCount; i++) {
            if (datasets[i].isPublic && !datasets[i].isPrivate) {
                publicDatasets[j] = datasets[i];
                j++;
            }
        }

        return publicDatasets;
    }

    function getMyDatasets() external view returns (Dataset[] memory) {
        uint256[] memory userIds = userUploads[msg.sender];
        Dataset[] memory myDatasets = new Dataset[](userIds.length);
        for (uint256 i = 0; i < userIds.length; i++) {
            myDatasets[i] = datasets[userIds[i]];
        }
        return myDatasets;
    }

    function getMyPrivateDatasets() external view returns (Dataset[] memory) {
        uint256 count = 0;
        uint256[] memory userIds = userUploads[msg.sender];
        
        // Count private datasets
        for (uint256 i = 0; i < userIds.length; i++) {
            if (datasets[userIds[i]].isPrivate) {
                count++;
            }
        }

        // Get private datasets
        Dataset[] memory privateDatasets = new Dataset[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < userIds.length; i++) {
            if (datasets[userIds[i]].isPrivate) {
                privateDatasets[j] = datasets[userIds[i]];
                j++;
            }
        }

        return privateDatasets;
    }

    function getMyPublicDatasets() external view returns (Dataset[] memory) {
        uint256 count = 0;
        uint256[] memory userIds = userUploads[msg.sender];
        
        // Count public datasets
        for (uint256 i = 0; i < userIds.length; i++) {
            if (datasets[userIds[i]].isPublic && !datasets[userIds[i]].isPrivate) {
                count++;
            }
        }

        // Get public datasets
        Dataset[] memory publicDatasets = new Dataset[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < userIds.length; i++) {
            if (datasets[userIds[i]].isPublic && !datasets[userIds[i]].isPrivate) {
                publicDatasets[j] = datasets[userIds[i]];
                j++;
            }
        }

        return publicDatasets;
    }

    function getMyPurchases() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < datasetCount; i++) {
            if (hasAccess[i][msg.sender] && datasets[i].uploader != msg.sender) {
                count++;
            }
        }

        uint256[] memory purchases = new uint256[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < datasetCount; i++) {
            if (hasAccess[i][msg.sender] && datasets[i].uploader != msg.sender) {
                purchases[j] = i;
                j++;
            }
        }

        return purchases;
    }

    // ===== EARNINGS & ANALYTICS =====

    // Get total earnings for a specific publisher (in FIL)
    function getPublisherEarnings(address publisher) external view returns (uint256) {
        return publisherEarnings[publisher];
    }

    // Get earnings for a specific dataset (in FIL)
    function getDatasetEarnings(uint256 datasetId) external view returns (uint256) {
        require(
            datasets[datasetId].uploader == msg.sender || msg.sender == owner(),
            "Not authorized"
        );
        return datasets[datasetId].earnings;
    }

    // Get my total earnings across all my datasets (in FIL)
    function getMyTotalEarnings() external view returns (uint256) {
        return publisherEarnings[msg.sender];
    }

    // Get total earnings across the entire platform (in FIL)
    function getTotalPlatformEarnings() external view returns (uint256) {
        return totalPlatformEarnings;
    }

    // Get detailed earnings breakdown for a publisher
    function getMyEarningsBreakdown() external view returns (
        uint256 totalEarnings,
        uint256 totalSales,
        uint256 totalDatasets,
        uint256 paidDatasets
    ) {
        uint256[] memory userIds = userUploads[msg.sender];
        totalEarnings = publisherEarnings[msg.sender];
        totalDatasets = userIds.length;
        
        for (uint256 i = 0; i < userIds.length; i++) {
            Dataset memory d = datasets[userIds[i]];
            if (d.isPaid) {
                paidDatasets++;
                totalSales += d.downloads; // Downloads represent sales for paid datasets
            }
        }
        
        return (totalEarnings, totalSales, totalDatasets, paidDatasets);
    }

    // ===== STATS & TOTALS =====

    function totalDatasets() external view returns (uint256) {
        return datasetCount;
    }

    function totalPublicDatasets() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < datasetCount; i++) {
            if (datasets[i].isPublic && !datasets[i].isPrivate) {
                count++;
            }
        }
        return count;
    }
}