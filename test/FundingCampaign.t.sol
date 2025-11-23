// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title FundingCampaign
 * @notice Main contract untuk crowdfunding campaign
 * @dev Handle deposit, withdraw, profit distribution
 */
contract FundingCampaign is ReentrancyGuard, Ownable, Pausable {
    
    // ═══════════════════════════════════════════════════════
    // ENUMS & STRUCTS
    // ═══════════════════════════════════════════════════════
    
    enum CampaignState {
        FUNDING,    // Crowdfunding active
        FUNDED,     // Target reached, waiting activation
        ACTIVE,     // Execution ongoing
        COMPLETED,  // Profit distributed, can claim
        FAILED      // Funding failed, can refund
    }
    
    enum CommodityType {
        COFFEE, RICE, CORN, COCOA, PALM_OIL, RUBBER, TEA, VANILLA, OTHER
    }
    
    struct FarmerDetail {
        bool exists;
        uint256 allocatedWeight;  // kg
        uint256 actualWeight;     // kg (filled after harvest)
    }
    
    // ═══════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════
    
    // Campaign Info
    bytes32 public campaignId;
    bytes32 public buyerId;
    address public collector;
    CommodityType public commodity;
    
    // Farmers
    bytes32[] public farmerIds;
    mapping(bytes32 => FarmerDetail) public farmerDetails;
    
    // Financial
    uint256 public totalProjectValue;        // Info only (1 miliar)
    uint256 public stomatradeContribution;   // Info only (800 juta)
    uint256 public crowdfundingTarget;       // Actual target (200 juta)
    uint256 public totalRaised;              // Current raised
    uint256 public estimatedWeight;          // Total kg
    uint256 public profitPerKg;              // USDT per kg
    uint256 public lenderShareBPS;           // Basis points (8000 = 80%)
    uint256 public stomatradeShareBPS;       // Basis points (2000 = 20%)
    
    // Timing
    uint256 public fundingDeadline;
    uint256 public createdAt;
    
    // State
    CampaignState public state;
    
    // Lenders
    mapping(address => uint256) public contributions;
    address[] public lenders;
    mapping(address => bool) public isLender;
    mapping(address => bool) public hasWithdrawn;
    mapping(address => bool) public hasRefunded;
    
    // Results
    uint256 public actualProfit;
    
    // Token
    IERC20 public immutable USDT;
    
    // Constants
    uint256 public constant BPS_DENOMINATOR = 10000;
    
    // ═══════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════
    
    event CampaignCreated(
        bytes32 indexed campaignId,
        bytes32[] farmerIds,
        bytes32 indexed buyerId,
        uint256 crowdfundingTarget,
        uint256 timestamp
    );
    
    event Deposited(
        address indexed lender,
        uint256 amount,
        uint256 totalRaised,
        uint256 timestamp
    );
    
    event CampaignFunded(
        uint256 totalRaised,
        uint256 lenderCount,
        uint256 timestamp
    );
    
    event FundsWithdrawn(
        address indexed admin,
        uint256 amount,
        uint256 timestamp
    );
    
    event CampaignActivated(uint256 timestamp);
    
    event FarmersAdded(
        bytes32[] farmerIds,
        uint256[] allocatedWeights,
        uint256 timestamp
    );
    
    event FarmerWeightUpdated(
        bytes32 indexed farmerId,
        uint256 actualWeight,
        uint256 timestamp
    );
    
    event ReturnsDeposited(
        uint256 principal,
        uint256 lendersProfitShare,
        uint256 totalDeposited,
        uint256 actualProfit,
        uint256 timestamp
    );
    
    event ReturnsClaimed(
        address indexed lender,
        uint256 principal,
        uint256 profit,
        uint256 total,
        uint256 timestamp
    );
    
    event CampaignFailed(uint256 timestamp);
    
    event RefundClaimed(
        address indexed lender,
        uint256 amount,
        uint256 timestamp
    );
    
    // ═══════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════
    
    constructor(
        address _usdtToken,
        bytes32 _campaignId,
        bytes32[] memory _farmerIds,
        uint256[] memory _allocatedWeights,
        bytes32 _buyerId,
        address _collector,
        CommodityType _commodity,
        uint256 _totalProjectValue,
        uint256 _stomatradeContribution,
        uint256 _crowdfundingTarget,
        uint256 _profitPerKg,
        uint256 _lenderShareBPS,
        uint256 _fundingDuration
    ) Ownable(msg.sender) {
        require(_usdtToken != address(0), "Invalid USDT address");
        require(_farmerIds.length > 0, "Need farmers");
        require(_farmerIds.length == _allocatedWeights.length, "Length mismatch");
        require(_buyerId != bytes32(0), "Invalid buyer");
        require(_collector != address(0), "Invalid collector");
        require(_crowdfundingTarget > 0, "Invalid target");
        require(_lenderShareBPS + (_lenderShareBPS == 10000 ? 0 : (10000 - _lenderShareBPS)) == BPS_DENOMINATOR, "Invalid BPS");
        
        USDT = IERC20(_usdtToken);
        campaignId = _campaignId;
        buyerId = _buyerId;
        collector = _collector;
        commodity = _commodity;
        totalProjectValue = _totalProjectValue;
        stomatradeContribution = _stomatradeContribution;
        crowdfundingTarget = _crowdfundingTarget;
        profitPerKg = _profitPerKg;
        lenderShareBPS = _lenderShareBPS;
        stomatradeShareBPS = BPS_DENOMINATOR - _lenderShareBPS;
        fundingDeadline = block.timestamp + _fundingDuration;
        createdAt = block.timestamp;
        state = CampaignState.FUNDING;
        
        // Add farmers
        uint256 totalWeight = 0;
        for(uint i = 0; i < _farmerIds.length; i++) {
            bytes32 farmerId = _farmerIds[i];
            uint256 weight = _allocatedWeights[i];
            
            require(!farmerDetails[farmerId].exists, "Duplicate farmer");
            require(weight > 0, "Weight must > 0");
            
            farmerIds.push(farmerId);
            farmerDetails[farmerId] = FarmerDetail({
                exists: true,
                allocatedWeight: weight,
                actualWeight: 0
            });
            
            totalWeight += weight;
        }
        
        estimatedWeight = totalWeight;
        
        emit CampaignCreated(
            _campaignId,
            _farmerIds,
            _buyerId,
            _crowdfundingTarget,
            block.timestamp
        );
        
        emit FarmersAdded(_farmerIds, _allocatedWeights, block.timestamp);
    }
    
    // ═══════════════════════════════════════════════════════
    // EXTERNAL FUNCTIONS - CROWDFUNDING
    // ═══════════════════════════════════════════════════════
    
    /**
     * @notice Investor deposit USDT (FCFS)
     * @param amount Amount USDT (dengan 6 decimals)
     */
    function deposit(uint256 amount) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        require(state == CampaignState.FUNDING, "Not in funding state");
        require(block.timestamp <= fundingDeadline, "Funding ended");
        require(amount > 0, "Amount must > 0");
        require(totalRaised + amount <= crowdfundingTarget, "Exceeds target");
        
        // Transfer USDT dari investor ke contract
        require(
            USDT.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        
        // Update contribution
        if (!isLender[msg.sender]) {
            lenders.push(msg.sender);
            isLender[msg.sender] = true;
        }
        
        contributions[msg.sender] += amount;
        totalRaised += amount;
        
        emit Deposited(msg.sender, amount, totalRaised, block.timestamp);
        
        // Check if target reached
        if (totalRaised >= crowdfundingTarget) {
            state = CampaignState.FUNDED;
            emit CampaignFunded(totalRaised, lenders.length, block.timestamp);
        }
    }
    
    /**
     * @notice Check and fail campaign jika deadline passed
     */
    function checkAndFailCampaign() external {
        require(state == CampaignState.FUNDING, "Not in funding state");
        require(block.timestamp > fundingDeadline, "Deadline not passed");
        require(totalRaised < crowdfundingTarget, "Target reached");
        
        state = CampaignState.FAILED;
        
        emit CampaignFailed(block.timestamp);
    }
    
    /**
     * @notice Investor claim refund jika campaign failed
     */
    function claimRefund() 
        external 
        nonReentrant 
    {
        require(state == CampaignState.FAILED, "Campaign not failed");
        require(contributions[msg.sender] > 0, "No contribution");
        require(!hasRefunded[msg.sender], "Already refunded");
        
        uint256 amount = contributions[msg.sender];
        hasRefunded[msg.sender] = true;
        
        require(USDT.transfer(msg.sender, amount), "Transfer failed");
        
        emit RefundClaimed(msg.sender, amount, block.timestamp);
    }
    
    // ═══════════════════════════════════════════════════════
    // EXTERNAL FUNCTIONS - ADMIN
    // ═══════════════════════════════════════════════════════
    
    /**
     * @notice Admin withdraw crowdfunding setelah FUNDED
     */
    function withdrawFunds() 
        external 
        onlyOwner 
        nonReentrant 
    {
        require(state == CampaignState.FUNDED, "Not funded");
        
        uint256 amount = totalRaised;
        state = CampaignState.ACTIVE;
        
        require(USDT.transfer(msg.sender, amount), "Transfer failed");
        
        emit FundsWithdrawn(msg.sender, amount, block.timestamp);
        emit CampaignActivated(block.timestamp);
    }
    
    /**
     * @notice Admin add farmers (during FUNDING)
     */
    function addFarmers(
        bytes32[] calldata _newFarmerIds,
        uint256[] calldata _allocatedWeights
    ) 
        external 
        onlyOwner 
        whenNotPaused 
    {
        require(state == CampaignState.FUNDING, "Wrong state");
        require(_newFarmerIds.length > 0, "Empty array");
        require(_newFarmerIds.length == _allocatedWeights.length, "Length mismatch");
        
        for(uint i = 0; i < _newFarmerIds.length; i++) {
            bytes32 farmerId = _newFarmerIds[i];
            uint256 weight = _allocatedWeights[i];
            
            require(!farmerDetails[farmerId].exists, "Already exists");
            require(weight > 0, "Weight must > 0");
            
            farmerIds.push(farmerId);
            farmerDetails[farmerId] = FarmerDetail({
                exists: true,
                allocatedWeight: weight,
                actualWeight: 0
            });
            
            estimatedWeight += weight;
        }
        
        emit FarmersAdded(_newFarmerIds, _allocatedWeights, block.timestamp);
    }
    
    /**
     * @notice Admin update actual weight after harvest
     */
    function updateFarmerActualWeight(
        bytes32 farmerId,
        uint256 actualWeight
    ) 
        external 
        onlyOwner 
    {
        require(state == CampaignState.ACTIVE, "Wrong state");
        require(farmerDetails[farmerId].exists, "Farmer not in campaign");
        
        farmerDetails[farmerId].actualWeight = actualWeight;
        
        emit FarmerWeightUpdated(farmerId, actualWeight, block.timestamp);
    }
    
    /**
     * @notice Admin deposit returns (principal + profit)
     * @param _actualProfit Total profit dalam USDT
     */
    function depositReturns(uint256 _actualProfit) 
        external 
        onlyOwner 
        nonReentrant 
    {
        require(state == CampaignState.ACTIVE, "Wrong state");
        require(_actualProfit > 0, "Profit must > 0");
        
        actualProfit = _actualProfit;
        
        // Calculate lenders profit share
        uint256 lendersProfitShare = (_actualProfit * lenderShareBPS) / BPS_DENOMINATOR;
        
        // Total to deposit = principal + profit for lenders
        uint256 totalToDeposit = crowdfundingTarget + lendersProfitShare;
        
        // Transfer from admin to contract
        require(
            USDT.transferFrom(msg.sender, address(this), totalToDeposit),
            "Transfer failed"
        );
        
        state = CampaignState.COMPLETED;
        
        emit ReturnsDeposited(
            crowdfundingTarget,
            lendersProfitShare,
            totalToDeposit,
            _actualProfit,
            block.timestamp
        );
    }
    
    // ═══════════════════════════════════════════════════════
    // EXTERNAL FUNCTIONS - INVESTOR CLAIM
    // ═══════════════════════════════════════════════════════
    
        /**
         * @notice Investor claim returns (principal + profit)
         */
        function claimReturns() 
            external 
            nonReentrant 
        {
            require(state == CampaignState.COMPLETED, "Wrong state");
            require(contributions[msg.sender] > 0, "No contribution");
            require(!hasWithdrawn[msg.sender], "Already withdrawn");
            
            uint256 principal = contributions[msg.sender];
    
            // total profit allocated to lenders
            uint256 lendersProfitShare = (actualProfit * lenderShareBPS) / BPS_DENOMINATOR;
    
            // profit per lender proportional to their contribution
            uint256 profit = 0;
            if (crowdfundingTarget > 0) {
                profit = (lendersProfitShare * principal) / crowdfundingTarget;
            }
    
            uint256 total = principal + profit;
            hasWithdrawn[msg.sender] = true;
    
            require(USDT.transfer(msg.sender, total), "Transfer failed");
    
            emit ReturnsClaimed(msg.sender, principal, profit, total, block.timestamp);
        }
    }