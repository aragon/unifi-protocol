// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {DaoAuthorizable} from "@aragon/commons/permission/auth/DaoAuthorizable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IERC7575} from "./interfaces/IERC7575.sol";
import {IERC7540Operator, IERC7540Redeem} from "./interfaces/IERC7540.sol";
import {ERC7575Share} from "./ERC7575Share.sol";

contract VaultaireVault is IERC7575, DaoAuthorizable, IERC7540Operator, IERC7540Redeem, EIP712 {
    using Math for uint256;

    ERC7575Share internal immutable _share;
    IERC20 internal immutable _asset;

    uint256 internal internalShares = 0;

    /// IERC7540Operator Storage
    /// @dev Assume requests are non-fungible and all have ID = 0
    uint256 internal constant REQUEST_ID = 0;
    mapping(address => mapping(address => bool)) public isOperator;
    mapping(address controller => mapping(bytes32 nonce => bool used)) public authorizations;

    /// IERC7540Redeem Storage
    uint32 public timelock;
    uint256 internal _totalPendingRedeemAssets;
    mapping(address => RedemptionRequest) internal _pendingRedemption;

    struct RedemptionRequest {
        uint256 assets;
        uint256 shares;
        uint32 claimableTimestamp;
    }

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

    /// @notice Thrown when a spender attempts to transfer more shares than their current allowance permits.
    /// @param spender The address attempting to spend the shares.
    /// @param currentAllowance The current allowance granted to the spender.
    /// @param value The amount of shares the spender attempted to transfer.
    error InsufficientShareAllowance(address spender, uint256 currentAllowance, uint256 value);

    constructor(
        IERC20 asset_,
        ERC7575Share share_,
        IDAO _dao,
        uint32 _timelock
    ) DaoAuthorizable(_dao) EIP712("VaultaireVault", "1") {
        _asset = asset_;
        _share = share_;
        timelock = _timelock;
    }

    // @inheritdoc IERC7575
    function asset() external view override returns (address assetTokenAddress) {
        return address(_asset);
    }

    // @inheritdoc IERC7575
    function share() external view override returns (address shareTokenAddress) {
        return address(_share);
    }

    // @inheritdoc IERC7575
    function totalAssets() public view override returns (uint256 totalManagedAssets) {
        return _asset.balanceOf(address(this));
    }

    // @inheritdoc IERC7575
    function totalInternalShares() public view returns (uint256 totalManagedAssets) {
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
    function maxDeposit(address) public pure returns (uint256 maxAssets) {
        return type(uint256).max;
    }

    // @inheritdoc IERC7575
    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    // @inheritdoc IERC7575
    function maxRedeem(address controller) public view virtual returns (uint256) {
        RedemptionRequest memory request = _pendingRedemption[controller];
        if (request.claimableTimestamp <= block.timestamp) {
            return request.shares;
        }
        return 0;
    }

    // @inheritdoc IERC7575
    function maxWithdraw(address controller) public view virtual returns (uint256) {
        RedemptionRequest memory request = _pendingRedemption[controller];
        if (request.claimableTimestamp <= block.timestamp) {
            return request.assets;
        }
        return 0;
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
        revert("ERC7540Vault/async-flow");
    }

    // @inheritdoc IERC7575
    function previewRedeem(uint256) public view virtual returns (uint256) {
        revert("ERC7540Vault/async-flow");
    }

    // @inheritdoc IERC7575
    function deposit(uint256 assets, address receiver) external override returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    // @inheritdoc IERC7575
    function mint(uint256 shares, address receiver) public virtual returns (uint256) {
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ExceededMaxMint(receiver, shares, maxShares);
        }

        uint256 assets = previewMint(shares);
        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    // @inheritdoc IERC7575
    function withdraw(uint256 assets, address receiver, address controller) public virtual returns (uint256) {
        require(controller == msg.sender || isOperator[controller][msg.sender], "ERC7540Vault/invalid-caller");
        require(assets != 0, "Must claim nonzero amount");

        uint256 maxAssets = maxWithdraw(controller);
        if (assets > maxAssets) {
            revert ExceededMaxWithdraw(controller, assets, maxAssets);
        }

        RedemptionRequest storage request = _pendingRedemption[controller];

        // Claiming partially introduces precision loss. The user therefore receives a rounded down amount,
        // while the claimable balance is reduced by a rounded up amount.
        uint256 shares = assets.mulDiv(request.shares, request.assets, Math.Rounding.Floor);
        uint256 sharesUp = assets.mulDiv(request.shares, request.assets, Math.Rounding.Ceil);
        request.assets -= assets;
        request.shares = request.shares > sharesUp ? request.shares - sharesUp : 0;

        _withdraw(_msgSender(), receiver, controller, assets, shares);

        return shares;
    }

    // @inheritdoc IERC7575
    function redeem(uint256 shares, address receiver, address controller) public virtual returns (uint256) {
        require(controller == msg.sender || isOperator[controller][msg.sender], "ERC7540Vault/invalid-caller");
        require(shares != 0, "Must claim nonzero amount");

        uint256 maxShares = maxRedeem(controller);
        if (shares > maxShares) {
            revert ExceededMaxRedeem(controller, shares, maxShares);
        }

        RedemptionRequest storage request = _pendingRedemption[controller];

        uint256 assets = shares.mulDiv(request.assets, request.shares, Math.Rounding.Floor);
        uint256 assetsUp = shares.mulDiv(request.assets, request.shares, Math.Rounding.Ceil);

        request.assets = request.assets > assetsUp ? request.assets - assetsUp : 0;
        request.shares -= shares;

        _withdraw(_msgSender(), receiver, controller, assets, shares);

        return assets;
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual returns (uint256) {
        return assets.mulDiv(totalInternalShares() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, totalInternalShares() + 10 ** _decimalsOffset(), rounding);
    }

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
        // slither-disable-next-line reentrancy-no-eth
        internalShares += shares;
        SafeERC20.safeTransferFrom(_asset, caller, address(this), assets);
        _share.mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual {
        _totalPendingRedeemAssets -= assets;
        SafeERC20.safeTransfer(_asset, receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
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

    /*//////////////////////////////////////////////////////////////
                           ERC7540 LOGIC
       //////////////////////////////////////////////////////////////*/

    function setOperator(address operator, bool approved) public virtual returns (bool success) {
        require(msg.sender != operator, "ERC7540Vault/cannot-set-self-as-operator");
        isOperator[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        success = true;
    }

    /*//////////////////////////////////////////////////////////////
                           EIP-7441 LOGIC
    //////////////////////////////////////////////////////////////*/

    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }

    function authorizeOperator(
        address controller,
        address operator,
        bool approved,
        bytes32 nonce,
        uint256 deadline,
        bytes memory signature
    ) public virtual returns (bool success) {
        require(controller != operator, "ERC7540Vault/cannot-set-self-as-operator");
        require(block.timestamp <= deadline, "ERC7540Vault/expired");
        require(!authorizations[controller][nonce], "ERC7540Vault/authorization-used");

        authorizations[controller][nonce] = true;

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        address recoveredAddress = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            keccak256(
                                "AuthorizeOperator(address controller,address operator,bool approved,bytes32 nonce,uint256 deadline)"
                            ),
                            controller,
                            operator,
                            approved,
                            nonce,
                            deadline
                        )
                    )
                )
            ),
            v,
            r,
            s
        );

        require(recoveredAddress != address(0) && recoveredAddress == controller, "INVALID_SIGNER");

        isOperator[controller][operator] = approved;

        emit OperatorSet(controller, operator, approved);

        success = true;
    }

    /*//////////////////////////////////////////////////////////////
                            ERC7540 LOGIC
    //////////////////////////////////////////////////////////////*/

    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId) {
        require(owner == msg.sender || isOperator[owner][msg.sender], "ERC7540Vault/invalid-owner");

        require(maxRedeem(owner) >= shares, "ERC7540Vault/insufficient-balance");
        require(shares != 0, "ZERO_SHARES");

        uint256 assets = _convertToAssets(shares, Math.Rounding.Floor);

        // SafeERC20.safeTransferFrom(_asset, owner, address(this), shares);
        _share.burn(owner, shares);
        internalShares -= shares;

        RedemptionRequest storage request = _pendingRedemption[controller];

        // If there's an existing request, we update it and reset timelock
        if (request.shares > 0) {
            request.assets += assets;
            request.shares += shares;
            // Reset timelock to ensure enough time for the new request
            request.claimableTimestamp = uint32(block.timestamp) + timelock;
        } else {
            _pendingRedemption[controller] = RedemptionRequest({
                assets: assets,
                shares: shares,
                claimableTimestamp: uint32(block.timestamp) + timelock
            });
        }

        _totalPendingRedeemAssets += assets;

        emit RedeemRequest(controller, owner, REQUEST_ID, msg.sender, shares);
        return REQUEST_ID;
    }

    function pendingRedeemRequest(uint256, address controller) public view returns (uint256 pendingShares) {
        RedemptionRequest memory request = _pendingRedemption[controller];
        if (request.claimableTimestamp > block.timestamp) {
            return request.shares;
        }
        return 0;
    }

    function claimableRedeemRequest(uint256, address controller) public view returns (uint256 claimableShares) {
        RedemptionRequest memory request = _pendingRedemption[controller];
        if (request.claimableTimestamp <= block.timestamp && request.shares > 0) {
            return request.shares;
        }
        return 0;
    }

    function setTimelock(uint32 timelock_) public {
        if (msg.sender == address(dao())) {
            timelock = timelock_;
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IERC7540Operator).interfaceId ||
            interfaceId == type(IERC7575).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}
