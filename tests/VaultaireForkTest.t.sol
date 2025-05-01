// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
// import { console2 } from "forge-std/src/console2.sol";

import {ERC7575Share} from "../src/ERC7575Share.sol";
import {VaultaireVault} from "../src/VaultaireVault.sol";
import {IERC7575} from "../src/interfaces/IERC7575.sol";
import {ERC4626Strategy} from "../src/strategies/ERC4626Strategy.sol";
import {IVaultAllocationStrategy} from "../src/interfaces/IVaultAllocationStrategy.sol";

import {createTestDAO} from "./mocks/MockDAO.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

contract VaultaireVaultForkTest is TestHelperOz5 {
    // Constants
    uint256 public constant USDC_INITIAL_ASSETS = 1000e6;
    uint256 public constant USDS_INITIAL_ASSETS = 1000e18;
    uint256 public constant INITIAL_MIN_VAULT_SHARE_BPS = 1000;
    uint32 public constant REDEMPTION_TIMELOCK = 1 days;

    // Test accounts
    address public deployer;
    address public user1;
    address public user2;
    address public operator;

    // Contracts
    DAO public dao;
    IERC20 public usdc = IERC20(address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913));
    IERC20 public usds = IERC20(address(0x820C137fa70C8691f0e44Dc420a5e53c168921Dc));
    ERC7575Share public share;
    uint32 public shareAEid = 1;
    uint32 public shareBEid = 2;
    VaultaireVault public usdcVault;
    VaultaireVault public usdsVault;
    ERC4626Strategy public usdcStrategy;
    ERC4626Strategy public usdsStrategy;
    IERC4626 public usdcLendingVault = IERC4626(address(0xbeeF010f9cb27031ad51e3333f9aF9C6B1228183));
    IERC4626 public usdsLendingVault = IERC4626(address(0x556d518FDFDCC4027A3A1388699c5E11AC201D8b));

    /* solhint-disable var-name-mixedcase */
    string public BASE_RPC_URL = vm.envString("BASE_RPC_URL");

    constructor() {
        setUpEndpoints(2, LibraryType.UltraLightNode);
        // Create test accounts
        deployer = makeAddr("deployer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        operator = makeAddr("operator");

        vm.createSelectFork(BASE_RPC_URL);

        vm.startPrank(deployer);
        dao = createTestDAO(deployer);
        address bridgeEndpoint = endpoints[shareAEid];
        share = ERC7575Share(_deployOApp(type(ERC7575Share).creationCode, abi.encode(bridgeEndpoint, address(dao))));

        // Deploying the vaults
        usdcVault = new VaultaireVault(
            IERC20(address(usdc)),
            share,
            dao,
            REDEMPTION_TIMELOCK,
            INITIAL_MIN_VAULT_SHARE_BPS,
            address(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B),
            0.97e18
        );
        usdsVault = new VaultaireVault(
            IERC20(address(usds)),
            share,
            dao,
            REDEMPTION_TIMELOCK,
            INITIAL_MIN_VAULT_SHARE_BPS,
            address(0x2330aaE3bca5F05169d5f4597964D44522F62930),
            0.97e18
        );

        // Setting the relationships
        usdcStrategy = new ERC4626Strategy(usdc, usdcVault, usdcLendingVault, dao);
        usdsStrategy = new ERC4626Strategy(usds, usdsVault, usdsLendingVault, dao);
        vm.startPrank(address(dao));
        usdcVault.setStrategy(IVaultAllocationStrategy(usdcStrategy));
        usdsVault.setStrategy(IVaultAllocationStrategy(usdsStrategy));
        vm.stopPrank();

        // Setting the permissions
        vm.startPrank(deployer);
        dao.grant(address(share), address(usdcVault), share.VAULT_ROLE());
        dao.grant(address(share), address(usdsVault), share.VAULT_ROLE());

        // Minting tokens
        deal(address(usdc), user1, USDC_INITIAL_ASSETS);
        deal(address(usdc), user2, USDC_INITIAL_ASSETS);

        deal(address(usds), user1, USDS_INITIAL_ASSETS);
        deal(address(usds), user2, USDS_INITIAL_ASSETS);
    }

    /// @dev Test if the vault is correctly configured after deployment
    function test_VaultInitialization() external view {
        assertEq(address(usdcVault.asset()), address(usdc), "Incorrect asset address");
        assertEq(address(usdcVault.share()), address(share), "Incorrect share address");
        assertEq(usdcVault.minTimelock(), REDEMPTION_TIMELOCK, "Incorrect timelock period");
    }

    /// @dev Test share token initialization and vault relationship
    function test_ShareTokenInitialization() external view {
        assertTrue(
            dao.hasPermission(address(share), address(usdcVault), share.VAULT_ROLE(), ""),
            "Vault doesn't have VAULT_ROLE"
        );
        assertEq(share.name(), "uUSD", "Incorrect share token name");
        assertEq(share.symbol(), "uUSD", "Incorrect share token symbol");
    }

    /// @dev Test basic deposit functionality
    function test_Deposit() external {
        uint256 depositAmount = 10e6;

        // User1 approves and deposits assets into the vault
        vm.startPrank(user1);
        usdc.approve(address(usdcVault), depositAmount);

        // Expect Deposit event to be emitted
        vm.expectEmit(true, true, false, true);
        emit IERC7575.Deposit(user1, user1, depositAmount, usdcVault.convertToShares(depositAmount));

        uint256 sharesMinted = usdcVault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Check balances after deposit
        assertEq(usdc.balanceOf(address(usdcVault)), depositAmount, "Vault didn't receive assets");
        assertEq(share.balanceOf(user1), sharesMinted, "User didn't receive shares");
        assertEq(
            sharesMinted,
            usdcVault.convertToShares(depositAmount),
            "Shares minted doesn't match deposit (1:1 ratio expected initially)"
        );
    }

    /// @dev Test basic deposit functionality
    function test_DepositOfTwoTokens() external {
        uint256 depositAmount = 10e6;

        // User1 approves and deposits assets into the vault
        vm.startPrank(user1);
        usdc.approve(address(usdcVault), depositAmount);

        // Expect Deposit event to be emitted
        vm.expectEmit(true, true, false, true);
        emit IERC7575.Deposit(user1, user1, depositAmount, usdcVault.convertToShares(depositAmount));

        uint256 sharesMinted = usdcVault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Check balances after deposit
        assertEq(usdc.balanceOf(address(usdcVault)), depositAmount, "Vault didn't receive assets");
        assertEq(share.balanceOf(user1), sharesMinted, "User didn't receive shares");
        assertEq(
            sharesMinted,
            usdcVault.convertToShares(depositAmount),
            "Shares minted doesn't match deposit (1:1 ratio expected initially)"
        );

        uint256 usdsDepositAmount = 10e18;

        // User1 approves and deposits assets into the vault
        vm.startPrank(user1);
        usds.approve(address(usdsVault), usdsDepositAmount);

        // Expect Deposit event to be emitted
        vm.expectEmit(true, true, false, true);
        emit IERC7575.Deposit(user1, user1, usdsDepositAmount, usdsVault.convertToShares(usdsDepositAmount));

        uint256 usdsSharesMinted = usdsVault.deposit(usdsDepositAmount, user1);
        vm.stopPrank();

        // Check balances after deposit
        assertEq(usds.balanceOf(address(usdsVault)), usdsDepositAmount, "Vault didn't receive assets");
        assertEq(share.balanceOf(user1), sharesMinted + usdsSharesMinted, "User didn't receive shares");
        assertEq(
            usdsSharesMinted,
            usdsVault.convertToShares(usdsDepositAmount),
            "Shares minted doesn't match deposit (1:1 ratio expected initially)"
        );
    }

    /// @dev Test redeem request functionality
    function test_RedeemRequest() external {
        // First deposit some assets
        uint256 depositAmount = 10e6;
        vm.startPrank(user1);
        usdc.approve(address(usdcVault), depositAmount);
        usdcVault.deposit(depositAmount, user1);

        // Request redemption of half the shares
        uint256 redeemAmount = depositAmount / 2;
        usdcVault.requestRedeem(redeemAmount, user1, user1);
        vm.stopPrank();

        // Verify pending redeem request
        assertEq(
            usdcVault.pendingRedeemRequest(0, user1),
            redeemAmount,
            "Pending redeem request not recorded correctly"
        );
        assertEq(usdcVault.claimableRedeemRequest(0, user1), 0, "Should not be claimable yet");

        // Fast forward time to make the redemption claimable
        vm.warp(block.timestamp + REDEMPTION_TIMELOCK + 1);

        // Verify claimable redeem request
        assertEq(usdcVault.pendingRedeemRequest(0, user1), 0, "Should not be pending anymore");
        assertEq(usdcVault.claimableRedeemRequest(0, user1), redeemAmount, "Should be claimable now");
    }

    /// @dev Test redeem request functionality
    function test_RedeemRequestWithTwoTokens() external {
        // First deposit some assets
        uint256 depositAmount = 10e6;
        vm.startPrank(user1);
        usdc.approve(address(usdcVault), depositAmount);
        usdcVault.deposit(depositAmount, user1);
        // Second deposit some assets
        uint256 usdsDepositAmount = 10e18;
        usds.approve(address(usdsVault), usdsDepositAmount);
        usdsVault.deposit(usdsDepositAmount, user1);

        // Request redemption of half the shares
        uint256 redeemAmount = depositAmount / 2;
        usdcVault.requestRedeem(redeemAmount, user1, user1);

        // Verify pending redeem request
        assertEq(
            usdcVault.pendingRedeemRequest(0, user1),
            redeemAmount,
            "Pending redeem request not recorded correctly"
        );
        assertEq(usdcVault.claimableRedeemRequest(0, user1), 0, "Should not be claimable yet");

        // Fast forward time to make the redemption claimable
        vm.warp(block.timestamp + REDEMPTION_TIMELOCK + 1);

        // Verify claimable redeem request
        assertEq(usdcVault.pendingRedeemRequest(0, user1), 0, "Should not be pending anymore");
        assertEq(usdcVault.claimableRedeemRequest(0, user1), redeemAmount, "Should be claimable now");

        // Redeeming last tokens
        // Request redemption of half the shares
        redeemAmount = usdsDepositAmount / 2;
        uint256 timelock = usdsVault.previewRedeemTimelock(redeemAmount);
        usdsVault.requestRedeem(redeemAmount, user1, user1);

        // Verify pending redeem request
        assertEq(
            usdsVault.pendingRedeemRequest(0, user1),
            redeemAmount,
            "Pending redeem request not recorded correctly"
        );
        assertEq(usdsVault.claimableRedeemRequest(0, user1), 0, "Should not be claimable yet");

        // Fast forward time to make the redemption claimable
        vm.warp(block.timestamp + timelock + 1);

        // Verify claimable redeem request
        assertEq(usdsVault.pendingRedeemRequest(0, user1), 0, "Should not be pending anymore");
        assertEq(usdsVault.claimableRedeemRequest(0, user1), redeemAmount, "Should be claimable now");
    }

    /// @dev Test redeem functionality after timelock
    function test_Redeem() external {
        // First deposit some assets
        uint256 usdcDeposit = 10e6;
        vm.startPrank(user1);
        usdc.approve(address(usdcVault), usdcDeposit);
        usdcVault.deposit(usdcDeposit, user1);

        assertEq(share.balanceOf(user1), (usdcDeposit * 1e12), "User's share balance not correctly updated");

        // Request redemption
        uint256 redeemAmount = 10e18 / 2;
        usdcVault.requestRedeem(redeemAmount, user1, user1);

        // Fast forward time to make the redemption claimable
        vm.warp(block.timestamp + REDEMPTION_TIMELOCK + 1);

        // Redeem the shares
        uint256 assetsReceived = usdcVault.redeem(redeemAmount, user1, user1);
        vm.stopPrank();

        // Check balances after redeem
        assertEq(
            usdc.balanceOf(user1),
            USDC_INITIAL_ASSETS - usdcDeposit + assetsReceived,
            "User didn't receive correct assets"
        );
        assertEq(
            share.balanceOf(user1),
            (usdcDeposit * 1e12) - redeemAmount,
            "User's share balance not correctly updated"
        );
        assertEq(
            assetsReceived * 1e12,
            redeemAmount,
            "Assets received doesn't match redeemed shares (1:1 ratio expected)"
        );
    }

    /// @dev Test basic deposit functionality
    function test_DepositWithInvestment() external {
        uint256 depositAmount = 10e6;

        vm.startPrank(address(dao));
        usdcVault.setInvestmentRatio(2000);
        vm.stopPrank();

        // User1 approves and deposits assets into the vault
        vm.startPrank(user1);
        usdc.approve(address(usdcVault), depositAmount);

        // Expect Deposit event to be emitted
        vm.expectEmit(true, true, false, true);
        emit IERC7575.Deposit(user1, user1, depositAmount, 10e18);

        uint256 sharesMinted = usdcVault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Check balances after deposit
        assertEq(usdc.balanceOf(address(usdcVault)), depositAmount - 2e6, "Vault didn't receive assets");
        assertEq(
            usdcLendingVault.balanceOf(address(usdcStrategy)),
            usdcLendingVault.convertToShares(2e6),
            "LendingVault didn't receive the correct amount"
        );
        assertEq(share.balanceOf(user1), sharesMinted, "User didn't receive shares");
        assertEq(sharesMinted, 10e18, "Shares minted doesn't match deposit (1:1 ratio expected initially)");
    }

    /// @dev Test basic deposit functionality
    function test_DepositTwoTokenWithInvestment() external {
        uint256 depositAmount = 10e6;

        vm.startPrank(address(dao));
        usdcVault.setInvestmentRatio(2000);
        vm.stopPrank();

        // User1 approves and deposits assets into the vault
        vm.startPrank(user1);
        usdc.approve(address(usdcVault), depositAmount);

        // Expect Deposit event to be emitted
        vm.expectEmit(true, true, false, true);
        emit IERC7575.Deposit(user1, user1, depositAmount, 10e18);

        uint256 sharesMinted = usdcVault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Check balances after deposit
        assertEq(usdc.balanceOf(address(usdcVault)), depositAmount - 2e6, "Vault didn't receive assets");
        assertEq(
            usdcLendingVault.balanceOf(address(usdcStrategy)),
            usdcLendingVault.convertToShares(2e6),
            "LendingVault didn't receive the correct amount"
        );
        assertEq(share.balanceOf(user1), sharesMinted, "User didn't receive shares");
        assertEq(sharesMinted, 10e18, "Shares minted doesn't match deposit (1:1 ratio expected initially)");

        // USDS
        uint256 usdsDeposit = 10e18;

        vm.startPrank(address(dao));
        usdsVault.setInvestmentRatio(2000);
        vm.stopPrank();

        // User1 approves and deposits assets into the vault
        vm.startPrank(user1);
        usds.approve(address(usdsVault), usdsDeposit);

        // Expect Deposit event to be emitted
        vm.expectEmit(true, true, false, true);
        emit IERC7575.Deposit(user1, user1, usdsDeposit, 10e18);

        uint256 usdsSharesMinted = usdsVault.deposit(usdsDeposit, user1);
        vm.stopPrank();

        // Check balances after deposit
        assertEq(usds.balanceOf(address(usdsVault)), usdsDeposit - 2e18, "Vault didn't receive assets");
        assertEq(
            usdsLendingVault.balanceOf(address(usdsStrategy)),
            usdsLendingVault.convertToShares(2e18),
            "LendingVault didn't receive the correct amount"
        );
        assertEq(share.balanceOf(user1), usdsSharesMinted + sharesMinted, "User didn't receive shares");
        assertEq(usdsSharesMinted, 10e18, "Shares minted doesn't match deposit (1:1 ratio expected initially)");
    }

    /// @dev Test basic deposit functionality
    function test_RequestRedeemWithInvestment() external {
        uint256 depositAmount = 10e6;

        vm.startPrank(address(dao));
        usdcVault.setInvestmentRatio(2000);
        vm.stopPrank();

        // User1 approves and deposits assets into the vault
        vm.startPrank(user1);
        usdc.approve(address(usdcVault), depositAmount);

        // Expect Deposit event to be emitted
        vm.expectEmit(true, true, false, true);
        emit IERC7575.Deposit(user1, user1, depositAmount, 10e18);

        uint256 sharesMinted = usdcVault.deposit(depositAmount, user1);

        // Check balances after deposit
        assertEq(usdc.balanceOf(address(usdcVault)), depositAmount - 2e6, "Vault didn't receive assets");
        assertEq(
            usdcLendingVault.balanceOf(address(usdcStrategy)),
            usdcLendingVault.convertToShares(2e6),
            "LendingVault didn't receive the correct amount"
        );
        assertEq(share.balanceOf(user1), sharesMinted, "User didn't receive shares");
        assertEq(sharesMinted, 10e18, "Shares minted doesn't match deposit (1:1 ratio expected initially)");

        // Request redemption of half the shares
        uint256 redeemAmount = depositAmount / 2;
        usdcVault.requestRedeem(redeemAmount, user1, user1);

        // Verify pending redeem request
        assertEq(share.balanceOf(user1), 10e18 - redeemAmount, "User didn't send their shares");
        assertEq(usdc.balanceOf(address(usdcVault)), 8e6, "USDC Vault doesn't hold complete amount minus invested");
        assertEq(
            usdcVault.pendingRedeemRequest(0, user1),
            redeemAmount,
            "Pending redeem request not recorded correctly"
        );
        assertEq(usdcVault.claimableRedeemRequest(0, user1), 0, "Should not be claimable yet");
        assertEq(
            usdcLendingVault.balanceOf(address(usdcStrategy)),
            usdcLendingVault.convertToShares(2e18) / 1e12, // Dividing by 1e12 to convert to same units
            "Strategy should hold 20% of the supply"
        );

        // Fast forward time to make the redemption claimable
        vm.warp(block.timestamp + REDEMPTION_TIMELOCK + 1);

        // Verify claimable redeem request
        assertEq(usdcVault.pendingRedeemRequest(0, user1), 0, "Should not be pending anymore");
        assertEq(usdcVault.claimableRedeemRequest(0, user1), redeemAmount, "Should be claimable now");
    }

    /// @dev Test basic deposit functionality
    function test_RedeemWithInvestment() external {
        uint256 depositAmount = 10e6;

        vm.startPrank(address(dao));
        usdcVault.setInvestmentRatio(2000);
        vm.stopPrank();

        // User1 approves and deposits assets into the vault
        vm.startPrank(user1);
        usdc.approve(address(usdcVault), depositAmount);

        // Expect Deposit event to be emitted
        vm.expectEmit(true, true, false, true);
        emit IERC7575.Deposit(user1, user1, depositAmount, 10e18);

        uint256 sharesMinted = usdcVault.deposit(depositAmount, user1);

        // Check balances after deposit
        assertEq(usdc.balanceOf(address(usdcVault)), depositAmount - 2e6, "Vault didn't receive assets");
        assertEq(
            usdcLendingVault.balanceOf(address(usdcStrategy)),
            usdcLendingVault.convertToShares(2e6),
            "LendingVault didn't receive the correct amount"
        );
        assertEq(share.balanceOf(user1), sharesMinted, "User didn't receive shares");
        assertEq(sharesMinted, 10e18, "Shares minted doesn't match deposit (1:1 ratio expected initially)");

        // Request redemption of half the shares
        uint256 redeemAmount = usdcVault.convertToShares(5e6);
        usdcVault.requestRedeem(redeemAmount, user1, user1);

        // Verify pending redeem request
        assertEq(
            usdcVault.pendingRedeemRequest(0, user1),
            redeemAmount,
            "Pending redeem request not recorded correctly"
        );
        assertEq(usdcVault.claimableRedeemRequest(0, user1), 0, "Should not be claimable yet");

        // Fast forward time to make the redemption claimable
        vm.warp(block.timestamp + REDEMPTION_TIMELOCK + 1);

        // Verify claimable redeem request
        assertEq(usdcVault.pendingRedeemRequest(0, user1), 0, "Should not be pending anymore");
        assertEq(usdcVault.claimableRedeemRequest(0, user1), redeemAmount, "Should be claimable now");

        // Redeem the shares
        uint256 assetsReceived = usdcVault.redeem(redeemAmount, user1, user1);
        vm.stopPrank();

        // Check balances after redeem
        assertEq(assetsReceived, 5e6, "User didn't receive correct assets");
        assertEq(
            usdc.balanceOf(user1),
            USDC_INITIAL_ASSETS - depositAmount + assetsReceived,
            "User didn't receive correct assets"
        );
        assertEq(
            share.balanceOf(user1),
            (depositAmount * 1e12) - redeemAmount,
            "User's share balance not correctly updated"
        );

        assertEq(usdc.balanceOf(address(usdcVault)), 4e6, "Vault shouldn't be drained");

        // Weird test due to precision loss
        assertTrue(
            usdcLendingVault.maxWithdraw(address(usdcStrategy)) > 0.999e6,
            "Strategy should still have 20% of total deposited"
        );
        assertTrue(
            usdcLendingVault.maxWithdraw(address(usdcStrategy)) < 1.001e6,
            "Strategy should still have 20% of total deposited"
        );
    }
}
