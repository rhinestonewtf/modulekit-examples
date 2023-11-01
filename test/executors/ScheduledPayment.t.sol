// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { Denominations } from "modulekit/modulekit/integrations/Denominations.sol";
import {
    RhinestoneModuleKit,
    RhinestoneModuleKitLib,
    RhinestoneAccount
} from "modulekit/test/utils/safe-base/RhinestoneModuleKit.sol";

import { ScheduledPayment, IExecutorManager } from "../../src/executors/ScheduledPayment.sol";

contract ScheduledPaymentTest is Test, RhinestoneModuleKit {
    using RhinestoneModuleKitLib for RhinestoneAccount;

    RhinestoneAccount instance;
    ScheduledPayment scheduledPayment;

    string constant keySalt = "0";
    string constant keyName = "key";

    function setUp() public {
        // Setup account
        instance = makeRhinestoneAccount("1");
        vm.deal(instance.account, 10 ether);

        // Setup executor
        scheduledPayment = new ScheduledPayment();

        // Add executor to account
        instance.addExecutor(address(scheduledPayment));
    }

    function testExecutePayment() public {
        // Set relayer
        address relayer = makeAddr("relayer");
        instance.exec4337({
            target: address(scheduledPayment),
            callData: abi.encodeWithSelector(scheduledPayment.setRelayer.selector, relayer)
        });
        assertEq(scheduledPayment.relayers(instance.account), relayer);

        // Set up payment
        address beneficiary = makeAddr("beneficiary");
        uint256 value = 100;
        address tokenAddress = Denominations.ETH;
        uint16 frequency = 1;
        instance.exec4337({
            target: address(scheduledPayment),
            callData: abi.encodeWithSelector(
                ScheduledPayment.addPayment.selector, beneficiary, value, tokenAddress, frequency
                )
        });

        // Execute payment
        vm.warp(2 days);
        vm.prank(relayer);
        scheduledPayment.executePayment({
            manager: IExecutorManager(address(instance.aux.executorManager)),
            account: instance.account,
            paymentIndex: 0
        });

        // Check payment
        assertEq(beneficiary.balance, value);
    }
}
