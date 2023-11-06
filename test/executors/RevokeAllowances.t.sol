// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import {
    RhinestoneModuleKit,
    RhinestoneModuleKitLib,
    RhinestoneAccount
} from "modulekit/test/utils/safe-base/RhinestoneModuleKit.sol";

import {
    RevokeAllowances,
    TokenRevocation,
    RevocationType,
    IExecutorManager
} from "../../src/executors/RevokeAllowances.sol";
import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";

contract RevokeAllowancesTest is Test, RhinestoneModuleKit {
    using RhinestoneModuleKitLib for RhinestoneAccount;

    RhinestoneAccount instance;
    RevokeAllowances revokeAllowances;
    MockERC20 token;

    string constant keySalt = "0";
    string constant keyName = "key";

    function setUp() public {
        // Setup account
        instance = makeRhinestoneAccount("1");
        vm.deal(instance.account, 10 ether);

        // Set up mock token
        token = new MockERC20("Mock Token", "MTKN", 18);
        token.mint(address(instance.account), 100 ether);

        // Setup executor
        revokeAllowances = new RevokeAllowances();

        // Add executor to account
        instance.addExecutor(address(revokeAllowances));
    }

    function testExecuteRevoke() public {
        // Set relayer
        address relayer = makeAddr("relayer");
        instance.exec4337({
            target: address(revokeAllowances),
            callData: abi.encodeWithSelector(RevokeAllowances.setRelayer.selector, relayer)
        });
        assertEq(revokeAllowances.relayers(instance.account), relayer);

        // Set frequency
        uint16 frequency = 1;
        instance.exec4337({
            target: address(revokeAllowances),
            callData: abi.encodeWithSelector(RevokeAllowances.setFrequency.selector, frequency)
        });
        (uint16 _frequency,) = revokeAllowances.schedules(instance.account);
        assertEq(_frequency, frequency);

        // Set up allowance
        address spender = makeAddr("spender");
        instance.exec4337({
            target: address(token),
            callData: abi.encodeWithSelector(token.approve.selector, spender, 20 ether)
        });
        assertEq(token.allowance(address(instance.account), spender), 20 ether);

        // Execute revocation
        TokenRevocation[] memory tokenRevocations = new TokenRevocation[](1);
        tokenRevocations[0] = TokenRevocation({
            token: payable(address(token)),
            spender: spender,
            tokenId: 0,
            revocationType: RevocationType.ERC20
        });
        vm.warp(1 days + 1 seconds);
        vm.prank(relayer);
        revokeAllowances.executeRevoke({
            manager: IExecutorManager(address(instance.aux.executorManager)),
            account: instance.account,
            revocations: tokenRevocations
        });
        assertEq(token.allowance(address(instance.account), spender), 0);
    }
}
