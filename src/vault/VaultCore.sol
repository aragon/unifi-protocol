// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import { IDAO } from "@aragon/commons/dao/IDAO.sol";
import { SingleStrategyManager } from "./SingleStrategyManager.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC7575 } from "../interfaces/IERC7575.sol";
import { ERC7575Share } from "../ERC7575Share.sol";

/**
 * @title VaultaireCore
 * @dev Core implementation of ERC7575 vault functionality
 */
abstract contract VaultCore is IERC7575, SingleStrategyManager {
    using Math for uint256;

    ERC7575Share internal immutable _share;
    IERC20 internal immutable _asset;
    uint256 public minVaultShareBps; // 10_000 -> 100%

    uint256 internal internalShares = 0;
    uint256 internal internalAssets = 0;

    /**
     * @dev Emitted when the minimum vault share basis points are updated.
     */
    event MinVaultShareBpsUpdated(uint256 minVaultShareBps);

    /**
     * @dev Attempted to deposit more assets than the max amount for `receiver`.
     */
    error ExceededMaxDeposit(address receiver, uint256 assets, uint256 max);

    /**
     * @dev Attempted to mint more shares than the max amount for `receiver`.
     */
    error ExceededMaxMint(address receiver, uint256 shares, uint256 max);

    /**
     * @dev Attempted to withdraw more assets than the max amount for `receiver`.
     */
    error ExceededMaxWithdraw(address owner, uint256 assets, uint256 max);

    /**
     * @dev Attempted to redeem more shares than the max amount for `receiver`.
     */
    error ExceededMaxRedeem(address owner, uint256 shares, uint256 max);

    /**
     * @dev Error thrown when trying to preview a withdraw or redeem operation in an asynchronous vault.
     */
    error SyncFlowNotSupported();

    /**
     * @dev Error thrown when a spender attempts to transfer more shares than their current allowance permits.
     */
    error InsufficientShareAllowance(address spender, uint256 currentAllowance, uint256 value);

    constructor(IERC20 asset_, ERC7575Share share_, IDAO _dao, uint256 _minVaultShareBps) SingleStrategyManager(_dao) {
        _asset = asset_;
        _share = share_;
        minVaultShareBps = _minVaultShareBps;
    }

    // @inheritdoc IERC7575
    function asset() public view override(IERC7575, SingleStrategyManager) returns (address assetTokenAddress) {
        return address(_asset);
    }

    // @inheritdoc IERC7575
    function share() external view override returns (address shareTokenAddress) {
        return address(_share);
    }

    function setMinVaultShareBps(uint256 _minVaultShareBps) external {
        if (msg.sender != address(dao())) revert OnlyDAOAllowed(msg.sender, address(dao()));

        minVaultShareBps = _minVaultShareBps;

        emit MinVaultShareBpsUpdated(_minVaultShareBps);
    }

    function getCurrentVaultShareBps() public view returns (uint256) {
        uint256 total = _share.totalSupply();
        if (internalShares == 0) return 0; // avoid division by zero
        return (total * 10_000) / internalShares;
    }

    // @inheritdoc IERC7575
    function totalAssets() public view virtual override returns (uint256 totalManagedAssets) {
        return _asset.balanceOf(address(this));
    }

    // @inheritdoc IERC7575
    function totalInternalShares() public view virtual returns (uint256 totalManagedAssets) {
        return internalShares;
    }

    // @inheritdoc IERC7575
    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    // @inheritdoc IERC7575
    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    // @inheritdoc IERC7575
    function maxDeposit(address) public pure virtual returns (uint256 maxAssets) {
        return type(uint256).max;
    }

    // @inheritdoc IERC7575
    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    // @inheritdoc IERC7575
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    // @inheritdoc IERC7575
    function previewMint(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Ceil);
    }

    // @inheritdoc IERC7575
    function previewWithdraw(uint256) public view virtual returns (uint256) {
        revert SyncFlowNotSupported();
    }

    // @inheritdoc IERC7575
    function previewRedeem(uint256) public view virtual returns (uint256) {
        revert SyncFlowNotSupported();
    }

    // @inheritdoc IERC7575
    function deposit(uint256 assets, address receiver) external virtual override returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) revert ExceededMaxDeposit(receiver, assets, maxAssets);

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        _afterDeposit(assets);
        return shares;
    }

    // @inheritdoc IERC7575
    function mint(uint256 shares, address receiver) public virtual returns (uint256) {
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) revert ExceededMaxMint(receiver, shares, maxShares);

        uint256 assets = previewMint(shares);
        _deposit(_msgSender(), receiver, assets, shares);

        _afterDeposit(previewMint(shares));
        return assets;
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual returns (uint256);

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual returns (uint256);

    function _decimalsOffset() internal view virtual returns (uint8) {
        return 0;
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual {
        // If asset() is ERC-777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        internalShares += shares;
        internalAssets += assets;
        SafeERC20.safeTransferFrom(_asset, caller, address(this), assets);
        _share.mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Hook that is called after depositing assets into the vault.
     *
     * @param assets The amount of assets deposited.
     */
    function _afterDeposit(uint256 assets) internal {
        _allocate(assets);
    }

    /**
     * @dev Updates `owner`'s allowance for `spender` based on spent `value`.
     *
     * Does not update the allowance value in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Does not emit an {Approval} event.
     */
    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = _share.allowance(owner, spender);
        if (currentAllowance < type(uint256).max) {
            if (currentAllowance < value) {
                revert InsufficientShareAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _share.setInternalApproves(owner, spender, currentAllowance - value);
            }
        }
    }
}
