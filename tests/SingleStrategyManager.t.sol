// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import {BaseVaultaireTest} from "./BaseVaultaireTest.t.sol";
import {console2} from "forge-std/src/console2.sol";

import {VaultaireVault} from "../src/VaultaireVault.sol";
import {ERC7575Share} from "../src/ERC7575Share.sol";
import {IERC7575} from "../src/interfaces/IERC7575.sol";
import {IERC7540Operator} from "../src/interfaces/IERC7540.sol";
import {MintableERC20} from "./mocks/MintableERC20.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {createTestDAO} from "./mocks/MockDAO.sol";

contract SingleStrategyManagerTest is BaseVaultaireTest {
    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        vm.prank(address(dao));
        vault.setInvestmentRatio(8000);
    }

    /// @dev Test if the vault is correctly configured after deployment
    function test_VaultStrategyDeposit() external {
        uint256 depositAmount = 10 ether;

        // User1 approves and deposits assets into the vault
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);

        // Expect Deposit event to be emitted
        vm.expectEmit(true, true, false, true);
        emit IERC7575.Deposit(user1, user1, depositAmount, depositAmount);

        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(vault)), 2000000000000000000);
        assertEq(asset.balanceOf(address(lendingVault)), 8000000000000000000);
        assertEq(lendingVault.balanceOf(address(strategy)), 8000000000000000000);
    }

    function test_VaultStrategyWithdraw() external {
        uint256 depositAmount = 10 ether;

        // User1 approves and deposits assets into the vault
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);

        // Expect Deposit event to be emitted
        vm.expectEmit(true, true, false, true);
        emit IERC7575.Deposit(user1, user1, depositAmount, depositAmount);

        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(vault)), 2000000000000000000);
        assertEq(asset.balanceOf(address(lendingVault)), 8000000000000000000);
        assertEq(lendingVault.balanceOf(address(strategy)), 8000000000000000000);
        assertEq(vault.totalAssets(), depositAmount);

        // User1 withdraws assets from the vault
        vm.startPrank(user1);
        vault.requestRedeem(1 ether, user1, user1);
        vm.warp(block.timestamp + REDEMPTION_TIMELOCK + 1);
        vault.withdraw(1 ether, user1, user1);
        vm.stopPrank();

        assertEq(vault.totalAssets(), depositAmount - 1 ether, "Vault total assets should be depositAmount - 1 ether");
        assertEq(asset.balanceOf(address(vault)), 2 ether, "Vault balance should be 2 ether");
        assertEq(asset.balanceOf(address(lendingVault)), 7 ether, "Lending vault balance should be 7 ether");
        assertEq(lendingVault.balanceOf(address(strategy)), 7 ether, "Strategy balance should be 7 ether");
    }

    function test_VaultStrategyWithdrawWithDeallocation() external {
        uint256 depositAmount = 10 ether;

        // User1 approves and deposits assets into the vault
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);

        // Expect Deposit event to be emitted
        vm.expectEmit(true, true, false, true);
        emit IERC7575.Deposit(user1, user1, depositAmount, depositAmount);

        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(vault)), 2000000000000000000);
        assertEq(asset.balanceOf(address(lendingVault)), 8000000000000000000);
        assertEq(lendingVault.balanceOf(address(strategy)), 8000000000000000000);
        assertEq(vault.totalAssets(), depositAmount);

        // User1 withdraws assets from the vault
        vm.startPrank(user1);
        vault.requestRedeem(depositAmount, user1, user1);
        vm.warp(block.timestamp + REDEMPTION_TIMELOCK + 1);
        vault.withdraw(depositAmount, user1, user1);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(lendingVault)), 0);
        assertEq(lendingVault.balanceOf(address(strategy)), 0);
    }

    function test_StrategyAllocationRatioChange() external {
        uint256 depositAmount = 10 ether;

        // Initial deposit with 80% ratio
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Change ratio to 60%
        vm.prank(address(dao));
        vault.setInvestmentRatio(6000);

        assertEq(
            asset.balanceOf(address(vault)),
            4 ether,
            "After changing ratio to 60%, vault should hold 40% of initial deposit"
        );
        assertEq(
            asset.balanceOf(address(lendingVault)),
            6 ether,
            "After changing ratio to 60%, lending vault should hold 60% of initial deposit"
        );

        // New deposit should follow new ratio
        vm.startPrank(user2);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user2);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(vault)), 8 ether, "Vault should hold 40% of new deposit");
        assertEq(asset.balanceOf(address(lendingVault)), 12 ether, "Lending vault should hold 60% of new deposit");
    }

    function test_StrategyWithdrawWithPartialDeallocation() external {
        uint256 depositAmount = 10 ether;
        uint256 withdrawAmount = 5 ether;

        // Setup: deposit assets
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);

        // Request partial withdrawal
        vault.requestRedeem(withdrawAmount, user1, user1);
        vm.warp(block.timestamp + REDEMPTION_TIMELOCK + 1);
        vault.withdraw(withdrawAmount, user1, user1);
        vm.stopPrank();

        assertEq(vault.totalAssets(), depositAmount - withdrawAmount, "Total assets should be reduced");
        assertEq(asset.balanceOf(address(vault)), 2 ether, "Vault balance should be reduced proportionally");
        assertEq(asset.balanceOf(address(lendingVault)), 3 ether, "Strategy balance should be reduced proportionally");
    }

    function test_ZeroInvestmentRatio() external {
        // Set investment ratio to 0
        vm.prank(address(dao));
        vault.setInvestmentRatio(0);

        uint256 depositAmount = 10 ether;

        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(vault)), depositAmount, "All assets should remain in vault");
        assertEq(asset.balanceOf(address(lendingVault)), 0, "No assets should be in strategy");
    }

    function test_MaxInvestmentRatio() external {
        // Set investment ratio to 100%
        vm.prank(address(dao));
        vault.setInvestmentRatio(10000);

        uint256 depositAmount = 10 ether;

        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(vault)), 0, "No assets should remain in vault");
        assertEq(asset.balanceOf(address(lendingVault)), depositAmount, "All assets should be in strategy");
    }

    function test_InvestmentRatioRevertOnExceed() external {
        vm.startPrank(address(dao));
        vm.expectRevert(abi.encodeWithSignature("RatioExceeds100Percent(uint256)", 10001));
        vault.setInvestmentRatio(10001);
        vm.stopPrank();
    }

    function test_OnlyDAOCanSetInvestmentRatio() external {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OnlyDAOAllowed(address,address)", user1, address(dao)));
        vault.setInvestmentRatio(5000);
    }

    function test_MultipleDepositsWithStrategy() external {
        uint256 depositAmount = 5 ether;

        // First deposit
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Second deposit
        vm.startPrank(user2);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user2);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(vault)), 2 ether, "Vault should hold 20% of total deposits");
        assertEq(asset.balanceOf(address(lendingVault)), 8 ether, "Strategy should hold 80% of total deposits");
        assertEq(vault.totalAssets(), depositAmount * 2, "Total assets should reflect both deposits");
    }

    function test_StrategyWithdrawWithFullDeallocation() external {
        uint256 depositAmount = 10 ether;

        // Setup: deposit assets
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);

        // Request full withdrawal
        vault.requestRedeem(depositAmount, user1, user1);
        vm.warp(block.timestamp + REDEMPTION_TIMELOCK + 1);
        vault.withdraw(depositAmount, user1, user1);
        vm.stopPrank();

        assertEq(vault.totalAssets(), 0, "Total assets should be zero");
        assertEq(asset.balanceOf(address(vault)), 0, "Vault should have no assets");
        assertEq(asset.balanceOf(address(lendingVault)), 0, "Strategy should have no assets");
    }
}
