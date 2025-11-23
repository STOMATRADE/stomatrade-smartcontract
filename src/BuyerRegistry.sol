// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BuyerRegistry
 * @notice Registry untuk menyimpan data buyer on-chain
 * @dev Data buyer untuk transparency & trust
 */
contract BuyerRegistry is Ownable {
    
    // ═══════════════════════════════════════════════════════
    // ENUMS & STRUCTS
    // ═══════════════════════════════════════════════════════
    
    enum BuyerType {
        EXPORTER,
        DOMESTIC,
        PROCESSOR,
        ROASTERY,
        RETAILER,
        OTHER
    }
    
    struct Buyer {
        bytes32 buyerId;            // Hashed ID
        string companyName;         // Nama perusahaan
        string ipfsHash;            // IPFS untuk contracts, licenses
        string location;            // Lokasi warehouse
        BuyerType buyerType;        // Tipe buyer
        uint256 registeredAt;       // Timestamp
        bool isActive;              // Status
    }
    
    // ═══════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════
    
    mapping(bytes32 => Buyer) public buyers;
    bytes32[] public buyerIds;
    uint256 public buyerCount;
    
    // ═══════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════
    
    event BuyerRegistered(
        bytes32 indexed buyerId,
        string companyName,
        string ipfsHash,
        string location,
        BuyerType buyerType,
        uint256 timestamp
    );
    
    event BuyerDeactivated(
        bytes32 indexed buyerId,
        uint256 timestamp
    );
    
    event BuyerReactivated(
        bytes32 indexed buyerId,
        uint256 timestamp
    );
    
    // ═══════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════
    
    constructor() Ownable(msg.sender) {}
    
    // ═══════════════════════════════════════════════════════
    // EXTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════
    
    /**
     * @notice Register buyer baru
     */
    function registerBuyer(
        bytes32 _buyerId,
        string calldata _companyName,
        string calldata _ipfsHash,
        string calldata _location,
        BuyerType _buyerType
    ) external onlyOwner {
        require(_buyerId != bytes32(0), "Invalid buyer ID");
        require(!buyers[_buyerId].isActive, "Buyer already registered");
        require(bytes(_companyName).length > 0, "Company name required");
        require(bytes(_ipfsHash).length > 0, "IPFS hash required");
        require(bytes(_location).length > 0, "Location required");
        
        buyers[_buyerId] = Buyer({
            buyerId: _buyerId,
            companyName: _companyName,
            ipfsHash: _ipfsHash,
            location: _location,
            buyerType: _buyerType,
            registeredAt: block.timestamp,
            isActive: true
        });
        
        buyerIds.push(_buyerId);
        buyerCount++;
        
        emit BuyerRegistered(
            _buyerId,
            _companyName,
            _ipfsHash,
            _location,
            _buyerType,
            block.timestamp
        );
    }
    
    /**
     * @notice Deactivate buyer
     */
    function deactivateBuyer(bytes32 _buyerId) external onlyOwner {
        require(buyers[_buyerId].isActive, "Buyer not active");
        
        buyers[_buyerId].isActive = false;
        
        emit BuyerDeactivated(_buyerId, block.timestamp);
    }
    
    /**
     * @notice Reactivate buyer
     */
    function reactivateBuyer(bytes32 _buyerId) external onlyOwner {
        require(buyers[_buyerId].registeredAt > 0, "Buyer not registered");
        require(!buyers[_buyerId].isActive, "Buyer already active");
        
        buyers[_buyerId].isActive = true;
        
        emit BuyerReactivated(_buyerId, block.timestamp);
    }
    
    // ═══════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════
    
    /**
     * @notice Get buyer detail
     */
    function getBuyer(bytes32 _buyerId) 
        external 
        view 
        returns (Buyer memory) 
    {
        return buyers[_buyerId];
    }
    
    /**
     * @notice Check if buyer is active
     */
    function isBuyerActive(bytes32 _buyerId) 
        external 
        view 
        returns (bool) 
    {
        return buyers[_buyerId].isActive;
    }
    
    /**
     * @notice Get all buyer IDs
     */
    function getAllBuyerIds() 
        external 
        view 
        returns (bytes32[] memory) 
    {
        return buyerIds;
    }
    
    /**
     * @notice Get buyer type as string
     */
    function getBuyerTypeString(BuyerType _buyerType) 
        external 
        pure 
        returns (string memory) 
    {
        if (_buyerType == BuyerType.EXPORTER) return "Exporter";
        if (_buyerType == BuyerType.DOMESTIC) return "Domestic";
        if (_buyerType == BuyerType.PROCESSOR) return "Processor";
        if (_buyerType == BuyerType.ROASTERY) return "Roastery";
        if (_buyerType == BuyerType.RETAILER) return "Retailer";
        return "Other";
    }
}