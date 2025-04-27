// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import {VaultaireVault} from "../src/VaultaireVault.sol";
import {ERC7575Share} from "../src/ERC7575Share.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626Strategy} from "../src/strategies/ERC4626Strategy.sol";

import {IDAO} from "@aragon/commons/dao/IDAO.sol";

import {BaseScript} from "./Base.s.sol";
import {console2} from "forge-std/src/console2.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/guides/scripting-with-solidity
contract Deploy is BaseScript {
    address dao;
    address user;

    IERC20 USDC;
    IERC20 USDT;
    IERC20 USDS;
    IERC20 eUSD;

    address USDC_PRICE_FEED;
    address USDT_PRICE_FEED;
    address USDS_PRICE_FEED;
    address eUSD_PRICE_FEED;

    int256 MIN_DEFAULT_PRICE_THRESHOLD;

    VaultaireVault USDCVault;
    VaultaireVault USDSVault;
    VaultaireVault USDTVault;
    VaultaireVault eUSDVault;

    function run() public broadcast {
        dao = vm.envAddress("PROD_DAO");
        user = vm.envAddress("PROD_USER");

        // 1. Deploying Mock Tokens
        USDC = IERC20(vm.envAddress("PROD_USDC"));
        USDT = IERC20(vm.envAddress("PROD_USDT"));
        USDS = IERC20(vm.envAddress("PROD_USDS"));
        eUSD = IERC20(vm.envAddress("PROD_EUSD"));

        // 1. Deploying the 7575Share
        ERC7575Share uUSD = new ERC7575Share(address(this), IDAO(dao));

        // 2. Deploying the first vault
        {
            uint32 vaultTimestamp = uint32(vm.envUint("PROD_VAULT_TIMESTAMP"));
            uint256 minVaultShareBps = vm.envUint("PROD_MIN_VAULT_SHARE_BPS");

            USDC_PRICE_FEED = vm.envAddress("PROD_USDC_CHAINLINK_FEED");
            USDT_PRICE_FEED = vm.envAddress("PROD_USDT_CHAINLINK_FEED");
            USDS_PRICE_FEED = vm.envAddress("PROD_USDS_CHAINLINK_FEED");
            eUSD_PRICE_FEED = vm.envAddress("PROD_EUSD_CHAINLINK_FEED");
            MIN_DEFAULT_PRICE_THRESHOLD = vm.envInt("PROD_MIN_DEFAULT_PRICE_THRESHOLD");

            USDCVault = new VaultaireVault(
                USDC,
                uUSD,
                IDAO(dao),
                vaultTimestamp,
                minVaultShareBps,
                USDC_PRICE_FEED,
                MIN_DEFAULT_PRICE_THRESHOLD
            );
            USDTVault = new VaultaireVault(
                USDT,
                uUSD,
                IDAO(dao),
                vaultTimestamp,
                minVaultShareBps,
                USDT_PRICE_FEED,
                MIN_DEFAULT_PRICE_THRESHOLD
            );
            USDSVault = new VaultaireVault(
                USDS,
                uUSD,
                IDAO(dao),
                vaultTimestamp,
                minVaultShareBps,
                USDS_PRICE_FEED,
                MIN_DEFAULT_PRICE_THRESHOLD
            );
            eUSDVault = new VaultaireVault(
                eUSD,
                uUSD,
                IDAO(dao),
                vaultTimestamp,
                minVaultShareBps,
                eUSD_PRICE_FEED,
                MIN_DEFAULT_PRICE_THRESHOLD
            );
        }

        // 3. Deploying any lending vaults we might want
        // USDC
        IERC4626 USDCLendingVault = IERC4626(vm.envAddress("PROD_USDC_LENDING_VAULT"));
        ERC4626Strategy USDCStrategy = new ERC4626Strategy(USDC, USDCVault, USDCLendingVault, IDAO(dao));
        // USDT
        // IERC4626 USDTLendingVault = IERC4626(vm.envAddress("PROD_USDT_LENDING_VAULT"));
        // ERC4626Strategy USDTStrategy = new ERC4626Strategy(USDT, USDTVault, USDTLendingVault, IDAO(dao));
        // USDS
        IERC4626 USDSLendingVault = IERC4626(vm.envAddress("PROD_USDS_LENDING_VAULT"));
        ERC4626Strategy USDSStrategy = new ERC4626Strategy(USDS, USDSVault, USDSLendingVault, IDAO(dao));
        // eUSD
        IERC4626 eUSDLendingVault = IERC4626(vm.envAddress("PROD_EUSD_LENDING_VAULT"));
        ERC4626Strategy eUSDStrategy = new ERC4626Strategy(eUSD, eUSDVault, eUSDLendingVault, IDAO(dao));

        // 4. I need to manually call the DAO to assign the permissions for now
        console2.log("NEXT_PUBLIC_DAO=", dao);

        console2.log("NEXT_PUBLIC_USDC=", address(USDC));
        console2.log("NEXT_PUBLIC_USDT=", address(USDT));
        console2.log("NEXT_PUBLIC_USDS=", address(USDS));
        console2.log("NEXT_PUBLIC_EUSD=", address(eUSD));

        console2.log("NEXT_PUBLIC_UUSD=", address(uUSD));

        console2.log("NEXT_PUBLIC_USDC_VAULT=", address(USDCVault));
        console2.log("NEXT_PUBLIC_USDT_VAULT=", address(USDTVault));
        console2.log("NEXT_PUBLIC_USDS_VAULT=", address(USDSVault));
        console2.log("NEXT_PUBLIC_EUSD_VAULT=", address(eUSDVault));

        console2.log("NEXT_PUBLIC_USDC_LENDING_VAULT=", address(USDCLendingVault));
        console2.log("NEXT_PUBLIC_USDC_STRATEGY=", address(USDCStrategy));

        // console2.log("NEXT_PUBLIC_USDT_LENDING_VAULT=", address(USDTLendingVault));
        // console2.log("NEXT_PUBLIC_USDT_STRATEGY=", address(USDTStrategy));

        console2.log("NEXT_PUBLIC_USDS_LENDING_VAULT=", address(USDSLendingVault));
        console2.log("NEXT_PUBLIC_USDS_STRATEGY=", address(USDSStrategy));

        console2.log("NEXT_PUBLIC_EUSD_LENDING_VAULT=", address(eUSDLendingVault));
        console2.log("NEXT_PUBLIC_EUSD_STRATEGY=", address(eUSDStrategy));
    }
}
