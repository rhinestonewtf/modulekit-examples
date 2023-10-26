// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import {
    RhinestoneModuleKit,
    RhinestoneModuleKitLib,
    RhinestoneAccount
} from "modulekit/test/utils/safe-base/RhinestoneModuleKit.sol";
import "modulekit/modulekit/interfaces/IExecutor.sol";

import "modulekit/core/ComposableCondition.sol";
import { AutoSavings } from "../../src/executors/AutoSavings.sol";
import "modulekit/test/mocks/MockRegistry.sol";
import "solmate/test/utils/mocks/MockERC4626.sol";
import "solmate/test/utils/mocks/MockERC20.sol";
import "../MainnetFork.t.sol";
import "forge-std/interfaces/IERC20.sol";

address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

contract AutoSaveTest is MainnetTest, RhinestoneModuleKit {
    using RhinestoneModuleKitLib for RhinestoneAccount;

    RhinestoneAccount instance;
    MockRegistry registry;
    ComposableConditionManager conditionManager;
    AutoSavings autoSavings;

    IERC20 usdc = IERC20(USDC);
    IERC20 weth = IERC20(WETH);
    MockERC4626 vault;

    string constant keySalt = "0";
    string constant keyName = "key";

    function setUp() public override {
        super.setUp();
        // Setup account
        instance = makeRhinestoneAccount("1");
        vm.deal(instance.account, 10 ether);

        registry = new MockRegistry();
        conditionManager = new ComposableConditionManager(registry);
        vault = new MockERC4626(ERC20(address(weth)), "vWETH", "vWETH");

        // Setup executor
        autoSavings = new AutoSavings(conditionManager);

        // Add executor to account
        instance.addExecutor(address(autoSavings));
    }

    function testTrigger() public {
        vm.startPrank(instance.account);

        ConditionConfig[] memory conditions = new ConditionConfig[](0);

        autoSavings.trigger(
            IExecutorManager(address(instance.aux.executorManager)), 0, 1000, conditions
        );
    }
}
