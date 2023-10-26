// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import {
    RhinestoneModuleKit,
    RhinestoneModuleKitLib,
    RhinestoneAccount
} from "modulekit/test/utils/safe-base/RhinestoneModuleKit.sol";

import { RevokeAllowances } from "../../src/executors/RevokeAllowances.sol";

contract RevokeAllowancesTest is Test, RhinestoneModuleKit {
    using RhinestoneModuleKitLib for RhinestoneAccount;

    RhinestoneAccount instance;
    RevokeAllowances revokeAllowances;

    string constant keySalt = "0";
    string constant keyName = "key";

    function setUp() public {
        // Setup account
        instance = makeRhinestoneAccount("1");
        vm.deal(instance.account, 10 ether);

        // Setup executor
        revokeAllowances = new RevokeAllowances();

        // Add executor to account
        instance.addExecutor(address(revokeAllowances));
    }
}
