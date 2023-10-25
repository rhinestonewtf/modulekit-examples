// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./MainnetFork.t.sol";
import {
    RhinestoneModuleKit,
    RhinestoneModuleKitLib,
    RhinestoneAccount
} from "modulekit/test/utils/safe-base/RhinestoneModuleKit.sol";

import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import { MockERC721 } from "solmate/test/utils/mocks/MockERC721.sol";

import "../src/AutoSavings/DollarCostAverage.sol";
import "modulekit/test/mocks/MockExecutor.sol";
import "modulekit/test/mocks/MockRegistry.sol";

import "forge-std/console2.sol";
import "forge-std/interfaces/IERC20.sol";
import "modulekit/core/ComposableCondition.sol";
import "modulekit/modulekit/conditions/ScheduleCondition.sol";
import "modulekit/modulekit/integrations/uniswap/helpers/MainnetAddresses.sol";

address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

contract DollarCostAverageTest is MainnetTest, RhinestoneModuleKit {
    using RhinestoneModuleKitLib for RhinestoneAccount; // <-- library that wraps smart account actions for easier testing

    MockExecutor mockExecutor;
    RhinestoneAccount instance; // <-- this is a rhinestone smart account instance
    address receiver;
    MockRegistry registry;

    ComposableConditionManager conditionManager;
    ScheduleCondition schedule;

    DCA dca;

    function setUp() public override {
        super.setUp();
        // setting up receiver address. This is the EOA that this test is sending funds to
        receiver = makeAddr("receiver");

        schedule = new ScheduleCondition();

        registry = new MockRegistry();
        conditionManager = new ComposableConditionManager(registry);

        dca = new DCA(conditionManager);

        // create a new rhinestone account instance
        instance = makeRhinestoneAccount("1");

        // dealing ether and tokens to newly created smart account
        vm.deal(instance.account, 10 ether);

        deal(USDC, instance.account, 10_000 ** 18);
        instance.addExecutor(address(dca));
    }

    function testDCA() public {
        DCA.DCAStrategy memory strategy = DCA.DCAStrategy({
            spendToken: IERC20(USDC),
            buyToken: IERC20(WETH),
            spendAmount: 50 ** 18
        });

        ScheduleCondition.Params memory scheduleParams =
            ScheduleCondition.Params({ triggerEveryHours: 7 * 24 });
        ConditionConfig[] memory conditions = new ConditionConfig[](1);
        conditions[0] = ConditionConfig({
            condition: ICondition(address(schedule)),
            conditionData: abi.encode(scheduleParams)
        });

        vm.startPrank(instance.account);
        dca.setStrategy(0, strategy);
        conditionManager.setHash(address(dca), conditions);
        IERC20(USDC).approve(SWAPROUTER_ADDRESS, 10_000 ** 18);
        vm.stopPrank();

        dca.triggerDCA(
            instance.account, IExecutorManager(address(instance.aux.executorManager)), 0, conditions
        );
    }
}
