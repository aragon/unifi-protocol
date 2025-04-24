// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import { IDAO } from "@aragon/commons/dao/IDAO.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Bridgeable } from "@openzeppelin/community-contracts/token/ERC20/extensions/ERC20Bridgeable.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

import { IERC7575Share } from "./interfaces/IERC7575Share.sol";
import { IERC7575 } from "./interfaces/IERC7575.sol";
import { PausableShare } from "./share/PausableShare.sol";

contract ERC7575Share is ERC20, ERC20Bridgeable, ERC20Burnable, ERC20Permit, IERC7575Share, PausableShare {
    bytes32 public constant TOKEN_BRIDGE_ROLE = keccak256("TOKEN_BRIDGE_ROLE");
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    mapping(address => IERC7575) internal _vaults;

    constructor(address tokenBridge, IDAO dao) ERC20("uUSD", "uUSD") ERC20Permit("uUSD") PausableShare(dao) { }

    function vault(address asset) external view returns (address vault_) {
        return address(_vaults[asset]);
    }

    function _checkTokenBridge(address caller) internal view override auth(TOKEN_BRIDGE_ROLE) {
        // if (!hasRole(TOKEN_BRIDGE_ROLE, caller)) revert Unauthorized();
    }

    function addVault(address asset, IERC7575 _vault) public {
        if (msg.sender != address(dao())) revert NotAuthorized();

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

    function setInternalApproves(address owner, address spender, uint256 amount) public auth(VAULT_ROLE) {
        _approve(owner, spender, amount);
    }

    // The following functions are overrides required by Solidity.
    function supportsInterface(bytes4 interfaceId) public view override(ERC20Bridgeable) returns (bool) {
        if (interfaceId == type(IERC7575Share).interfaceId) return true;
        return super.supportsInterface(interfaceId);
    }
}
