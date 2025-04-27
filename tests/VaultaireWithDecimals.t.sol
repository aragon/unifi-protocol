// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import { BaseVaultaireTest } from "./BaseVaultaireTest.t.sol";

import { VaultRedeem } from "../src/vault/VaultRedeem.sol";
import { IERC7575 } from "../src/interfaces/IERC7575.sol";

contract VaultaireVaultWithDecimalsTest is BaseVaultaireTest {
    uint256 public decimalShift;

    function setUp() public {
        decimalShift = 10 ** (18 - assetWithDecimals.decimals());
        vm.prank(address(dao));
        vault.setInvestmentRatio(0);
    }

    /// @dev Test if the vault is correctly configured after deployment
    function test_VaultInitialization() external view {
        assertEq(address(vaultWithDecimals.asset()), address(assetWithDecimals), "Incorrect asset address");
        assertEq(address(vaultWithDecimals.share()), address(share), "Incorrect share address");
        assertEq(vaultWithDecimals.minTimelock(), REDEMPTION_TIMELOCK, "Incorrect timelock period");
    }

    /// @dev Test share token initialization and vault relationship
    function test_ShareTokenInitialization() external view {
        assertEq(
            share.vault(address(assetWithDecimals)),
            address(vaultWithDecimals),
            "Incorrect vault mapping in share token"
        );
        assertTrue(
            dao.hasPermission(address(share), address(vaultWithDecimals), share.VAULT_ROLE(), ""),
            "Vault doesn't have VAULT_ROLE"
        );
        assertEq(share.name(), "uUSD", "Incorrect share token name");
        assertEq(share.symbol(), "uUSD", "Incorrect share token symbol");
    }

    /// @dev Test basic deposit functionality
    function test_Deposit() external {
        uint256 depositAmount = 100 ether;

        // User1 approves and deposits assets into the vault
        vm.startPrank(user1);
        assetWithDecimals.approve(address(vaultWithDecimals), depositAmount);

        // Expect Deposit event to be emitted
        vm.expectEmit(true, true, false, true);
        emit IERC7575.Deposit(user1, user1, depositAmount, depositAmount * decimalShift);

        uint256 sharesMinted = vaultWithDecimals.deposit(depositAmount, user1);
        vm.stopPrank();

        // Check balances after deposit
        assertEq(assetWithDecimals.balanceOf(address(vaultWithDecimals)), depositAmount, "Vault didn't receive assets");
        assertEq(share.balanceOf(user1), sharesMinted, "User didn't receive shares");
        assertEq(
            sharesMinted,
            depositAmount * decimalShift,
            "Shares minted doesn't match deposit (1:1 ratio expected initially)"
        );
    }

    /// @dev Test mint functionality (deposit with specific shares amount)
    function test_Mint() external {
        uint256 sharesToMint = 50 ether;

        // User2 approves and mints shares from the vault
        vm.startPrank(user2);
        assetWithDecimals.approve(address(vaultWithDecimals), sharesToMint * 2); // Approve more than needed

        uint256 assetsUsed = vaultWithDecimals.mint(sharesToMint, user2);
        vm.stopPrank();

        // Check balances after mint
        assertEq(
            assetWithDecimals.balanceOf(address(vaultWithDecimals)), assetsUsed, "Vault didn't receive correct assets"
        );
        assertEq(share.balanceOf(user2), sharesToMint, "User didn't receive requested shares");
        assertEq(
            assetsUsed * decimalShift, sharesToMint, "Assets used doesn't match shares (1:1 ratio expected initially)"
        );
    }

    /// @dev Test redeem request functionality
    function test_RedeemRequest() external {
        // First deposit some assets
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        assetWithDecimals.approve(address(vaultWithDecimals), depositAmount);
        vaultWithDecimals.deposit(depositAmount, user1);

        // Request redemption of half the shares
        uint256 redeemAmount = depositAmount / 2;
        vaultWithDecimals.requestRedeem(redeemAmount, user1, user1);
        vm.stopPrank();

        // Verify pending redeem request
        assertEq(
            vaultWithDecimals.pendingRedeemRequest(0, user1),
            redeemAmount,
            "Pending redeem request not recorded correctly"
        );
        assertEq(vaultWithDecimals.claimableRedeemRequest(0, user1), 0, "Should not be claimable yet");

        // Fast forward time to make the redemption claimable
        vm.warp(block.timestamp + REDEMPTION_TIMELOCK + 1);

        // Verify claimable redeem request
        assertEq(vaultWithDecimals.pendingRedeemRequest(0, user1), 0, "Should not be pending anymore");
        assertEq(vaultWithDecimals.claimableRedeemRequest(0, user1), redeemAmount, "Should be claimable now");
    }

    /// @dev Test redeem functionality after timelock
    function test_Redeem() external {
        // First deposit some assets
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        assetWithDecimals.approve(address(vaultWithDecimals), depositAmount);
        vaultWithDecimals.deposit(depositAmount, user1);

        // Request redemption
        uint256 redeemAmount = decimalShift * (depositAmount / 2);
        vaultWithDecimals.requestRedeem(redeemAmount, user1, user1);

        // Fast forward time to make the redemption claimable
        vm.warp(block.timestamp + REDEMPTION_TIMELOCK + 1);

        // Redeem the shares
        uint256 assetsReceived = vaultWithDecimals.redeem(redeemAmount, user1, user1);
        vm.stopPrank();

        // Check balances after redeem
        assertEq(
            assetWithDecimals.balanceOf(user1),
            INITIAL_ASSETS - depositAmount + assetsReceived,
            "User didn't receive correct assets"
        );
        assertEq(
            share.balanceOf(user1),
            (depositAmount * decimalShift) - redeemAmount,
            "User's share balance not correctly updated"
        );
        assertEq(
            assetsReceived * decimalShift,
            redeemAmount,
            "Assets received doesn't match redeemed shares (1:1 ratio expected)"
        );
    }

    /// @dev Test asset conversion functions
    function test_AssetConversion() external {
        // First deposit some assets to have non-zero shares
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        assetWithDecimals.approve(address(vaultWithDecimals), depositAmount);
        vaultWithDecimals.deposit(depositAmount, user1);
        vm.stopPrank();

        // Test convertToShares
        uint256 assets = 50 ether;
        uint256 expectedShares = assets * decimalShift; // 1:1 ratio initially
        assertEq(vaultWithDecimals.convertToShares(assets), expectedShares, "convertToShares calculation incorrect");

        // Test convertToAssets
        uint256 shares = 75 ether;
        uint256 expectedAssets = shares / decimalShift; // 1:1 ratio initially
        assertEq(vaultWithDecimals.convertToAssets(shares), expectedAssets, "convertToAssets calculation incorrect");
    }

    /// @dev Test maximum deposit/mint/withdraw/redeem amounts
    function test_MaximumAmounts() external {
        // Test maxDeposit should be unlimited
        assertEq(vaultWithDecimals.maxDeposit(user1), type(uint256).max, "maxDeposit should be unlimited");

        // Test maxMint should be unlimited
        assertEq(vaultWithDecimals.maxMint(user1), type(uint256).max, "maxMint should be unlimited");

        // Test maxWithdraw and maxRedeem (should be 0 without pending requests)
        assertEq(vaultWithDecimals.maxWithdraw(user1), 0, "maxWithdraw should be 0 without requests");
        assertEq(vaultWithDecimals.maxRedeem(user1), 0, "maxRedeem should be 0 without requests");

        // Set up a redemption request
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        assetWithDecimals.approve(address(vaultWithDecimals), depositAmount);
        vaultWithDecimals.deposit(depositAmount, user1);
        vaultWithDecimals.requestRedeem(depositAmount / 2, user1, user1);
        vm.stopPrank();

        // Fast forward time to make the redemption claimable
        vm.warp(block.timestamp + REDEMPTION_TIMELOCK + 1);

        // Test maxWithdraw and maxRedeem with claimable request
        assertEq(
            vaultWithDecimals.maxWithdraw(user1) * decimalShift,
            (depositAmount / 2),
            "maxWithdraw incorrect with claimable withdraw"
        );
        assertEq(vaultWithDecimals.maxRedeem(user1), (depositAmount / 2), "maxRedeem incorrect with claimable redeem");
    }

    /// @dev Test failing cases
    function test_RevertCases() external {
        // Test revert when trying to redeem with insufficient balance
        vm.startPrank(user1);
        vm.expectRevert();
        vaultWithDecimals.requestRedeem(1 ether, user1, user1);
        vm.stopPrank();

        // Test revert when trying to claim before timelock expires
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        assetWithDecimals.approve(address(vaultWithDecimals), depositAmount);
        vaultWithDecimals.deposit(depositAmount, user1);
        vaultWithDecimals.requestRedeem(depositAmount / 2, user1, user1);

        vm.expectRevert();
        vaultWithDecimals.redeem(depositAmount / 2, user1, user1);
        vm.stopPrank();

        // Test revert when non-operator tries to redeem on behalf of someone else
        vm.startPrank(user2);
        vm.expectRevert();
        vaultWithDecimals.redeem(depositAmount / 2, user1, user1);
        vm.stopPrank();

        // Test revert when trying to set yourself as your own operator
        vm.startPrank(user1);
        vm.expectRevert();
        vaultWithDecimals.setOperator(user1, true);
        vm.stopPrank();
    }

    function test_MinVaultShareBps() external {
        // Initial value should match what was set in constructor
        assertEq(
            vaultWithDecimals.minVaultShareBps(), INITIAL_MIN_VAULT_SHARE_BPS, "Initial minVaultShareBps incorrect"
        );

        // Non-DAO address should not be able to set minVaultShareBps
        vm.startPrank(user1);
        vm.expectRevert();
        vaultWithDecimals.setMinVaultShareBps(5000);
        vm.stopPrank();

        // DAO should be able to set minVaultShareBps
        vm.startPrank(address(dao));
        vaultWithDecimals.setMinVaultShareBps(5000);
        vm.stopPrank();

        // Verify the new value
        assertEq(vaultWithDecimals.minVaultShareBps(), 5000, "minVaultShareBps not updated correctly");

        // Test getCurrentVaultShareBps with no shares
        assertEq(vaultWithDecimals.getCurrentVaultShareBps(), 0, "Should be 0 when no shares exist");

        // Deposit some assets to test getCurrentVaultShareBps
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        assetWithDecimals.approve(address(vaultWithDecimals), depositAmount);
        vaultWithDecimals.deposit(depositAmount, user1);
        vm.stopPrank();

        // Since we're using 1:1 ratio initially, the share BPS should be 10000 (100%)
        assertEq(vaultWithDecimals.getCurrentVaultShareBps(), 10_000, "Current vault share BPS should be 100%");
    }

    /// @dev Test the exponential timelock calculation with different redemption amounts
    function test_ExponentialTimelock() external {
        // First deposit some assets to establish a baseline
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        assetWithDecimals.approve(address(vaultWithDecimals), depositAmount);
        vaultWithDecimals.deposit(depositAmount, user1);
        asset2.approve(address(vault2), depositAmount * decimalShift);
        vault2.deposit(depositAmount * decimalShift, user1);

        // Initial state should be healthy (100% ratio)
        uint256 smallRedemption = 10 ether; // 10% redemption
        uint256 timelock = vaultWithDecimals.previewRedeemTimelock(smallRedemption);
        assertEq(timelock, REDEMPTION_TIMELOCK, "Should only have base timelock when healthy");

        // Try with a larger redemption that would put us below minVaultShareBps
        uint256 largeRedemption = 95 ether; // 95% redemption
        uint256 increasedTimelock =
            vaultWithDecimals.previewRedeemTimelock(vaultWithDecimals.convertToShares(largeRedemption));
        assertTrue(increasedTimelock > REDEMPTION_TIMELOCK, "Timelock should increase for large redemptions");

        // Test an even larger redemption
        uint256 veryLargeRedemption = 99 ether; // 90% redemption
        uint256 maxTimelock =
            vaultWithDecimals.previewRedeemTimelock(vaultWithDecimals.convertToShares(veryLargeRedemption));
        assertTrue(maxTimelock > increasedTimelock, "Timelock should be even higher for very large redemptions");

        // Verify actual redemption matches preview
        uint256 previewedTimelock =
            vaultWithDecimals.previewRedeemTimelock(vaultWithDecimals.convertToShares(largeRedemption));
        vaultWithDecimals.requestRedeem(vaultWithDecimals.convertToShares(largeRedemption), user1, user1);

        VaultRedeem.RedemptionRequest memory redeemRequest = vaultWithDecimals.pendingRedeemRequestData(user1);
        assertEq(
            redeemRequest.claimableTimestamp,
            previewedTimelock + uint32(block.timestamp),
            "Actual timelock should match preview"
        );
        vm.stopPrank();
    }
}
