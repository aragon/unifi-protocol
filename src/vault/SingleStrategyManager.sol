// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {DaoAuthorizable} from "@aragon/commons/permission/auth/DaoAuthorizable.sol";
import {IVaultAllocationStrategy} from "../interfaces/IVaultAllocationStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SingleStrategyManager
 * @dev A simple manager that integrates with exactly one strategy at a time.
 * This implementation includes DAO governance controls for setting allocation ratios and
 * emergency strategy clearing.
 */
abstract contract SingleStrategyManager is DaoAuthorizable {
    IVaultAllocationStrategy private _strategy; // The currently active strategy

    // Investment ratio (in basis points, i.e., 10000 = 100%)
    // Determines how much of new deposits get allocated to the strategy
    // uint256 public investmentRatio = 8000; // To 80%
    uint256 public investmentRatio = 0; // Default 0%
    uint256 public currentlyInvested = 0;

    event PortfolioRebalanced(uint256 investmentRatio, uint256 assetsAllocated, uint256 assetsDeallocated);
    event StrategySet(IVaultAllocationStrategy strategy);
    event InvestmentRatioUpdated(uint256 newRatio);
    /**
     * @dev Error thrown when a non-DAO address attempts to call a DAO-only function.
     */
    error OnlyDAOAllowed(address caller, address dao);

    /**
     * @dev Error thrown when a ratio exceeds 100% (10000 basis points).
     */
    error RatioExceeds100Percent(uint256 ratio);

    constructor(IDAO dao_) DaoAuthorizable(dao_) {}

    /**
     * @notice Assigns a new strategy address (or updates the existing one).
     * @dev Can only be called by the vault or the DAO
     */
    function setStrategy(IVaultAllocationStrategy strategy) external {
        if (msg.sender != address(dao())) {
            revert OnlyDAOAllowed(msg.sender, address(dao()));
        }
        _strategy = strategy;
        emit StrategySet(strategy);
    }

    /**
     * @notice Clears out the active strategy, setting it to address(0).
     * @dev Can only be called by the vault or the DAO
     */
    function clearStrategy() external {
        if (msg.sender != address(dao())) {
            revert OnlyDAOAllowed(msg.sender, address(dao()));
        }
        _strategy = IVaultAllocationStrategy(address(0));
        emit StrategySet(_strategy);
    }

    /**
     * @notice Returns the active strategy.
     */
    function getStrategy() public view returns (IVaultAllocationStrategy strategy) {
        return _strategy;
    }

    /**
     * @notice Allocates `assets` to the active strategy based on current investment ratio.
     * @dev This will allocate a portion of the assets according to the investmentRatio.
     */
    function _allocate(IERC20 asset, uint256 assets) internal returns (uint256 totalAllocated) {
        if (address(_strategy) == address(0)) return 0;

        // Calculate how much to actually invest based on the ratio
        uint256 amountToInvest = (assets * investmentRatio) / 10000;
        if (amountToInvest == 0) return 0;

        asset.approve(address(_strategy), amountToInvest);
        totalAllocated = _strategy.invest(amountToInvest);
        currentlyInvested += totalAllocated;

        return totalAllocated;
    }

    /**
     * @notice Deallocates `assets` from the active strategy.
     */
    function _deallocate(uint256 assets) internal returns (uint256 totalDeallocated) {
        if (address(_strategy) == address(0)) return 0;

        totalDeallocated = _strategy.divest(assets);
        currentlyInvested -= totalDeallocated;

        return totalDeallocated;
    }

    /**
     * @notice Harvests yield on the active strategy.
     */
    function _harvest() internal {
        if (address(_strategy) == address(0)) return;
        _strategy.harvest();
    }

    /**
     * @notice Rebalances the assets between vault and strategy according to the current investment ratio.
     * @dev This can be called by the DAO to adjust allocations after changing investment ratios.
     * @return assetsAllocated Amount of assets moved to the strategy, if any.
     * @return assetsDeallocated Amount of assets moved from the strategy to the vault, if any.
     */
    function _rebalance() internal returns (uint256 assetsAllocated, uint256 assetsDeallocated) {
        /*
        if (address(_strategy) == address(0)) return (0, 0);

        // Get current asset balances
        IERC20 asset = IERC20(vault.asset());
        uint256 vaultBalance = asset.balanceOf(address(vault));
        uint256 strategyBalance = _strategy.totalManagedAssets();
        uint256 totalAssets = vaultBalance + strategyBalance;

        // Calculate target amounts based on investment ratio
        uint256 targetStrategyAmount = (totalAssets * investmentRatio) / 10000;

        // Determine if we need to allocate more to strategy or deallocate
        if (strategyBalance < targetStrategyAmount) {
            // Need to allocate more to the strategy
            uint256 amountToInvest = targetStrategyAmount - strategyBalance;

            // Ensure the vault has enough to invest while respecting reserved ratio
            uint256 minReserve = (totalAssets * (10000 - investmentRatio)) / 10000;
            if (vaultBalance - amountToInvest < minReserve) {
                amountToInvest = vaultBalance > minReserve ? vaultBalance - minReserve : 0;
            }

            if (amountToInvest > 0) {
                assetsAllocated = _strategy.invest(amountToInvest);
            }
        } else if (strategyBalance > targetStrategyAmount) {
            // Need to deallocate from the strategy
            uint256 amountToDivest = strategyBalance - targetStrategyAmount;
            if (amountToDivest > 0) {
                assetsDeallocated = _strategy.divest(amountToDivest);
            }
        }

        emit PortfolioRebalanced(investmentRatio, assetsAllocated, assetsDeallocated);
        */
    }

    /**
     * @notice Sets the investment ratio (how much of deposits goes to strategy).
     * @dev Only the DAO can call this function
     * @param newRatio The new investment ratio in basis points (e.g., 8000 = 80%)
     */
    function setInvestmentRatio(uint256 newRatio) external {
        if (msg.sender != address(dao())) {
            revert OnlyDAOAllowed(msg.sender, address(dao()));
        }

        if (newRatio > 10000) {
            revert RatioExceeds100Percent(newRatio);
        }

        investmentRatio = newRatio;
        emit InvestmentRatioUpdated(newRatio);

        // Automatically rebalance when ratio changes
        // rebalance();
    }
}
