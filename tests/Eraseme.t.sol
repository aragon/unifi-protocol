// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {ERC7575Share} from "../src/ERC7575Share.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {createTestDAO} from "./mocks/MockDAO.sol";

import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

/* solhint-disable max-states-count */
contract BaseDeployTest is TestHelperOz5 {
    // Test accounts
    address public deployer;
    address public user1;
    address public user2;
    address public operator;

    // Contracts
    DAO public dao;
    uint32 private shareEid = 1;
    ERC7575Share public share;

    function setUp() public virtual override {
        super.setUp();
    }

    function test_Deployment() public {
        // Create test accounts
        deployer = makeAddr("deployer");

        // Deploy mock DAO
        dao = createTestDAO(deployer);

        setUpEndpoints(2, LibraryType.UltraLightNode);

        // Deploy share toke
        address bridgeEndpoint = endpoints[shareEid];
        share = ERC7575Share(_deployOApp(type(ERC7575Share).creationCode, abi.encode(bridgeEndpoint, address(dao))));
        vm.stopPrank();
    }
}
