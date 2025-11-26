// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/StomaTrade.sol";
import "../src/MockIDRX.sol";
import "../src/Events.sol"; // Untuk ProjectStatus

contract StomaTradeTest is Test {
    StomaTrade public stomaTrade;
    MockIDRX public idrx;

    // Alamat-alamat yang digunakan untuk testing
    address public immutable owner = address(this);
    address public immutable projectOwner = address(0x1);
    address public immutable investor1 = address(0x2);
    address public immutable investor2 = address(0x3);
    address public immutable randomUser = address(0x4);

    // Nilai-nilai konstanta (dalam unit dasar, misalnya 10^18)
    uint256 constant UNIT = 10**18;
    uint256 constant INITIAL_SUPPLY_IDRX = 10_000_000; // 10 Juta IDRX
    uint256 constant PROJECT_VALUE = 500_000 * UNIT;
    uint256 constant MAX_FUNDING = 100_000 * UNIT;
    uint256 constant INVEST_AMOUNT_1 = 60_000 * UNIT; // 60%
    uint256 constant INVEST_AMOUNT_2 = 40_000 * UNIT; // 40%

    // Fungsi setUp akan dijalankan sebelum setiap test
    function setUp() public {
        // 1. Deploy Mock IDRX
        // MockIDRX constructor menerima supply tanpa dikalikan 10^18
        idrx = new MockIDRX(INITIAL_SUPPLY_IDRX);
        
        // 2. Deploy StomaTrade
        // StomaTrade constructor membutuhkan address token IDRX
        stomaTrade = new StomaTrade(address(idrx));

        // 3. Mint IDRX ke addresses investor untuk testing
        // Fungsi mint MockIDRX menerima nilai tanpa 10^18
        idrx.mint(investor1, 1_000_000); // 1 Juta IDRX
        idrx.mint(investor2, 1_000_000); // 1 Juta IDRX

        // 4. Label addresses untuk debugging
        vm.label(owner, "Owner (Deployer)");
        vm.label(projectOwner, "ProjectOwner");
        vm.label(investor1, "Investor1");
        vm.label(investor2, "Investor2");
        vm.label(randomUser, "RandomUser");
    }

    // --- HELPER FUNCTIONS ---
    function createAndApproveProject() internal returns (uint256) {
        uint256 projectId = stomaTrade.createProject(
            projectOwner,
            PROJECT_VALUE,
            MAX_FUNDING
        );
        stomaTrade.approveProject(projectId);
        return projectId;
    }


    function testCreateProjectSuccess() public {
        uint256 projectId = stomaTrade.createProject(
            projectOwner,
            PROJECT_VALUE,
            MAX_FUNDING
        );

        assertEq(projectId, 1, "Project ID must be 1");
        
        (
            uint256 id,
            address owner_,
            uint256 maxFunding_,
            uint256 totalRaised,
            ProjectStatus status
        ) = stomaTrade.getProject(projectId);

        assertEq(id, 1);
        assertEq(owner_, projectOwner);
        assertEq(maxFunding_, MAX_FUNDING);
        assertEq(totalRaised, 0);
        assertEq(uint(status), uint(ProjectStatus.PENDING), "Initial status must be PENDING");
    }

    function testFailCreateProjectZeroFunding() public {
        // Harus revert ZeroAmount()
        vm.expectRevert("ZeroAmount"); 
        stomaTrade.createProject(projectOwner, PROJECT_VALUE, 0);
    }
    
    function testApproveProjectSuccess() public {
        uint256 projectId = stomaTrade.createProject(projectOwner, PROJECT_VALUE, MAX_FUNDING);
        
        stomaTrade.approveProject(projectId);

        (, , , , ProjectStatus status) = stomaTrade.getProject(projectId);
        assertEq(uint(status), uint(ProjectStatus.ACTIVE), "Status should be ACTIVE after approval");
        assertTrue(stomaTrade.allowedApprovals(projectOwner), "Project owner should be approved");
    }

    function testFailApproveProjectNotOwner() public {
        uint256 projectId = stomaTrade.createProject(projectOwner, PROJECT_VALUE, MAX_FUNDING);
        
        vm.prank(randomUser);
        // Harus revert Ownable/NotOwner
        vm.expectRevert(); 
        stomaTrade.approveProject(projectId);
    }


    function testInvestSuccess() public {
        uint256 projectId = createAndApproveProject();
        uint256 investAmount = 10_000 * UNIT;
        
        // 1. Approve IDRX ke StomaTrade
        vm.startPrank(investor1);
        idrx.approve(address(stomaTrade), investAmount);
        
        // 2. Invest
        stomaTrade.invest(projectId, investAmount);
        vm.stopPrank();

        // Cek total raised dan contribution
        (, , , uint256 totalRaised, ) = stomaTrade.getProject(projectId);
        assertEq(totalRaised, investAmount, "Total raised must match investment");
        assertEq(stomaTrade.contribution(projectId, investor1), investAmount, "Contribution mapping incorrect");

        // Cek kepemilikan NFT (Soulbound Token)
        uint256 nftId = 1;
        assertEq(stomaTrade.ownerOf(nftId), investor1, "Investor should own NFT (ID 1)");
    }
    
    function testInvestReachesMaxFundingAndChangesStatus() public {
        uint256 projectId = createAndApproveProject();

        // Invest exact max funding
        vm.startPrank(investor1);
        idrx.approve(address(stomaTrade), MAX_FUNDING);
        stomaTrade.invest(projectId, MAX_FUNDING);
        vm.stopPrank();

        // Check status changed to SUCCESS
        (, , , , ProjectStatus status) = stomaTrade.getProject(projectId);
        assertEq(uint(status), uint(ProjectStatus.SUCCESS), "Status should be SUCCESS");
    }
    
    function testFailInvestMaxFundingExceeded() public {
        uint256 projectId = createAndApproveProject();
        uint256 tooMuch = MAX_FUNDING + 1;

        vm.startPrank(investor1);
        idrx.approve(address(stomaTrade), tooMuch);
        
        // Harus revert MaxFundingExceeded()
        vm.expectRevert("MaxFundingExceeded"); 
        stomaTrade.invest(projectId, tooMuch); 
        vm.stopPrank();
    }
    
    function testFailInvestUnapprovedProject() public {
        // Project dibuat tapi belum di-approve
        uint256 projectId = stomaTrade.createProject(projectOwner, PROJECT_VALUE, MAX_FUNDING);
        uint256 investAmount = 10_000 * UNIT;

        vm.startPrank(investor1);
        idrx.approve(address(stomaTrade), investAmount);
        
        // Harus revert ApprovalNotAllowed() karena project owner belum di-approve
        vm.expectRevert("ApprovalNotAllowed"); 
        stomaTrade.invest(projectId, investAmount); 
        vm.stopPrank();
    }



    function testClaimRefundSuccess() public {
        uint256 projectId = createAndApproveProject();
        uint256 investAmount = 50_000 * UNIT;
        uint256 balanceBefore;
        
        // 1. Invest
        vm.startPrank(investor1);
        idrx.approve(address(stomaTrade), investAmount);
        stomaTrade.invest(projectId, investAmount);
        balanceBefore = idrx.balanceOf(investor1); // Saldo IDRX setelah invest (sudah berkurang)
        vm.stopPrank();

        // 2. Set status ke REFUNDING (hanya owner StomaTrade)
        stomaTrade.refundable(projectId);

        // 3. Claim refund
        vm.prank(investor1);
        stomaTrade.claimRefund(projectId);

        // Cek saldo kembali
        assertEq(idrx.balanceOf(investor1), balanceBefore + investAmount, "Balance should be fully restored");
        assertEq(stomaTrade.contribution(projectId, investor1), 0, "Contribution must be reset to 0");
    }

    function testFailClaimRefundNotRefunding() public {
        uint256 projectId = createAndApproveProject(); // Status ACTIVE
        uint256 investAmount = 10 * UNIT;

        vm.startPrank(investor1);
        idrx.approve(address(stomaTrade), investAmount);
        stomaTrade.invest(projectId, investAmount);
        
        // Harus revert InvalidStatus() karena status masih ACTIVE
        vm.expectRevert("InvalidStatus"); 
        stomaTrade.claimRefund(projectId);
    }
    

    
    function testWithDrawProjectFundSuccess() public {
        uint256 projectId = createAndApproveProject();

        // Invest to reach max funding (Status = SUCCESS)
        vm.startPrank(investor1);
        idrx.approve(address(stomaTrade), MAX_FUNDING);
        stomaTrade.invest(projectId, MAX_FUNDING);
        vm.stopPrank();

        // Withdraw
        uint256 balanceBefore = idrx.balanceOf(projectOwner);
        stomaTrade.withDrawProjectFund(projectId);
        uint256 balanceAfter = idrx.balanceOf(projectOwner);

        assertEq(balanceAfter - balanceBefore, MAX_FUNDING, "Project owner should receive full funding");

        // Check status changed to CLOSED
        (, , , , ProjectStatus status) = stomaTrade.getProject(projectId);
        assertEq(uint(status), uint(ProjectStatus.CLOSED), "Status should be CLOSED");
    }
    
    function testFailWithDrawNotSuccess() public {
        uint256 projectId = createAndApproveProject(); // Status ACTIVE
        
        // Harus revert InvalidStatus()
        vm.expectRevert("InvalidStatus"); 
        stomaTrade.withDrawProjectFund(projectId);
    }

    function testDepositAndClaimProfitSingleInvestor() public {
        uint256 projectId = createAndApproveProject();

        // 1. Invest 100% (MAX_FUNDING)
        vm.startPrank(investor1);
        idrx.approve(address(stomaTrade), MAX_FUNDING);
        stomaTrade.invest(projectId, MAX_FUNDING);
        vm.stopPrank();
        
        // 2. Deposit profit (misalnya 10,000 IDRX, dilakukan oleh Owner)
        uint256 profitAmount = 10_000 * UNIT;
        idrx.approve(address(stomaTrade), profitAmount);
        stomaTrade.depositProfit(projectId, profitAmount);

        // 3. Claim profit
        uint256 balanceBefore = idrx.balanceOf(investor1);
        vm.prank(investor1);
        stomaTrade.claimProfit(projectId);
        uint256 balanceAfter = idrx.balanceOf(investor1);

        assertEq(balanceAfter - balanceBefore, profitAmount, "Investor 1 should claim 100% of profit");
        assertEq(stomaTrade.getClaimableProfit(projectId, investor1), 0, "Claimable profit must be 0 after claim");
    }

    function testDepositAndClaimProfitMultipleInvestors() public {
        uint256 projectId = createAndApproveProject();
        
        // 1. Invest (60% dan 40%)
        vm.startPrank(investor1);
        idrx.approve(address(stomaTrade), INVEST_AMOUNT_1);
        stomaTrade.invest(projectId, INVEST_AMOUNT_1);
        vm.stopPrank();

        vm.startPrank(investor2);
        idrx.approve(address(stomaTrade), INVEST_AMOUNT_2);
        stomaTrade.invest(projectId, INVEST_AMOUNT_2);
        vm.stopPrank();

        // 2. Deposit profit (10,000 IDRX)
        uint256 profitAmount = 10_000 * UNIT;
        idrx.approve(address(stomaTrade), profitAmount);
        stomaTrade.depositProfit(projectId, profitAmount); // Dilakukan oleh Owner
        
        // 3. Perhitungan yang diharapkan
        uint256 expectedProfit1 = (profitAmount * INVEST_AMOUNT_1) / MAX_FUNDING; // 60%
        uint256 expectedProfit2 = (profitAmount * INVEST_AMOUNT_2) / MAX_FUNDING; // 40%
        
        // Cek claimable
        assertEq(stomaTrade.getClaimableProfit(projectId, investor1), expectedProfit1, "Claimable 1 incorrect");
        assertEq(stomaTrade.getClaimableProfit(projectId, investor2), expectedProfit2, "Claimable 2 incorrect");
    }


    function testFailTransferNFTIsSoulbound() public {
        uint256 projectId = createAndApproveProject();
        uint256 investAmount = 10 * UNIT;

        // Investor1 invest dan mendapatkan NFT ID 1
        vm.startPrank(investor1);
        idrx.approve(address(stomaTrade), investAmount);
        stomaTrade.invest(projectId, investAmount);
        
        uint256 nftId = 1;
        
        // Coba transfer dari investor1 ke investor2
        // Harus revert TransferNotAllowed() karena ini Soulbound Token
        vm.expectRevert("TransferNotAllowed");
        stomaTrade.transferFrom(investor1, investor2, nftId);
        
        vm.stopPrank();
    }
}