// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import {SingleStrategyManager} from "./SingleStrategyManager.sol";
import {AggregatorV3Interface} from "../interfaces/IAggregatorV3Chainlink.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";

abstract contract VaultDefaultChecker is SingleStrategyManager {
    AggregatorV3Interface private immutable priceFeed;
    int256 private immutable defaultPriceThreshold;
    bool public isPaused;

    event VaultPaused(int256 currentPrice, int256 threshold);
    event VaultUnpaused();

    error PriceFeedStale(uint256 lastUpdated, uint256 currentTime);
    error NotAuthorized();

    constructor(address _priceFeed, int256 _defaultPriceThreshold) {
        priceFeed = AggregatorV3Interface(_priceFeed);
        defaultPriceThreshold = _defaultPriceThreshold;
    }

    /**
     * @notice Checks the current price and pauses the vault if the token is defaulted.
     */
    function checkForDefault() external {
        if (address(priceFeed) == address(0)) revert NotAuthorized();
        if (defaultPriceThreshold <= 0) revert NotAuthorized();

        (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();

        // Ensure the price feed data is not stale (e.g., older than 1 hour)
        if (block.timestamp - updatedAt > 1 hours) {
            revert PriceFeedStale(updatedAt, block.timestamp);
        }

        // Scale the price to 18 decimals for comparison
        uint8 priceDecimals = priceFeed.decimals();
        int256 scaledPrice = price * int256(10 ** (18 - priceDecimals));

        // Check if the price is below the default threshold
        if (scaledPrice < defaultPriceThreshold && !isPaused) {
            _pause(scaledPrice);
        }
    }

    /**
     * @notice Allows the DAO to pause the vault.
     */
    function pause(int256 scaledPrice) public {
        if (msg.sender != address(dao())) revert NotAuthorized();
        _pause(scaledPrice);
    }

    /**
     * @notice Allows to pause the vault internally.
     */
    function _pause(int256 scaledPrice) internal {
        isPaused = true;
        emit VaultPaused(scaledPrice, defaultPriceThreshold);
    }

    /**
     * @notice Allows the DAO to unpause the vault.
     */
    function unpause() external {
        if (msg.sender != address(dao())) revert NotAuthorized();
        isPaused = false;
        emit VaultUnpaused();
    }

    /**
     * @notice Returns the default price threshold.
     */
    function getDefaultPriceThreshold() external view returns (int256) {
        return defaultPriceThreshold;
    }
}
