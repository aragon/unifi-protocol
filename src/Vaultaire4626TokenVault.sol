// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC7575Share } from "./ERC7575Share.sol";
import { IERC7575 } from "./interfaces/IERC7575.sol";
import { IERC7540Operator } from "./interfaces/IERC7540.sol";

import { VaultCore } from "./vault/VaultCore.sol";
import { VaultAuth } from "./vault/VaultOperatorAuth.sol";
import { VaultRedeem } from "./vault/VaultRedeem.sol";

/**
 * @title VaultaireVault
 * @dev Main vault contract that combines all components
 */
contract Vaultaire4626TokenVault is VaultAuth, VaultRedeem {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /**
     * @dev Event emitted when the strategy harvests yield.
     */
    event StrategyHarvest(uint256 yield);

    /**
     * @dev Constructor for VaultaireVault
     * @param asset_ The underlying asset token
     * @param share_ The share token
     * @param _dao The DAO address for authorization
     * @param _timelock The timelock duration for redemption requests
     */
    constructor(
        IERC20 asset_,
        ERC7575Share share_,
        IDAO _dao,
        uint32 _timelock,
        uint256 _minVaultShareBps
    )
        VaultCore(asset_, share_, _dao, _minVaultShareBps)
        VaultAuth("VaultaireVault", "1")
        VaultRedeem(_timelock)
    {
        // Constructor logic is handled by parent contracts
    }

    function totalAssets() public view override returns (uint256 totalManagedAssets) {
        return _asset.balanceOf(address(this)) + currentlyInvested;
    }

    /**
     * @dev Implementation of ERC-165 interface detection
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC7540Operator).interfaceId || interfaceId == type(IERC7575).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @dev Override _convertToShares to account for pending redemptions
     */
    function _convertToShares(uint256 assets, Math.Rounding) internal view override returns (uint256) {
        return ERC4626(address(_asset)).convertToShares(assets);
    }

    /**
     * @dev Override _convertToShares to account for pending redemptions
     */
    function _convertToAssets(uint256 shares, Math.Rounding) internal view override returns (uint256) {
        return ERC4626(address(_asset)).convertToAssets(shares);
    }

    function calculateYield() public view returns (uint256 yield) {
        uint256 totalAssetsNow = ERC4626(address(_asset)).maxWithdraw(address(this));
        return totalAssetsNow > internalAssets ? totalAssetsNow - internalAssets : 0;
    }

    /**
     * @notice Harvests yield on the active strategy.
     */
    function harvest() external override {
        uint256 yield = calculateYield();
        if (yield == 0) return;

        _asset.safeTransfer(address(dao()), yield);

        emit StrategyHarvest(yield);
    }
}
