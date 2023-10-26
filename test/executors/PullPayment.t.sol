// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import {
    RhinestoneModuleKit,
    RhinestoneModuleKitLib,
    RhinestoneAccount
} from "modulekit/test/utils/safe-base/RhinestoneModuleKit.sol";

import { PullPayment, IExecutorManager } from "../../src/executors/PullPayment.sol";

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

    function testExecuteWithdrawal() public {
        // Set relayer
        address relayer = makeAddr("relayer");
        instance.exec4337({
            target: address(pullPayment),
            callData: abi.encodeWithSelector(PullPayment.setRelayer.selector, relayer)
        });
        assertEq(pullPayment.relayers(instance.account), relayer);

        // Set up withdrawal
        address beneficiary = makeAddr("beneficiary");
        uint256 value = 100;
        address tokenAddress = address(0);
        uint16 frequency = 1;
        instance.exec4337({
            target: address(pullPayment),
            callData: abi.encodeWithSelector(
                PullPayment.addWithdrawal.selector, beneficiary, value, tokenAddress, frequency
                )
        });

        // Execute withdrawal
        vm.warp(1 days);
        vm.prank(relayer);
        pullPayment.executeWithdrawal({
            manager: IExecutorManager(address(instance.aux.executorManager)),
            account: instance.account,
            withdrawalIndex: 0
        });

        // Check withdrawal
        assertEq(beneficiary.balance, value);
    }
}
