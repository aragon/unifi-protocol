// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity >=0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import { ERC20Bridgeable } from "@openzeppelin/community-contracts/token/ERC20/extensions/ERC20Bridgeable.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MintableERC20 is ERC20, ERC20Burnable, Ownable, ERC20Permit {
    uint8 private _customDecimals;

    error Unauthorized();

    constructor(
        address initialOwner,
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) Ownable(initialOwner) ERC20Permit(name) {
        _customDecimals = decimals_;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return _customDecimals;
    }
}
