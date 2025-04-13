// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import {VaultaireVault} from "../src/VaultaireVault.sol";
import {ERC7575Share} from "../src/ERC7575Share.sol";

import {MintableERC20} from "../tests/mocks/MintableERC20.sol";

import {IDAO} from "@aragon/commons/dao/IDAO.sol";

import {BaseScript} from "./Base.s.sol";
import {console2} from "forge-std/src/console2.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/guides/scripting-with-solidity
contract Deploy is BaseScript {
    function run()
        public
        broadcast
        returns (
            ERC7575Share share,
            VaultaireVault fUSDCVault,
            VaultaireVault fUSDsVault,
            VaultaireVault fUSDTVault,
            VaultaireVault fGHOVault
        )
    {
        address dao = vm.envAddress("DAO");
        address user = vm.envAddress("USER");
        uint32 vaultTimestamp = uint32(vm.envUint("VAULT_TIMESTAMP"));
        address tokenBridge = address(this);

        // 1. Deploying Mock Tokens
        MintableERC20 asset1 = new MintableERC20(broadcaster, "fakeUSDC", "fUSDC");
        console2.log("fake USDC: ", address(asset1));

        MintableERC20 asset2 = new MintableERC20(broadcaster, "fakeUSDs", "fUSDs");
        console2.log("fake USDs: ", address(asset2));

        MintableERC20 asset3 = new MintableERC20(broadcaster, "fakeUSDT", "fUSDT");
        console2.log("fake USDT: ", address(asset3));

        MintableERC20 asset4 = new MintableERC20(broadcaster, "fakeGHO", "fGHO");
        console2.log("fake GHO: ", address(asset4));

        asset1.mint(user, 100 ether);
        asset2.mint(user, 75 ether);
        asset3.mint(user, 50 ether);
        asset4.mint(user, 25 ether);

        // 1. Deploying the 7575Share
        share = new ERC7575Share(tokenBridge, IDAO(dao));

        // 2. Deploying the first vault
        fUSDCVault = new VaultaireVault(asset1, share, IDAO(dao), vaultTimestamp);
        fUSDsVault = new VaultaireVault(asset2, share, IDAO(dao), vaultTimestamp);
        fUSDTVault = new VaultaireVault(asset3, share, IDAO(dao), vaultTimestamp);
        fGHOVault = new VaultaireVault(asset4, share, IDAO(dao), vaultTimestamp);

        // 3. I need to manually call the DAO to assign the permissions for now
    }
}
