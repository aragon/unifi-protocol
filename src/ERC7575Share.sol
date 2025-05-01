// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

import {IERC7575Share} from "./interfaces/IERC7575Share.sol";
import {IERC7575} from "./interfaces/IERC7575.sol";
import {PausableShare} from "./share/PausableShare.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";

contract ERC7575Share is OFT, PausableShare, IERC7575Share {
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    mapping(address collateralAddress => IERC7575 vaultAddress)
        internal _vaults;

    constructor(
        address lzBridge,
        address dao
    ) PausableShare(dao) OFT("uUSD", "uUSD", lzBridge, dao) Ownable(dao) {}

    function vault(address asset) external view returns (address vault_) {
        return address(_vaults[asset]);
    }

    function addVault(address asset, IERC7575 _vault) public onlyOwner {
        _vaults[asset] = _vault;
    }

    function mint(address to, uint256 amount) public auth(VAULT_ROLE) {
        if (mintsPaused) revert SharesPaused();
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) public auth(VAULT_ROLE) {
        if (burnsPaused) revert SharesPaused();
        _burn(to, amount);
    }

    function setInternalApproves(
        address owner,
        address spender,
        uint256 amount
    ) public auth(VAULT_ROLE) {
        _approve(owner, spender, amount);
    }

    // The following functions are overrides required by Solidity.
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        if (interfaceId == type(IERC7575Share).interfaceId) return true;
        return false;
    }
}
