// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC7540Redeem } from "../interfaces/IERC7540.sol";
import { VaultOperator } from "./VaultOperator.sol";
import { VaultCore } from "./VaultCore.sol";

/**
 * @title VaultaireRedeem
 * @dev Implementation of redemption functionality with timelock
 */
abstract contract VaultRedeem is IERC7540Redeem, VaultCore, VaultOperator {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @dev Constant request ID used for all redemption requests
    uint256 internal constant REQUEST_ID = 0;

    /// @dev Minimum timelock duration in seconds for redemption requests
    uint32 public minTimelock;

    /// @dev Total assets currently pending redemption
    uint256 internal _totalPendingRedeemAssets;

    /// @dev Mapping of controllers to their redemption requests
    mapping(address controller => RedemptionRequest request) internal _pendingRedemption;

    struct RedemptionRequest {
        uint256 assets;
        uint256 shares;
        uint32 claimableTimestamp;
    }

    /**
     * @dev Error thrown when a caller is neither the owner nor an authorized operator of the owner.
     */
    error InvalidOwner(address caller, address owner);

    /**
     * @dev Error thrown when attempting to claim zero assets or shares.
     */
    error ZeroAmountClaim();

    /**
     * @dev Error thrown when attempting to redeem more shares than the owner has available.
     */
    error InsufficientRedeemableBalance(address owner, uint256 requested, uint256 available);

    constructor(uint32 _minTimelock) {
        minTimelock = _minTimelock;
    }

    // @inheritdoc VaultaireCore
    function totalAssets() public view virtual override returns (uint256 totalManagedAssets) {
        return _asset.balanceOf(address(this));
    }

    // @inheritdoc IERC7575
    function maxRedeem(address controller) public view override returns (uint256) {
        RedemptionRequest memory request = _pendingRedemption[controller];
        if (request.claimableTimestamp <= block.timestamp) return request.shares;
        return 0;
    }

    // @inheritdoc IERC7575
    function maxWithdraw(address controller) public view override returns (uint256) {
        RedemptionRequest memory request = _pendingRedemption[controller];
        if (request.claimableTimestamp <= block.timestamp) return request.assets;
        return 0;
    }

    // @inheritdoc IERC7575
    function withdraw(uint256 assets, address receiver, address controller) public virtual override returns (uint256) {
        if (controller != msg.sender && !isOperator[controller][msg.sender]) {
            revert InvalidCaller(msg.sender, controller);
        }

        if (assets == 0) revert ZeroAmountClaim();

        uint256 maxAssets = maxWithdraw(controller);
        if (assets > maxAssets) revert ExceededMaxWithdraw(controller, assets, maxAssets);

        RedemptionRequest storage request = _pendingRedemption[controller];

        // Claiming partially introduces precision loss. The user therefore receives a rounded down amount,
        // while the claimable balance is reduced by a rounded up amount.
        uint256 shares = assets.mulDiv(request.shares, request.assets, Math.Rounding.Floor);
        uint256 sharesUp = assets.mulDiv(request.shares, request.assets, Math.Rounding.Ceil);
        request.assets -= assets;
        request.shares = request.shares > sharesUp ? request.shares - sharesUp : 0;

        _beforeWithdraw(assets);

        _withdraw(_msgSender(), receiver, controller, assets, shares);

        return shares;
    }

    // @inheritdoc IERC7575
    function redeem(uint256 shares, address receiver, address controller) public virtual override returns (uint256) {
        if (controller != msg.sender && !isOperator[controller][msg.sender]) {
            revert InvalidCaller(msg.sender, controller);
        }

        if (shares == 0) revert ZeroAmountClaim();

        uint256 maxShares = maxRedeem(controller);
        if (shares > maxShares) revert ExceededMaxRedeem(controller, shares, maxShares);

        RedemptionRequest storage request = _pendingRedemption[controller];

        uint256 assets = shares.mulDiv(request.assets, request.shares, Math.Rounding.Floor);
        uint256 assetsUp = shares.mulDiv(request.assets, request.shares, Math.Rounding.Ceil);

        request.assets = request.assets > assetsUp ? request.assets - assetsUp : 0;
        request.shares -= shares;

        _withdraw(_msgSender(), receiver, controller, assets, shares);

        return assets;
    }

    /// @notice Preview the timelock duration for a redemption request
    /// @param shares Amount of shares to be redeemed
    /// @return Total timelock duration in seconds (base + additional)
    function previewRedeemTimelock(uint256 shares) public view returns (uint32) {
        uint256 globalTotalShares = _share.totalSupply(); // Total across all vaults
        uint256 vaultInternalShares = internalShares; // Internal share count for this vault

        // Prevent underflows
        if (shares > vaultInternalShares || shares > globalTotalShares) {
            return type(uint32).max; // Or revert with "Invalid redemption amount"
        }

        // Simulate state after redemption
        uint256 newVaultInternalShares = vaultInternalShares - shares;
        uint256 newGlobalTotalShares = globalTotalShares - shares;

        // Avoid division by zero
        uint256 vaultShareBpsAfterRedemption =
            newGlobalTotalShares == 0 ? 0 : (newVaultInternalShares * 10_000) / newGlobalTotalShares;

        // If vault remains healthy, return base timelock
        if (vaultShareBpsAfterRedemption >= minVaultShareBps) {
            return minTimelock;
        }

        // Penalty calculation (exponential scaling)
        uint256 bpsDifference = minVaultShareBps - vaultShareBpsAfterRedemption;
        uint256 percentageBelow = (bpsDifference * 100) / minVaultShareBps;
        uint256 exponentialFactor = percentageBelow * percentageBelow;

        return minTimelock + uint32((minTimelock * exponentialFactor) / 100);
    }

    /**
     * @dev Withdrawal implementation used by both withdraw and redeem
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    )
        internal
        virtual
    {
        _totalPendingRedeemAssets -= assets;
        SafeERC20.safeTransfer(_asset, receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    // @inheritdoc IERC7540Redeem
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    )
        external
        override
        returns (uint256 requestId)
    {
        if (owner != msg.sender && !isOperator[owner][msg.sender]) revert InvalidOwner(msg.sender, owner);

        uint256 available = _share.balanceOf(owner);
        if (available < shares) revert InsufficientRedeemableBalance(owner, shares, available);
        if (shares == 0) revert ZeroAmountClaim();

        uint256 assets = _convertToAssets(shares, Math.Rounding.Floor);

        uint32 totalTimelock = previewRedeemTimelock(shares);

        _share.burn(owner, shares);
        internalShares -= shares;
        internalAssets -= assets;

        RedemptionRequest storage request = _pendingRedemption[controller];

        // Calculate total timelock including additional time based on vault state

        // If there's an existing request, we update it and reset timelock
        if (request.shares > 0) {
            request.assets += assets;
            request.shares += shares;
            // Reset timelock with new calculated total
            request.claimableTimestamp = uint32(block.timestamp) + totalTimelock;
        } else {
            _pendingRedemption[controller] = RedemptionRequest({
                assets: assets,
                shares: shares,
                claimableTimestamp: uint32(block.timestamp) + totalTimelock
            });
        }

        _totalPendingRedeemAssets += assets;

        emit RedeemRequest(controller, owner, REQUEST_ID, msg.sender, shares);
        return REQUEST_ID;
    }

    // @inheritdoc IERC7540Redeem
    function pendingRedeemRequest(uint256, address controller) public view override returns (uint256 pendingShares) {
        RedemptionRequest memory request = _pendingRedemption[controller];
        if (request.claimableTimestamp > block.timestamp) {
            return request.shares;
        }
        return 0;
    }

    // @inheritdoc IERC7540Redeem
    function claimableRedeemRequest(
        uint256,
        address controller
    )
        public
        view
        override
        returns (uint256 claimableShares)
    {
        RedemptionRequest memory request = _pendingRedemption[controller];
        if (request.claimableTimestamp <= block.timestamp && request.shares > 0) {
            return request.shares;
        }
        return 0;
    }

    /**
     * @dev Returns detailed information about a pending redemption request
     */
    function pendingRedeemRequestData(address controller) public view returns (RedemptionRequest memory) {
        RedemptionRequest memory request = _pendingRedemption[controller];
        if (request.claimableTimestamp <= block.timestamp) {
            revert ZeroAmountClaim();
        }
        return request;
    }

    /**
     * @dev Returns detailed information about a claimable redemption request
     */
    function claimableRedeemRequestData(address controller) public view returns (RedemptionRequest memory) {
        RedemptionRequest memory request = _pendingRedemption[controller];
        if (request.claimableTimestamp > block.timestamp || request.shares <= 0) {
            revert ZeroAmountClaim();
        }
        return request;
    }

    /**
     * @dev Sets the timelock duration for redemption requests
     */
    function setMinTimelock(uint32 minTimelock_) public virtual {
        if (msg.sender == address(dao())) {
            minTimelock = minTimelock_;
        }
    }

    /**
     * @dev Hook that is called before withdrawing assets from the vault.
     *
     * @param assets The amount of assets withdrawing.
     */
    function _beforeWithdraw(uint256 assets) internal {
        // Custom logic before withdrawal
        _deallocate(assets);
    }
}
