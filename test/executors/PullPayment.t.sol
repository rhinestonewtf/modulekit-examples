// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import {
    RhinestoneModuleKit,
    RhinestoneModuleKitLib,
    RhinestoneAccount
} from "modulekit/test/utils/safe-base/RhinestoneModuleKit.sol";

import {PullPayment} from "../../src/executors/PullPayment.sol";

contract PullPaymentTest is Test, RhinestoneModuleKit {
    using RhinestoneModuleKitLib for RhinestoneAccount; 

     RhinestoneAccount instance;
    PullPayment pullPayment;

    string constant keySalt = "0";
    string constant keyName = "key";

    function setUp() public {
        // Setup account
        instance = makeRhinestoneAccount("1");
        vm.deal(instance.account, 10 ether);

        // Setup executor
        pullPayment = new PullPayment();

        // Add executor to account
        instance.addExecutor(address(pullPayment));
    }

}
