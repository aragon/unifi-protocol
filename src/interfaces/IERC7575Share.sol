// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

interface IERC7575Share {
    event VaultUpdate(address indexed asset, address vault);

    /**
     * @dev Returns the address of the Vault for the given asset.
     *
     * @param asset the ERC-20 token to deposit with into the Vault
     */
    function vault(address asset) external view returns (address vault);
}
