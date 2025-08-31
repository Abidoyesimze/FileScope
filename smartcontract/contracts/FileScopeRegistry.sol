// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FileScopeRegistry is ReentrancyGuard, Ownable {
    struct Dataset {
        string datasetCID;
        string analysisCID;
        address uploader;
        bool isPublic;
        uint256 timestamp;
        uint256 views;
        uint256 downloads;
        uint256 citations;
    }

    mapping(string => bool) private cidExists; // Prevent duplicate datasets
    mapping(uint256 => Dataset) private datasets;
    mapping(address => uint256[]) private userUploads;
    uint256 private datasetCount;

    event DatasetUploaded(
        uint256 indexed datasetId,
        address indexed uploader,
        string datasetCID,
        string analysisCID,
        bool isPublic
    );

    event DatasetViewed(uint256 indexed datasetId);
    event DatasetDownloaded(uint256 indexed datasetId);
    event DatasetCited(uint256 indexed datasetId);
    event VisibilityChanged(uint256 indexed datasetId, bool newVisibility);
    event AnalysisUpdated(uint256 indexed datasetId, string newAnalysisCID);

    modifier onlyUploader(uint256 datasetId) {
        require(datasets[datasetId].uploader == msg.sender, "Not the uploader");
        _;
    }

    function uploadDataset(
        string memory _datasetCID,
        string memory _analysisCID,
        bool _isPublic
    ) external nonReentrant {
        require(!cidExists[_datasetCID], "Dataset already registered");
        require(bytes(_datasetCID).length > 0, "CID required");

        cidExists[_datasetCID] = true;

        datasets[datasetCount] = Dataset({
            datasetCID: _datasetCID,
            analysisCID: _analysisCID,
            uploader: msg.sender,
            isPublic: _isPublic,
            timestamp: block.timestamp,
            views: 0,
            downloads: 0,
            citations: 0
        });

        userUploads[msg.sender].push(datasetCount);

        emit DatasetUploaded(datasetCount, msg.sender, _datasetCID, _analysisCID, _isPublic);
        datasetCount++;
    }

    function getDataset(uint256 datasetId) external view returns (Dataset memory) {
        Dataset memory d = datasets[datasetId];
        require(d.isPublic || d.uploader == msg.sender, "Private dataset");
        return d;
    }

    function updateAnalysis(uint256 datasetId, string memory newAnalysisCID)
        external
        onlyUploader(datasetId)
    {
        datasets[datasetId].analysisCID = newAnalysisCID;
        emit AnalysisUpdated(datasetId, newAnalysisCID);
    }

    function changeVisibility(uint256 datasetId, bool newVisibility)
        external
        onlyUploader(datasetId)
    {
        datasets[datasetId].isPublic = newVisibility;
        emit VisibilityChanged(datasetId, newVisibility);
    }

    function incrementViews(uint256 datasetId) external {
        Dataset storage d = datasets[datasetId];
        if (d.isPublic || d.uploader == msg.sender) {
            d.views++;
            emit DatasetViewed(datasetId);
        }
    }

    function incrementDownloads(uint256 datasetId) external {
        Dataset storage d = datasets[datasetId];
        if (d.isPublic || d.uploader == msg.sender) {
            d.downloads++;
            emit DatasetDownloaded(datasetId);
        }
    }

    function incrementCitations(uint256 datasetId) external {
        Dataset storage d = datasets[datasetId];
        if (d.isPublic || d.uploader == msg.sender) {
            d.citations++;
            emit DatasetCited(datasetId);
        }
    }

    function getAllPublicDatasets() external view returns (Dataset[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < datasetCount; i++) {
            if (datasets[i].isPublic) {
                count++;
            }
        }

        Dataset[] memory publicDatasets = new Dataset[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < datasetCount; i++) {
            if (datasets[i].isPublic) {
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

    function totalDatasets() external view returns (uint256) {
        return datasetCount;
    }
}
