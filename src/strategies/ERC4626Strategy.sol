// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";
import { BaseVaultAllocationStrategy } from "./BaseVaultAllocationStrategy.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { VaultaireVault } from "../VaultaireVault.sol";

/**
 * @title ERC4626Strategy
 * @dev Strategy for allocating assets to an ERC4626-compatible vault.
 * Tracks principal vs. yield and handles deposits/withdrawals.
 */
contract ERC4626Strategy is BaseVaultAllocationStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // The target ERC4626 vault where assets are invested
    IERC4626 public targetVault;

    // Total shares owned in the target vault
    uint256 public totalShares;

    /**
     * @dev Event emitted when the strategy harvests yield.
     */
    event StrategyHarvest(uint256 yield);

    /**
     * @dev Error thrown when there's a mismatch between the target vault's asset and this strategy's asset.
     */
    error AssetMismatch(IERC20 expectedAsset, address actualAsset);

    /**
     * @dev Error thrown when harvest operation fails.
     */
    error HarvestFailed();

    error ReceivedFewerShares(uint256 received, uint256 expected);
    error OnlyDaoCanTriggerEmergencyExit(address caller, address dao);

    constructor(
        IERC20 _underlyingAsset,
        VaultaireVault _vaultaireVault,
        IERC4626 _targetVault,
        IDAO _dao
    )
        BaseVaultAllocationStrategy(_underlyingAsset, _vaultaireVault, _dao)
    {
        targetVault = IERC4626(_targetVault);

        // Verify the target vault uses the same asset
        if (targetVault.asset() != address(_underlyingAsset)) {
            revert AssetMismatch(_underlyingAsset, targetVault.asset());
        }
    }

    /**
     * @notice Invests assets into the target ERC4626 vault.
     * @param assets Amount of assets to invest.
     * @return shares Amount of shares minted by the target vault.
     */
    function invest(uint256 assets) external override onlyVault returns (uint256 shares) {
        if (assets == 0) return 0;

        _beforeInvest(assets);

        // Ensure we have allowance to the target vault
        underlyingAsset.approve(address(targetVault), assets);

        // Get assets from the vault
        underlyingAsset.safeTransferFrom(address(vaultaireVault), address(this), assets);

        // Deposit assets into the target vault
        // Calculate expected shares - we can compare later for extra safety
        uint256 expectedShares = targetVault.previewDeposit(assets);

        // Perform the deposit
        shares = targetVault.deposit(assets, address(this));

        // Sanity check - received at least the expected shares
        if (shares < expectedShares) {
            revert ReceivedFewerShares(shares, expectedShares);
        }

        // Update accounting
        totalPrincipal += assets;
        totalShares += shares;

        _afterInvest(assets, shares);

        emit StrategyInvest(assets);

        return shares;
    }

    /**
     * @notice Divests assets from the target ERC4626 vault.
     * @param assets Amount of assets to divest.
     * @return actualDivested The actual amount divested.
     */
    function divest(uint256 assets) external override onlyVault returns (uint256 actualDivested) {
        if (assets == 0) return 0;

        uint256 managedAssets = totalManagedAssets();
        if (managedAssets == 0) return 0;

        // Cap the withdrawal to what we actually have
        uint256 actualAssets = assets > managedAssets ? managedAssets : assets;

        _beforeDivest(actualAssets);

        // Calculate how many shares we need to redeem
        uint256 sharesToRedeem = totalShares.mulDiv(
            actualAssets,
            managedAssets,
            Math.Rounding.Ceil // Round up to ensure we get at least the requested assets
        );

        // Cap to available shares
        sharesToRedeem = sharesToRedeem > totalShares ? totalShares : sharesToRedeem;

        if (sharesToRedeem == 0) return 0;

        // Perform the withdrawal
        actualDivested = targetVault.redeem(
            sharesToRedeem,
            address(vaultaireVault), // Send directly to the vault
            address(this) // Owner of the shares
        );

        // Update accounting
        // Reduce principal proportionally to assets withdrawn
        uint256 principalReduction = totalPrincipal.mulDiv(actualDivested, managedAssets, Math.Rounding.Ceil);

        totalPrincipal = principalReduction > totalPrincipal ? 0 : totalPrincipal - principalReduction;
        totalShares -= sharesToRedeem;

        _afterDivest(assets, actualDivested);

        emit StrategyDivest(actualDivested);

        return actualDivested;
    }

    /**
     * @notice Harvests any yield generated by the strategy.
     * @dev In this implementation, harvesting does move funds
     */
    function harvest() external override onlyVault {
        uint256 yield = calculateYield();
        if (yield == 0) return;

        // // Perform the withdrawal and send to the DAO
        uint256 actualRedeemed = targetVault.redeem(
            yield,
            address(vaultaireVault.dao()), // Send directly to the vault
            address(this) // Owner of the shares
        );

        // 4. Emit event
        emit StrategyHarvest(actualRedeemed);
    }

    /**
     * @notice Calculates the yield generated by the strategy.
     * @return Yield amount.
     */
    function calculateYield() public view returns (uint256) {
        return targetVault.maxWithdraw(address(this)) - totalPrincipal;
    }

    /**
     * @notice Returns the total assets currently managed by this strategy.
     * @return Total assets including principal and yield.
     */
    function totalManagedAssets() public view override returns (uint256) {
        if (totalShares == 0) return 0;

        // Convert our shares to their current asset value
        return targetVault.previewRedeem(totalShares);
    }

    /**
     * @notice Allows the DAO to perform an emergency exit, withdrawing all assets.
     * @dev Can only be called by the DAO.
     */
    function emergencyExit() external {
        if (msg.sender != address(dao())) {
            revert OnlyDaoCanTriggerEmergencyExit(msg.sender, address(dao()));
        }

        uint256 sharesToRedeem = totalShares;
        if (sharesToRedeem == 0) return;

        // Withdraw everything and send to the vault
        uint256 withdrawn = targetVault.redeem(sharesToRedeem, address(vaultaireVault), address(this));

        // Reset accounting
        totalPrincipal = 0;
        totalShares = 0;

        emit StrategyDivest(withdrawn);
    }
}
