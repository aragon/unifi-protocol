// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import {IVaultAllocationStrategy} from "./IVaultAllocationStrategy.sol";

/**
 * @title ISingleStrategyManager
 * @dev Interface for a manager that controls a single strategy.
 */
interface ISingleStrategyManager {
    /**
     * @dev Emitted when the manager sets or updates the strategy.
     */
    event StrategySet(IVaultAllocationStrategy indexed strategy);

    /**
     * @dev Emitted when the portfolio is rebalanced.
     */
    event PortfolioRebalanced(uint256 targetRatio, uint256 assetsAllocated, uint256 assetsDeallocated);

    /**
     * @notice Assigns a new strategy (or updates the existing one).
     * @param strategy The address of the new strategy contract.
     */
    function setStrategy(IVaultAllocationStrategy strategy) external;

    /**
     * @notice Clears out the active strategy, setting it to address(0).
     */
    function clearStrategy() external;

    /**
     * @notice Allocates `assets` to the active strategy.
     * @return totalAllocated The total amount of assets actually allocated.
     */
    function allocate(uint256 assets) external returns (uint256 totalAllocated);

    /**
     * @notice Deallocates `assets` from the active strategy.
     * @return totalDeallocated The total amount of assets actually deallocated.
     */
    function deallocate(uint256 assets) external returns (uint256 totalDeallocated);

    /**
     * @notice Harvests yield on the active strategy.
     */
    function harvest() external;

    /**
     * @notice Returns the currently active strategy.
     * @return strategy The address of the active strategy, or address(0) if none set.
     */
    function getStrategy() external view returns (IVaultAllocationStrategy strategy);
}
