// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import {
    RhinestoneModuleKit,
    RhinestoneModuleKitLib,
    RhinestoneAccount
} from "modulekit/test/utils/safe-base/RhinestoneModuleKit.sol";

import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import { MockERC721 } from "solmate/test/utils/mocks/MockERC721.sol";

import "../../src/hooks/DeadmanSwitch.sol";
import "modulekit/test/mocks/MockExecutor.sol";
import "modulekit/test/mocks/MockRegistry.sol";

import "forge-std/console2.sol";
import "forge-std/interfaces/IERC20.sol";
import "modulekit/core/ComposableCondition.sol";

contract DeadmanSwitchTest is Test, RhinestoneModuleKit {
    using RhinestoneModuleKitLib for RhinestoneAccount; // <-- library that wraps smart account actions for easier testing

    MockExecutor mockExecutor;
    RhinestoneAccount instance; // <-- this is a rhinestone smart account instance
    address receiver;
    MockERC20 token;
    MockRegistry registry;

    ComposableConditionManager conditionManager;

    DeadmanSwitch dms;

    function setUp() public {
        // setting up receiver address. This is the EOA that this test is sending funds to
        receiver = makeAddr("receiver");

        registry = new MockRegistry();
        conditionManager = new ComposableConditionManager(registry);

        mockExecutor = new MockExecutor();

        // setting up mock executor and token
        token = new MockERC20("", "", 18);

        dms = new DeadmanSwitch(conditionManager);

        // create a new rhinestone account instance
        instance = makeRhinestoneAccount("1");

        // dealing ether and tokens to newly created smart account
        vm.deal(instance.account, 10 ether);
        token.mint(address(instance.account), 10 ** 18);
        instance.addExecutor(address(mockExecutor));
    }

    function test_IterateLastAccess() public {
        instance.addHook(address(dms));
        instance.addExecutor(address(dms));

        vm.warp(16_000_000);

        assertEq(token.balanceOf(receiver), 0);
        mockExecutor.exec(
            IExecutorManager(address(instance.aux.executorManager)),
            instance.account,
            address(token),
            receiver,
            100
        );
        assertEq(token.balanceOf(receiver), 100);
        uint256 lastExec = dms.lastAccess(instance.account);
        assertEq(lastExec, 16_000_000);

        vm.warp(16_000_001);
    }

    function test_recoverAccount() public {
        test_IterateLastAccess();

        address nominee = makeAddr("nominee");

        DeadmansSwitchParams memory params = DeadmansSwitchParams({ timeout: 365 days });

        ConditionConfig[] memory conditions = new ConditionConfig[](1);
        conditions[0] = ConditionConfig({
            condition: ICondition(address(dms)),
            conditionData: abi.encode(params)
        });

        vm.startPrank(instance.account);
        conditionManager.setHash({ executor: address(dms), conditions: conditions });
        dms.setNominee(nominee);
        vm.stopPrank();

        ExecutorAction[] memory actions = new ExecutorAction[](1);
        actions[0] = ExecutorAction({
            to: payable(address(token)),
            value: 0,
            data: abi.encodeCall(IERC20.transfer, (address(nominee), 100))
        });
        ExecutorTransaction memory recoveryActions =
            ExecutorTransaction({ actions: actions, nonce: 0, metadataHash: bytes32(0) });

        vm.prank(nominee);
        vm.expectRevert();
        dms.recover(
            instance.account,
            IExecutorManager(address(instance.aux.executorManager)),
            recoveryActions,
            conditions
        );

        vm.warp(16_000_002 + 365 days);

        vm.prank(nominee);
        dms.recover(
            instance.account,
            IExecutorManager(address(instance.aux.executorManager)),
            recoveryActions,
            conditions
        );

        assertEq(token.balanceOf(nominee), 100);
    }
}
