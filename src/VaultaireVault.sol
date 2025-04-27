// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC7575Share} from "./ERC7575Share.sol";
import {IERC7575} from "./interfaces/IERC7575.sol";
import {IERC7540Operator} from "./interfaces/IERC7540.sol";

import {VaultCore} from "./vault/VaultCore.sol";
import {VaultAuth} from "./vault/VaultOperatorAuth.sol";
import {VaultRedeem} from "./vault/VaultRedeem.sol";
import {SingleStrategyManager} from "./vault/SingleStrategyManager.sol";
import {VaultDefaultChecker} from "./vault/VaultDefaultChecker.sol";

/**
 * @title VaultaireVault
 * @dev Main vault contract that combines all components
 */
contract VaultaireVault is VaultAuth, VaultRedeem {
    using Math for uint256;

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
        uint256 _minVaultShareBps,
        address _priceFeed,
        int256 _minDefaultPriceThreshold
    )
        VaultCore(asset_, share_, _minVaultShareBps)
        VaultAuth("VaultaireVault", "1")
        VaultRedeem(_timelock)
        SingleStrategyManager(_dao)
        VaultDefaultChecker(_priceFeed, _minDefaultPriceThreshold)
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
        return
            interfaceId == type(IERC7540Operator).interfaceId ||
            interfaceId == type(IERC7575).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @dev Override _convertToShares to account for pending redemptions
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256) {
        return
            assets.mulDiv(
                totalInternalShares() + 10 ** _decimalsOffset(),
                totalAssets() - _totalPendingRedeemAssets + 1,
                rounding
            );
    }

    /**
     * @dev Override _convertToShares to account for pending redemptions
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256) {
        return
            shares.mulDiv(
                totalAssets() - _totalPendingRedeemAssets + 1,
                totalInternalShares() + 10 ** _decimalsOffset(),
                rounding
            );
    }
}
