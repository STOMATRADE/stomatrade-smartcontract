// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FarmerRegistry
 * @notice Registry untuk menyimpan data petani on-chain
 * @dev Data immutable setelah registered, hanya admin yang bisa register
 */
contract FarmerRegistry is Ownable {
    
    // ═══════════════════════════════════════════════════════
    // ENUMS & STRUCTS
    // ═══════════════════════════════════════════════════════
    
    enum CommodityType {
        COFFEE,
        RICE,
        CORN,
        COCOA,
        PALM_OIL,
        RUBBER,
        TEA,
        VANILLA,
        OTHER
    }
    
    struct Farmer {
        bytes32 farmerId;           // Hashed ID (privacy)
        string ipfsHash;            // IPFS link untuk metadata lengkap
        uint256 landArea;           // Luas lahan dalam m²
        CommodityType commodity;    // Jenis komoditas
        string location;            // Lokasi (Desa, Kecamatan, Kabupaten)
        uint256 registeredAt;       // Timestamp registration
        bool isActive;              // Status aktif
    }
    
    // ═══════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════
    
    mapping(bytes32 => Farmer) public farmers;
    bytes32[] public farmerIds;
    uint256 public farmerCount;
    
    // ═══════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════
    
    event FarmerRegistered(
        bytes32 indexed farmerId,
        string ipfsHash,
        uint256 landArea,
        CommodityType commodity,
        string location,
        uint256 timestamp
    );
    
    event FarmerDeactivated(
        bytes32 indexed farmerId,
        uint256 timestamp
    );
    
    event FarmerReactivated(
        bytes32 indexed farmerId,
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
     * @notice Register farmer baru
     * @param _farmerId Unique farmer ID (hashed)
     * @param _ipfsHash IPFS hash untuk metadata
     * @param _landArea Luas lahan dalam m²
     * @param _commodity Jenis komoditas
     * @param _location Lokasi petani
     */
    function registerFarmer(
        bytes32 _farmerId,
        string calldata _ipfsHash,
        uint256 _landArea,
        CommodityType _commodity,
        string calldata _location
    ) external onlyOwner {
        require(_farmerId != bytes32(0), "Invalid farmer ID");
        require(!farmers[_farmerId].isActive, "Farmer already registered");
        require(_landArea > 0, "Land area must be > 0");
        require(bytes(_ipfsHash).length > 0, "IPFS hash required");
        require(bytes(_location).length > 0, "Location required");
        
        farmers[_farmerId] = Farmer({
            farmerId: _farmerId,
            ipfsHash: _ipfsHash,
            landArea: _landArea,
            commodity: _commodity,
            location: _location,
            registeredAt: block.timestamp,
            isActive: true
        });
        
        farmerIds.push(_farmerId);
        farmerCount++;
        
        emit FarmerRegistered(
            _farmerId,
            _ipfsHash,
            _landArea,
            _commodity,
            _location,
            block.timestamp
        );
    }
    
    /**
     * @notice Deactivate farmer
     * @param _farmerId Farmer ID to deactivate
     */
    function deactivateFarmer(bytes32 _farmerId) external onlyOwner {
        require(farmers[_farmerId].isActive, "Farmer not active");
        
        farmers[_farmerId].isActive = false;
        
        emit FarmerDeactivated(_farmerId, block.timestamp);
    }
    
    /**
     * @notice Reactivate farmer
     * @param _farmerId Farmer ID to reactivate
     */
    function reactivateFarmer(bytes32 _farmerId) external onlyOwner {
        require(farmers[_farmerId].registeredAt > 0, "Farmer not registered");
        require(!farmers[_farmerId].isActive, "Farmer already active");
        
        farmers[_farmerId].isActive = true;
        
        emit FarmerReactivated(_farmerId, block.timestamp);
    }
    
    // ═══════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════
    
    /**
     * @notice Get farmer detail
     * @param _farmerId Farmer ID
     */
    function getFarmer(bytes32 _farmerId) 
        external 
        view 
        returns (Farmer memory) 
    {
        return farmers[_farmerId];
    }
    
    /**
     * @notice Check if farmer is active
     * @param _farmerId Farmer ID
     */
    function isFarmerActive(bytes32 _farmerId) 
        external 
        view 
        returns (bool) 
    {
        return farmers[_farmerId].isActive;
    }
    
    /**
     * @notice Get all farmer IDs
     */
    function getAllFarmerIds() 
        external 
        view 
        returns (bytes32[] memory) 
    {
        return farmerIds;
    }
    
    /**
     * @notice Get commodity type as string
     * @param _commodity Commodity enum
     */
    function getCommodityString(CommodityType _commodity) 
        external 
        pure 
        returns (string memory) 
    {
        if (_commodity == CommodityType.COFFEE) return "Coffee";
        if (_commodity == CommodityType.RICE) return "Rice";
        if (_commodity == CommodityType.CORN) return "Corn";
        if (_commodity == CommodityType.COCOA) return "Cocoa";
        if (_commodity == CommodityType.PALM_OIL) return "Palm Oil";
        if (_commodity == CommodityType.RUBBER) return "Rubber";
        if (_commodity == CommodityType.TEA) return "Tea";
        if (_commodity == CommodityType.VANILLA) return "Vanilla";
        return "Other";
    }
}