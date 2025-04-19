// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import {BaseVaultaireTest} from "./BaseVaultaireTest.t.sol";
import {console2} from "forge-std/src/console2.sol";

import {VaultaireVault} from "../src/VaultaireVault.sol";
import {ERC7575Share} from "../src/ERC7575Share.sol";
import {IERC7575} from "../src/interfaces/IERC7575.sol";
import {IERC7540Operator} from "../src/interfaces/IERC7540.sol";
import {MintableERC20} from "./mocks/MintableERC20.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SingleStrategyManager} from "../src/SingleStrategyManager.sol";

import {createTestDAO} from "./mocks/MockDAO.sol";

contract SingleStrategyManagerTest is BaseVaultaireTest {
    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        vm.prank(address(dao));
        strategyManager.setInvestmentRatio(8000);
    }

    /// @dev Test if the vault is correctly configured after deployment
    function test_VaultStrategyVaultGetsAssets() external {
        uint256 depositAmount = 10 ether;

        // User1 approves and deposits assets into the vault
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);

        // Expect Deposit event to be emitted
        vm.expectEmit(true, true, false, true);
        emit IERC7575.Deposit(user1, user1, depositAmount, depositAmount);

        uint256 sharesMinted = vault.deposit(depositAmount, user1);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(vault)), depositAmount);
    }
}
