// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import { BaseVaultaireTest } from "./BaseVaultaireTest.t.sol";

import { IERC7575 } from "../src/interfaces/IERC7575.sol";
import { PausableShare } from "../src/share/PausableShare.sol";

contract VaultairePausePermissions is BaseVaultaireTest {
    /// @dev Test basic deposit functionality
    function test_Deposit() external {
        uint256 depositAmount = 100 ether;

        // User1 approves and deposits assets into the vault
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);

        // Expect Deposit event to be emitted
        vm.expectEmit(true, true, false, true);
        emit IERC7575.Deposit(user1, user1, depositAmount, depositAmount);

        uint256 sharesMinted = vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Check balances after deposit
        assertEq(asset.balanceOf(address(vault)), depositAmount, "Vault didn't receive assets");
        assertEq(share.balanceOf(user1), sharesMinted, "User didn't receive shares");
        assertEq(sharesMinted, depositAmount, "Shares minted doesn't match deposit (1:1 ratio expected initially)");
    }

    /// @dev Test basic deposit functionality
    function test_DepositAfterPause() external {
        uint256 depositAmount = 100 ether;

        // Pause the vault
        vm.prank(address(dao));
        share.pause();

        // User1 approves and deposits assets into the vault
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);

        vm.expectRevert(PausableShare.SharesPaused.selector);

        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Check balances after deposit
        assertEq(asset.balanceOf(address(vault)), 0, "Vault didn't receive assets");
        assertEq(share.balanceOf(user1), 0, "User didn't receive shares");
    }

    /// @dev Test basic deposit functionality
    function test_WithdrawalAfterPause() external {
        uint256 depositAmount = 100 ether;

        // User1 approves and deposits assets into the vault
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        uint256 sharesMinted = vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Pause the vault
        vm.prank(address(dao));
        share.pause();

        // Start redemption request
        vm.startPrank(user1);
        uint256 redeemAmount = depositAmount / 2;
        vm.expectRevert(PausableShare.SharesPaused.selector);
        vault.requestRedeem(redeemAmount, user1, user1);
        vm.stopPrank();

        // Verify claimable redeem request
        assertEq(vault.pendingRedeemRequest(0, user1), 0, "Should not be pending anymore");
        assertEq(vault.claimableRedeemRequest(0, user1), 0, "Should be claimable now");

        assertEq(asset.balanceOf(address(vault)), depositAmount, "Vault didn't receive assets");
        assertEq(share.balanceOf(user1), sharesMinted, "User didn't receive shares");
    }
}
