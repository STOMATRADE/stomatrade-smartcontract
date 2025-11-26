// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Mengganti HandleError.sol dengan Errors.sol
import "./HandleError.sol";
import "./Events.sol";

contract StomaTrade is ERC721URIStorage, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    struct Project {
        uint256 id;
        address projectOwner;
        uint256 valueProject;
        uint256 maxCrowdFunding;
        uint256 totalRaised;
        ProjectStatus status;
    }

    struct Investment {
        uint256 idProject;
        address investor;
        uint256 amount;
    }

    IERC20 public immutable idrx;
    uint256 public nextProjectId = 1;
    uint256 public nextNftId = 1;

    // STATE
    mapping(uint256 => Project) public projects;
    mapping(uint256 => mapping(address => uint256)) public contribution;
    mapping(uint256 => Investment) public investmentsByTokenId;
    mapping(uint256 => uint256) public profitPool;
    mapping(uint256 => mapping(address => uint256)) public claimedProfit;
    mapping(address => bool) public allowedApprovals;

    // State baru untuk UX: Melacak total investasi per user di semua proyek
    mapping(address => uint256) public totalInvestment;
    
    // tokenCid digunakan untuk Project ID (sebelum mint) dan NFT ID (setelah mint)
    mapping(uint256 => string) public tokenCid; 


    // Penggantian fungsi _beforeTokenTransfer untuk menerapkan SBT
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);

        // Cegah transfer (SBT logic), hanya mint dan burn yang boleh
        if (from != address(0) && to != address(0)) {
            revert Errors.TransferNotAllowed();
        }
    }

    // ---------------- MODIFIERS ----------------
    modifier onlyValidProject(uint256 _idProject) {
        // Menggunakan Errors.InvalidProject()
        if (_idProject == 0 || _idProject >= nextProjectId) revert Errors.InvalidProject();
        _;
    }

    modifier onlyApprovedProjectOwner(uint256 _idProject) {
        Project storage p = projects[_idProject];
        // Menggunakan Errors.ApprovalNotAllowed()
        if (!allowedApprovals[p.projectOwner]) revert Errors.ApprovalNotAllowed();
        _;
    }

    // ---------------- CONSTRUCTOR ----------------
    constructor(address idrxTokenAddress)
        ERC721("CrowdFunding Stomatrade", "STP")
        Ownable(msg.sender)
    {
        // Memperbaiki error: seharusnya Errors.ZeroAddress()
        if (idrxTokenAddress == address(0)) revert Errors.ZeroAddress();
        idrx = IERC20(idrxTokenAddress);
    }

    // ---------------- PROJECT MANAGEMENT ----------------
    function createProject(
        uint256 _valueProject,
        uint256 _maxCrowdFunding,
        string memory _cid
    ) external returns (uint256 _idProject) {
        // Menggunakan Errors.ZeroAmount()
        if (_maxCrowdFunding == 0) revert Errors.ZeroAmount();
        
        // Memperbaiki agar projectOwner adalah msg.sender (Collector)
        if (msg.sender == address(0)) revert Errors.ZeroAddress(); 

        _idProject = nextProjectId++;
        projects[_idProject] = Project({
            id: _idProject,
            projectOwner: msg.sender,
            valueProject: _valueProject,
            maxCrowdFunding: _maxCrowdFunding,
            totalRaised: 0,
            status: ProjectStatus.PENDING
        });

        // Simpan CID (metadata project)
        tokenCid[_idProject] = _cid;

        emit ProjectCreated(_idProject, msg.sender, _valueProject, _maxCrowdFunding);
    }

    function approveProject(uint256 _idProject)
        external
        onlyOwner
        onlyValidProject(_idProject)
    {
        Project storage p = projects[_idProject];
        // Menggunakan Errors.InvalidState()
        if (p.status != ProjectStatus.PENDING) revert Errors.InvalidState();

        allowedApprovals[p.projectOwner] = true;
        ProjectStatus oldStatus = p.status;
        p.status = ProjectStatus.ACTIVE;
        emit ProjectStatusChanged(_idProject, oldStatus, ProjectStatus.ACTIVE);

        // --- MINT Project SBT ke project owner ---
        uint256 nftId = nextNftId++;
        _safeMint(p.projectOwner, nftId);
        
        // Mengambil CID yang disimpan saat createProject
        string memory projectCid = tokenCid[_idProject]; 
        string memory uri = string(abi.encodePacked("https://gateway.pinata.cloud/ipfs/", projectCid));
        _setTokenURI(nftId, uri);
        
        // Simpan CID menggunakan NFT ID agar dapat diakses dari tokenURI
        tokenCid[nftId] = projectCid; 
    }

    function setProjectStatus(uint256 _idProject, ProjectStatus newStatus)
        external
        onlyOwner
        onlyValidProject(_idProject)
    {
        Project storage p = projects[_idProject];
        ProjectStatus oldStatus = p.status;
        p.status = newStatus;
        emit ProjectStatusChanged(_idProject, oldStatus, newStatus);
    }

    // ---------------- INVESTMENT ----------------
    function invest(uint256 _idProject, uint256 _amount)
        external
        nonReentrant
        onlyValidProject(_idProject)
        onlyApprovedProjectOwner(_idProject)
    {
        // Menggunakan Errors.ZeroAmount()
        if (_amount == 0) revert Errors.ZeroAmount();

        Project storage p = projects[_idProject];
        // Menggunakan Errors.InvalidState()
        if (p.status != ProjectStatus.ACTIVE) revert Errors.InvalidState();
        // Menggunakan Errors.MaxFundingExceeded()
        if (p.totalRaised + _amount > p.maxCrowdFunding) revert Errors.MaxFundingExceeded();

        idrx.safeTransferFrom(msg.sender, address(this), _amount);

        p.totalRaised += _amount;
        contribution[_idProject][msg.sender] += _amount;
        
        // UPDATE UX: Melacak total investasi user
        totalInvestment[msg.sender] += _amount; 

        // --- Mint SBT investor ---
        uint256 nftId = nextNftId++;
        _safeMint(msg.sender, nftId);

        // Mengambil CID Project (yang sudah tersimpan di approveProject) untuk metadata Investment Receipt
        // Walaupun metadata ini tidak se-spesifik per investasi, ini merujuk ke project yang diinvestasikan.
        string memory projectCid = tokenCid[_idProject];
        string memory uri = string(abi.encodePacked("https://gateway.pinata.cloud/ipfs/", projectCid));
        _setTokenURI(nftId, uri);
        tokenCid[nftId] = projectCid; // Simpan CID dengan NFT ID

        investmentsByTokenId[nftId] = Investment({
            idProject: _idProject,
            investor: msg.sender,
            amount: _amount
        });

        emit Invested(_idProject, msg.sender, _amount, nftId);

        if (p.totalRaised == p.maxCrowdFunding && p.status == ProjectStatus.ACTIVE) {
            ProjectStatus oldStatus = p.status;
            p.status = ProjectStatus.SUCCESS;
            emit ProjectStatusChanged(_idProject, oldStatus, ProjectStatus.SUCCESS);
        }
    }

    // REFUND
    function refundable(uint256 _idProject)
        external
        onlyOwner
        onlyValidProject(_idProject)
    {
        Project storage p = projects[_idProject];
        // Menggunakan Errors.InvalidState()
        if (p.status != ProjectStatus.ACTIVE && p.status != ProjectStatus.SUCCESS) revert Errors.InvalidState();

        ProjectStatus oldStatus = p.status;
        p.status = ProjectStatus.REFUNDING;
        emit ProjectStatusChanged(_idProject, oldStatus, ProjectStatus.REFUNDING);
    }

    function claimRefund(uint256 _idProject)
        external
        nonReentrant
        onlyValidProject(_idProject)
    {
        Project storage p = projects[_idProject];
        // Menggunakan Errors.InvalidState()
        if (p.status != ProjectStatus.REFUNDING) revert Errors.InvalidState();

        uint256 _amount = contribution[_idProject][msg.sender];
        // Menggunakan Errors.NothingToRefund()
        if (_amount == 0) revert Errors.NothingToRefund();

        contribution[_idProject][msg.sender] = 0;
        p.totalRaised -= _amount;
        
        // UPDATE UX: Kurangi dari total investasi user
        totalInvestment[msg.sender] -= _amount; 

        idrx.safeTransfer(msg.sender, _amount);
        emit Refunded(_idProject, msg.sender, _amount);
    }

    // WITHDraw
    function withDrawProjectFund(uint256 _idProject)
        external
        nonReentrant
        onlyOwner
        onlyValidProject(_idProject)
    {
        Project storage p = projects[_idProject];
        // Menggunakan Errors.InvalidState()
        if (p.status != ProjectStatus.SUCCESS) revert Errors.InvalidState();

        uint256 _amount = p.totalRaised;
        // Menggunakan Errors.NothingToWithdraw()
        if (_amount == 0) revert Errors.NothingToWithdraw();

        ProjectStatus oldStatus = p.status;
        p.status = ProjectStatus.CLOSED;

        idrx.safeTransfer(p.projectOwner, _amount);

        emit WithDraw(_idProject, p.projectOwner, _amount);
        emit ProjectStatusChanged(_idProject, oldStatus, ProjectStatus.CLOSED);
    }

    // PROFIT 
    function depositProfit(uint256 _idProject, uint256 _amount)
        external
        onlyOwner
        onlyValidProject(_idProject)
    {
        // Menggunakan Errors.ZeroAmount()
        if (_amount == 0) revert Errors.ZeroAmount();

        idrx.safeTransferFrom(msg.sender, address(this), _amount);
        profitPool[_idProject] += _amount;
        emit ProfitDeposited(_idProject, _amount);
    }

    function claimProfit(uint256 _idProject)
        external
        nonReentrant
        onlyValidProject(_idProject)
    {
        Project storage p = projects[_idProject];

        // Menggunakan Errors.InvalidState()
        if (p.maxCrowdFunding == 0) revert Errors.InvalidState();

        uint256 userContribution = contribution[_idProject][msg.sender];
        // Menggunakan Errors.NothingToWithdraw()
        if (userContribution == 0) revert Errors.NothingToWithdraw();

        uint256 totalProfit = profitPool[_idProject];
        // Menggunakan Errors.NothingToWithdraw()
        if (totalProfit == 0) revert Errors.NothingToWithdraw();
        // Menggunakan Errors.InvalidState()
        if (p.totalRaised == 0) revert Errors.InvalidState();

        uint256 entitled = (totalProfit * userContribution) / p.totalRaised;
        uint256 already = claimedProfit[_idProject][msg.sender];
        // Menggunakan Errors.NothingToWithdraw()
        if (entitled <= already) revert Errors.NothingToWithdraw();

        uint256 toClaim = entitled - already;
        claimedProfit[_idProject][msg.sender] = entitled;

        idrx.safeTransfer(msg.sender, toClaim);
        emit ProfitClaimed(_idProject, msg.sender, toClaim);
    }

    // ---------------- VIEW ---------------- 
    
    // Fungsi baru untuk mengambil total investasi pengguna
    function getTotalInvestment(address _user) external view returns (uint256) {
        return totalInvestment[_user];
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        // Menggunakan Errors.InvalidInput() untuk token yang tidak ada
        if (!_exists(tokenId)) revert Errors.InvalidInput();
        
        // Membangun URI menggunakan CID yang disimpan
        string memory _cid = tokenCid[tokenId];
        return string(abi.encodePacked("ipfs://", _cid));
    }


    function getProject(uint256 _idProject)
        external
        view
        onlyValidProject(_idProject)
        returns (
            uint256 id,
            address projectOwner_,
            uint256 valueProject_,
            uint256 totalRaised_,
            ProjectStatus status_
        )
    {
        Project memory p = projects[_idProject];
        return (p.id, p.projectOwner, p.valueProject, p.totalRaised, p.status);
    }

    function getClaimableProfit(uint256 _idProject, address _user)
        external
        view
        returns (uint256)
    {
        uint256 userContribution = contribution[_idProject][_user];
        if (userContribution == 0) return 0;

        uint256 totalProfit = profitPool[_idProject];
        if (totalProfit == 0) return 0;

        Project memory p = projects[_idProject];
        if (p.totalRaised == 0) return 0;

        uint256 entitled = (totalProfit * userContribution) / p.totalRaised;
        uint256 already = claimedProfit[_idProject][_user];

        return entitled > already ? entitled - already : 0;
    }

    function getInvestmentByNftId(uint256 _NftId)
        external
        view
        returns (Investment memory)
    {
        // Menggunakan fungsi _ownerOf dari ERC721
        if (_ownerOf(_NftId) == address(0)) revert Errors.InvalidProject();
        return investmentsByTokenId[_NftId];
    }
}