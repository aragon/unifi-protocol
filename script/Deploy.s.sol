// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import { VaultaireVault } from "../src/VaultaireVault.sol";
import { ERC7575Share } from "../src/ERC7575Share.sol";

import { MintableERC20 } from "../tests/mocks/MintableERC20.sol";
import { MockERC4626 } from "../tests/mocks/MockERC4626.sol";
import { ERC4626Strategy } from "../src/strategies/ERC4626Strategy.sol";

import { IDAO } from "@aragon/commons/dao/IDAO.sol";

import { BaseScript } from "./Base.s.sol";
import { console2 } from "forge-std/src/console2.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/guides/scripting-with-solidity
contract Deploy is BaseScript {
    VaultaireVault public fUSDCVault;
    VaultaireVault public fUSDSVault;
    VaultaireVault public fUSDTVault;
    VaultaireVault public fGHOVault;

    function run() public broadcast {
        address dao = vm.envAddress("DAO");
        address user = vm.envAddress("USER");

        // 1. Deploying Mock Tokens
        MintableERC20 asset1 = new MintableERC20(broadcaster, "fakeUSDC", "fUSDC", 6);
        MintableERC20 asset2 = new MintableERC20(broadcaster, "fakeUSDs", "fUSDs", 18);
        MintableERC20 asset3 = new MintableERC20(broadcaster, "fakeUSDT", "fUSDT", 18);
        MintableERC20 asset4 = new MintableERC20(broadcaster, "fakeGHO", "fGHO", 6);

        asset1.mint(user, 100 ether / 10 ** 6);
        asset2.mint(user, 75 ether);
        asset3.mint(user, 50 ether);
        asset4.mint(user, (25 ether / 10) * 6);

        // 1. Deploying the 7575Share
        ERC7575Share share = new ERC7575Share(address(this), IDAO(dao));

        // 2. Deploying the first vault
        {
            uint32 vaultTimestamp = uint32(vm.envUint("VAULT_TIMESTAMP"));
            uint256 minVaultShareBps = vm.envUint("MIN_VAULT_SHARE_BPS");

            fUSDCVault = new VaultaireVault(asset1, share, IDAO(dao), vaultTimestamp, minVaultShareBps, address(0), 0);
            fUSDSVault = new VaultaireVault(asset2, share, IDAO(dao), vaultTimestamp, minVaultShareBps, address(0), 0);
            fUSDTVault = new VaultaireVault(asset3, share, IDAO(dao), vaultTimestamp, minVaultShareBps, address(0), 0);
            fGHOVault = new VaultaireVault(asset4, share, IDAO(dao), vaultTimestamp, minVaultShareBps, address(0), 0);
        }

        // 3. Deploying any lending vaults we might want
        MockERC4626 fUSDClendingVault = new MockERC4626(address(asset1));
        ERC4626Strategy fUSDCstrategy = new ERC4626Strategy(asset1, fUSDCVault, fUSDClendingVault, IDAO(dao));
        MockERC4626 fUSDSlendingVault = new MockERC4626(address(asset2));
        ERC4626Strategy fUSDSstrategy = new ERC4626Strategy(asset2, fUSDSVault, fUSDSlendingVault, IDAO(dao));

        // 4. I need to manually call the DAO to assign the permissions for now
        console2.log("NEXT_PUBLIC_DAO=", dao);

        console2.log("NEXT_PUBLIC_USDC=", address(asset1));
        console2.log("NEXT_PUBLIC_USDT=", address(asset3));
        console2.log("NEXT_PUBLIC_USDS=", address(asset2));
        console2.log("NEXT_PUBLIC_GHO=", address(asset4));

        console2.log("NEXT_PUBLIC_UUSD=", address(share));

        console2.log("NEXT_PUBLIC_USDC_VAULT=", address(fUSDCVault));
        console2.log("NEXT_PUBLIC_USDT_VAULT=", address(fUSDTVault));
        console2.log("NEXT_PUBLIC_USDS_VAULT=", address(fUSDSVault));
        console2.log("NEXT_PUBLIC_GHO_VAULT=", address(fGHOVault));

        console2.log("NEXT_PUBLIC_USDC_LENDING_VAULT=", address(fUSDClendingVault));
        console2.log("NEXT_PUBLIC_USDC_STRATEGY=", address(fUSDCstrategy));

        console2.log("NEXT_PUBLIC_USDS_LENDING_VAULT=", address(fUSDSlendingVault));
        console2.log("NEXT_PUBLIC_USDS_STRATEGY=", address(fUSDSstrategy));
    }
}
