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
        vault.requestRedeem(depositAmount, user1, user1);
        vm.warp(block.timestamp + REDEMPTION_TIMELOCK + 1);
        vault.withdraw(depositAmount, user1, user1);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(lendingVault)), 0);
        assertEq(lendingVault.balanceOf(address(strategy)), 0);
    }
}
