// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

/**
 * @title IVaultAllocationStrategy
 * @dev Interface defining the methods a Vault-compatible investment strategy must implement.
 *
 * A vault calls these methods to allocate or deallocate assets according to the strategy’s rules.
 * In addition, the strategy should be able to report how many assets are principal (original deposits)
 * versus yield (earnings).
 */
interface IVaultAllocationStrategy {
    /**
     * @dev Emitted when the strategy invests `assets`.
     */
    event StrategyInvest(uint256 assets);

    /**
     * @dev Emitted when the strategy divests `assets` for the vault.
     */
    event StrategyDivest(uint256 assets);

    /**
     * @notice Moves `assets` from the vault into the strategy, putting them to work (e.g., lending, staking).
     * @param assets Amount of underlying assets to allocate.
     * @return shares Amount of strategy-specific shares (if applicable), or assets allocated.
     */
    function invest(uint256 assets) external returns (uint256 shares);

    /**
     * @notice Pulls `assets` from the strategy back to the vault, liquidating external positions as needed.
     * @param assets Amount of underlying assets to deallocate.
     * @return actualDivested The actual amount of underlying assets divested (some strategies may be partially
     * illiquid).
     */
    function divest(uint256 assets) external returns (uint256 actualDivested);

    /**
     * @notice Harvests yield or rewards from the strategy’s underlying protocol(s), realizing gains or losses.
     */
    function harvest() external;

    /**
     * @notice Returns how many of the underlying assets the strategy currently manages in total (principal + yield).
     * @return totalManagedAssets The total amount of underlying assets held or owed by this strategy.
     */
    function totalManagedAssets() external view returns (uint256 totalManagedAssets);

    /**
     * @notice Returns how many of the strategy's total assets represent the principal (original deposits).
     * @return totalPrincipal Assets representing the portion of principal still allocated.
     */
    function totalPrincipal() external view returns (uint256 totalPrincipal);

    /**
     * @notice Returns how many of the strategy's total assets represent yield (earnings).
     * @return totalYield Assets representing unrealized yield or gains.
     */
    function totalYield() external view returns (uint256 totalYield);

    /**
     * @notice Indicates the underlying asset the strategy manages.
     * @return asset The address of the underlying ERC20 asset managed by this strategy.
     */
    function asset() external view returns (address asset);
}
