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

contract VaultaireVaultTest is BaseVaultaireTest {
    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {}

    /// @dev Test if the vault is correctly configured after deployment
    function test_VaultInitialization() external view {
        assertEq(address(vault.asset()), address(asset), "Incorrect asset address");
        assertEq(address(vault.share()), address(share), "Incorrect share address");
        assertEq(vault.timelock(), REDEMPTION_TIMELOCK, "Incorrect timelock period");
    }

    /// @dev Test share token initialization and vault relationship
    function test_ShareTokenInitialization() external view {
        assertEq(share.vault(address(asset)), address(vault), "Incorrect vault mapping in share token");
        assertTrue(
            dao.hasPermission(address(share), address(vault), share.VAULT_ROLE(), ""),
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

    /// @dev Test mint functionality (deposit with specific shares amount)
    function test_Mint() external {
        uint256 sharesToMint = 50 ether;

        // User2 approves and mints shares from the vault
        vm.startPrank(user2);
        asset.approve(address(vault), sharesToMint * 2); // Approve more than needed

        uint256 assetsUsed = vault.mint(sharesToMint, user2);
        vm.stopPrank();

        // Check balances after mint
        assertEq(asset.balanceOf(address(vault)), assetsUsed, "Vault didn't receive correct assets");
        assertEq(share.balanceOf(user2), sharesToMint, "User didn't receive requested shares");
        assertEq(assetsUsed, sharesToMint, "Assets used doesn't match shares (1:1 ratio expected initially)");
    }

    /// @dev Test redeem request functionality
    function test_RedeemRequest() external {
        // First deposit some assets
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);

        // Request redemption of half the shares
        uint256 redeemAmount = depositAmount / 2;
        vault.requestRedeem(redeemAmount, user1, user1);
        vm.stopPrank();

        // Verify pending redeem request
        assertEq(vault.pendingRedeemRequest(0, user1), redeemAmount, "Pending redeem request not recorded correctly");
        assertEq(vault.claimableRedeemRequest(0, user1), 0, "Should not be claimable yet");

        // Fast forward time to make the redemption claimable
        vm.warp(block.timestamp + REDEMPTION_TIMELOCK + 1);

        // Verify claimable redeem request
        assertEq(vault.pendingRedeemRequest(0, user1), 0, "Should not be pending anymore");
        assertEq(vault.claimableRedeemRequest(0, user1), redeemAmount, "Should be claimable now");
    }

    /// @dev Test redeem functionality after timelock
    function test_Redeem() external {
        // First deposit some assets
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);

        // Request redemption
        uint256 redeemAmount = depositAmount / 2;
        vault.requestRedeem(redeemAmount, user1, user1);

        // Fast forward time to make the redemption claimable
        vm.warp(block.timestamp + REDEMPTION_TIMELOCK + 1);

        // Redeem the shares
        uint256 assetsReceived = vault.redeem(redeemAmount, user1, user1);
        vm.stopPrank();

        // Check balances after redeem
        assertEq(
            asset.balanceOf(user1),
            INITIAL_ASSETS - depositAmount + assetsReceived,
            "User didn't receive correct assets"
        );
        assertEq(share.balanceOf(user1), depositAmount - redeemAmount, "User's share balance not correctly updated");
        assertEq(assetsReceived, redeemAmount, "Assets received doesn't match redeemed shares (1:1 ratio expected)");
    }

    /// @dev Test operator functionality
    function test_Operator() external {
        // User1 sets operator as an operator
        vm.startPrank(user1);

        // Expect OperatorSet event to be emitted
        vm.expectEmit(true, true, false, true);
        emit IERC7540Operator.OperatorSet(user1, operator, true);

        vault.setOperator(operator, true);
        vm.stopPrank();

        // Verify operator status
        assertTrue(vault.isOperator(user1, operator), "Operator not set correctly");

        // Deposit assets with user1
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Request redemption as operator
        vm.startPrank(operator);
        vault.requestRedeem(depositAmount / 2, user1, user1);
        vm.stopPrank();

        // Fast forward time to make the redemption claimable
        vm.warp(block.timestamp + REDEMPTION_TIMELOCK + 1);

        // Redeem shares as operator
        vm.startPrank(operator);
        vault.redeem(depositAmount / 2, user1, user1);
        vm.stopPrank();

        // Verify user1's share balance after operator-initiated redemption
        assertEq(share.balanceOf(user1), depositAmount / 2, "Operator redemption didn't work correctly");
    }

    /// @dev Test asset conversion functions
    function test_AssetConversion() external {
        // First deposit some assets to have non-zero shares
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Test convertToShares
        uint256 assets = 50 ether;
        uint256 expectedShares = assets; // 1:1 ratio initially
        assertEq(vault.convertToShares(assets), expectedShares, "convertToShares calculation incorrect");

        // Test convertToAssets
        uint256 shares = 75 ether;
        uint256 expectedAssets = shares; // 1:1 ratio initially
        assertEq(vault.convertToAssets(shares), expectedAssets, "convertToAssets calculation incorrect");
    }

    /// @dev Test maximum deposit/mint/withdraw/redeem amounts
    function test_MaximumAmounts() external {
        // Test maxDeposit should be unlimited
        assertEq(vault.maxDeposit(user1), type(uint256).max, "maxDeposit should be unlimited");

        // Test maxMint should be unlimited
        assertEq(vault.maxMint(user1), type(uint256).max, "maxMint should be unlimited");

        // Test maxWithdraw and maxRedeem (should be 0 without pending requests)
        assertEq(vault.maxWithdraw(user1), 0, "maxWithdraw should be 0 without requests");
        assertEq(vault.maxRedeem(user1), 0, "maxRedeem should be 0 without requests");

        // Set up a redemption request
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vault.requestRedeem(depositAmount / 2, user1, user1);
        vm.stopPrank();

        // Fast forward time to make the redemption claimable
        vm.warp(block.timestamp + REDEMPTION_TIMELOCK + 1);

        // Test maxWithdraw and maxRedeem with claimable request
        assertEq(vault.maxWithdraw(user1), depositAmount / 2, "maxWithdraw incorrect with claimable request");
        assertEq(vault.maxRedeem(user1), depositAmount / 2, "maxRedeem incorrect with claimable request");
    }

    /// @dev Test failing cases
    function test_RevertCases() external {
        // Test revert when trying to redeem with insufficient balance
        vm.startPrank(user1);
        vm.expectRevert();
        vault.requestRedeem(1 ether, user1, user1);
        vm.stopPrank();

        // Test revert when trying to claim before timelock expires
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vault.requestRedeem(depositAmount / 2, user1, user1);

        vm.expectRevert();
        vault.redeem(depositAmount / 2, user1, user1);
        vm.stopPrank();

        // Test revert when non-operator tries to redeem on behalf of someone else
        vm.startPrank(user2);
        vm.expectRevert();
        vault.redeem(depositAmount / 2, user1, user1);
        vm.stopPrank();

        // Test revert when trying to set yourself as your own operator
        vm.startPrank(user1);
        vm.expectRevert();
        vault.setOperator(user1, true);
        vm.stopPrank();
    }

    function test_MinVaultShareBps() external {
        // Initial value should match what was set in constructor
        assertEq(vault.minVaultShareBps(), INITIAL_MIN_VAULT_SHARE_BPS, "Initial minVaultShareBps incorrect");

        // Non-DAO address should not be able to set minVaultShareBps
        vm.startPrank(user1);
        vm.expectRevert();
        vault.setMinVaultShareBps(5000);
        vm.stopPrank();

        // DAO should be able to set minVaultShareBps
        vm.startPrank(address(dao));
        vault.setMinVaultShareBps(5000);
        vm.stopPrank();

        // Verify the new value
        assertEq(vault.minVaultShareBps(), 5000, "minVaultShareBps not updated correctly");

        // Test getCurrentVaultShareBps with no shares
        assertEq(vault.getCurrentVaultShareBps(), 0, "Should be 0 when no shares exist");

        // Deposit some assets to test getCurrentVaultShareBps
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Since we're using 1:1 ratio initially, the share BPS should be 10000 (100%)
        assertEq(vault.getCurrentVaultShareBps(), 10000, "Current vault share BPS should be 100%");
    }
}
