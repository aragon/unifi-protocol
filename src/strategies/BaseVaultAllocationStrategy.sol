// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVaultAllocationStrategy } from "../interfaces/IVaultAllocationStrategy.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";
import { DaoAuthorizable } from "@aragon/commons/permission/auth/DaoAuthorizable.sol";
import { VaultaireVault } from "../VaultaireVault.sol";

/**
 * @title BaseVaultAllocationStrategy
 * @dev Abstract base class for vault allocation strategies.
 * Provides common functionality like tracking principal vs yield.
 */
abstract contract BaseVaultAllocationStrategy is IVaultAllocationStrategy, DaoAuthorizable {
    using SafeERC20 for IERC20;

    // The underlying asset this strategy manages
    IERC20 public underlyingAsset;

    // The Vaultaire vault that owns this strategy
    VaultaireVault public vaultaireVault;

    // Total principal (excluding yield)
    uint256 public totalPrincipal;

    /**
     * @dev Error thrown when only the vault should be able to call a function.
     */
    error OnlyVaultAllowed(address caller, VaultaireVault vault);

    /**
     * @dev Error thrown when a transfer fails.
     */
    error TransferFailed();

    /**
     * @dev Modifier to restrict function calls to the vault only.
     */
    modifier onlyVault() {
        if (msg.sender != address(vaultaireVault)) {
            revert OnlyVaultAllowed(msg.sender, vaultaireVault);
        }
        _;
    }

    constructor(IERC20 _underlyingAsset, VaultaireVault _vaultaireVault, IDAO _dao) DaoAuthorizable(_dao) {
        underlyingAsset = _underlyingAsset;
        vaultaireVault = _vaultaireVault;
    }

    /**
     * @notice Returns the address of the underlying asset.
     */
    function asset() external view override returns (address) {
        return address(underlyingAsset);
    }

    /**
     * @notice Returns the total yield generated (totalManagedAssets - totalPrincipal).
     */
    function totalYield() external view override returns (uint256) {
        uint256 total = totalManagedAssets();
        return total > totalPrincipal ? total - totalPrincipal : 0;
    }

    /**
     * @notice The total value of assets managed by this strategy, including yield.
     * @dev Must be implemented by concrete strategy classes.
     */
    function totalManagedAssets() public view virtual override returns (uint256);

    /**
     * @notice Hook called before investing assets. May be used for pre-investment operations.
     * @param amount Amount of assets being invested
     */
    // solhint-disable-next-line no-empty-blocks
    function _beforeInvest(uint256 amount) internal virtual {
        // Intentionally left blank
    }

    /**
     * @notice Hook called after investing assets. May be used for post-investment operations.
     * @param amount Amount of assets invested
     * @param shares Amount of shares received
     */
    // solhint-disable-next-line no-empty-blocks
    function _afterInvest(uint256 amount, uint256 shares) internal virtual {
        // Intentionally left blank
    }

    /**
     * @notice Hook called before divesting assets. May be used for pre-divestment operations.
     * @param amount Amount of assets being divested
     */
    // solhint-disable-next-line no-empty-blocks
    function _beforeDivest(uint256 amount) internal virtual {
        // Intentionally left blank
    }

    /**
     * @notice Hook called after divesting assets. May be used for post-divestment operations.
     * @param amount Amount of assets requested to divest
     * @param actualDivested Actual amount divested
     */
    // solhint-disable-next-line no-empty-blocks
    function _afterDivest(uint256 amount, uint256 actualDivested) internal virtual {
        // Intentionally left blank
    }
}
