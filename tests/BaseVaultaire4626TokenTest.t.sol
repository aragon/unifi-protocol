// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import {Test} from "forge-std/src/Test.sol";

import {Vaultaire4626TokenVault} from "../src/Vaultaire4626TokenVault.sol";
import {ERC7575Share} from "../src/ERC7575Share.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC4626} from "./mocks/MockERC4626.sol";

import {MintableERC20} from "./mocks/MintableERC20.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {createTestDAO} from "./mocks/MockDAO.sol";

contract BaseVaultaire4626TokenTest is Test {
    // Constants
    uint256 public constant INITIAL_ASSETS = 10_000 ether;
    uint256 public constant INITIAL_MIN_VAULT_SHARE_BPS = 1000;
    uint32 public constant REDEMPTION_TIMELOCK = 1 days;

    // Test accounts
    address public deployer;
    address public user1;
    address public user2;
    address public operator;

    // Contracts
    DAO public dao;
    MintableERC20 public assetCollateral;
    MockERC4626 public asset;
    ERC7575Share public share;
    Vaultaire4626TokenVault public vault;

    constructor() {
        // Create test accounts
        deployer = makeAddr("deployer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        operator = makeAddr("operator");

        // Deploy mock DAO
        dao = createTestDAO(deployer);
        assetCollateral = new MintableERC20(deployer, "Test USD", "USDT", 18);
        asset = new MockERC4626(address(assetCollateral));
        vm.stopPrank();

        // Deploy share token
        vm.startPrank(deployer);
        share = new ERC7575Share(address(0), dao); // Token bridge is not needed for tests
        vm.stopPrank();

        // Deploy vault
        vm.startPrank(deployer);
        vault = new Vaultaire4626TokenVault(
            IERC20(address(asset)),
            share,
            dao,
            REDEMPTION_TIMELOCK,
            INITIAL_MIN_VAULT_SHARE_BPS
        );
        vm.stopPrank();

        // Set up relationships
        vm.startPrank(address(dao));
        share.addVault(address(asset), vault);
        vm.stopPrank();
        vm.startPrank(deployer);
        dao.grant(address(share), address(vault), share.VAULT_ROLE());
        vm.stopPrank();

        // Mint initial assets to test users
        vm.startPrank(deployer);
        assetCollateral.mint(user1, INITIAL_ASSETS * 2);
        assetCollateral.mint(user2, INITIAL_ASSETS * 2);
        vm.stopPrank();

        // Deposit collateral into the token
        vm.startPrank(user1);
        assetCollateral.approve(address(asset), INITIAL_ASSETS);
        asset.deposit(INITIAL_ASSETS, user1);
        vm.stopPrank();
        vm.startPrank(user2);
        assetCollateral.approve(address(asset), INITIAL_ASSETS);
        asset.deposit(INITIAL_ASSETS, user2);
        vm.stopPrank();
    }
}
