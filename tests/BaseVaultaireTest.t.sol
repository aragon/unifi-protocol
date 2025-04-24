// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import { Test } from "forge-std/src/Test.sol";

import "../src/VaultaireVault.sol";
import "../src/ERC7575Share.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@aragon/commons/dao/IDAO.sol";
import { MockERC4626 } from "./mocks/MockERC4626.sol";

import { MintableERC20 } from "./mocks/MintableERC20.sol";
// import {SingleStrategyManager} from "../src/SingleStrategyManager.sol";
import { ERC4626Strategy } from "../src/strategies/ERC4626Strategy.sol";
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { createTestDAO } from "./mocks/MockDAO.sol";
import { IVaultAllocationStrategy } from "../src/interfaces/IVaultAllocationStrategy.sol";

contract BaseVaultaireTest is Test {
    // Constants
    uint256 constant INITIAL_ASSETS = 10_000 ether;
    uint256 constant INITIAL_MIN_VAULT_SHARE_BPS = 1000;
    uint32 constant REDEMPTION_TIMELOCK = 1 days;

    // Test accounts
    address deployer;
    address user1;
    address user2;
    address operator;

    // Contracts
    DAO dao;
    MintableERC20 asset;
    MintableERC20 asset2;
    ERC7575Share share;
    VaultaireVault vault;
    VaultaireVault vault2;
    ERC4626Strategy strategy;
    ERC4626Strategy strategy2;
    MockERC4626 lendingVault;
    MockERC4626 lendingVault2;

    constructor() {
        // Create test accounts
        deployer = makeAddr("deployer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        operator = makeAddr("operator");

        // Deploy mock DAO
        dao = createTestDAO(deployer);
        asset = new MintableERC20(deployer, "Test USD", "USDT");
        asset2 = new MintableERC20(deployer, "Test USD", "USDC");
        vm.stopPrank();

        // Deploy share token
        vm.startPrank(deployer);
        share = new ERC7575Share(address(0), dao); // Token bridge is not needed for tests
        vm.stopPrank();

        // Deploy vault
        vm.startPrank(deployer);
        vault = new VaultaireVault(IERC20(address(asset)), share, dao, REDEMPTION_TIMELOCK, INITIAL_MIN_VAULT_SHARE_BPS);
        vm.stopPrank();

        // Set up relationships
        vm.startPrank(address(dao));
        share.addVault(address(asset), vault);
        vm.stopPrank();
        vm.startPrank(deployer);
        dao.grant(address(share), address(vault), share.VAULT_ROLE());
        vm.stopPrank();

        // Deploy strategy
        vm.startPrank(deployer);
        lendingVault = new MockERC4626(address(asset));
        strategy = new ERC4626Strategy(asset, vault, lendingVault, dao);
        vm.stopPrank();
        vm.startPrank(address(dao));
        vault.setStrategy(IVaultAllocationStrategy(strategy));
        vm.stopPrank();

        // Mint initial assets to test users
        vm.startPrank(deployer);
        asset.mint(user1, INITIAL_ASSETS);
        asset.mint(user2, INITIAL_ASSETS);
        vm.stopPrank();

        // Deploy vault 2
        vm.startPrank(deployer);
        vault2 =
            new VaultaireVault(IERC20(address(asset2)), share, dao, REDEMPTION_TIMELOCK, INITIAL_MIN_VAULT_SHARE_BPS);
        vm.stopPrank();

        // Set up relationships
        vm.startPrank(address(dao));
        share.addVault(address(asset2), vault2);
        vm.stopPrank();
        vm.startPrank(deployer);
        dao.grant(address(share), address(vault2), share.VAULT_ROLE());
        vm.stopPrank();

        // Deploy strategy
        vm.startPrank(deployer);
        lendingVault2 = new MockERC4626(address(asset2));
        strategy2 = new ERC4626Strategy(asset2, vault2, lendingVault2, dao);
        vm.stopPrank();
        vm.startPrank(address(dao));
        vault2.setStrategy(IVaultAllocationStrategy(strategy2));
        vm.stopPrank();

        // Mint initial assets to test users
        vm.startPrank(deployer);
        asset2.mint(user1, INITIAL_ASSETS);
        asset2.mint(user2, INITIAL_ASSETS);
        vm.stopPrank();
    }
}
