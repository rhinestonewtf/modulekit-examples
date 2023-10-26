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
import "modulekit/test/mocks/MockCondition.sol";
import "solmate/test/utils/mocks/MockERC20.sol";
import "../MainnetFork.t.sol";
import "modulekit/modulekit/integrations/interfaces/IERC4626.sol";

address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

contract AutoSaveTest is MainnetTest, RhinestoneModuleKit {
    using RhinestoneModuleKitLib for RhinestoneAccount;

    RhinestoneAccount instance;
    MockRegistry registry;
    ComposableConditionManager conditionManager;
    AutoSavings autoSavings;

    MockCondition mockCondition;
    IERC20 usdc = IERC20(USDC);
    IERC20 weth = IERC20(WETH);
    MockERC4626 vault;

    string constant keySalt = "0";
    string constant keyName = "key";

    address payer;

    function setUp() public override {
        super.setUp();

        payer = makeAddr("payer");
        // Setup account
        instance = makeRhinestoneAccount("1");
        vm.deal(instance.account, 10 ether);

        registry = new MockRegistry();
        conditionManager = new ComposableConditionManager(registry);
        vault = new MockERC4626(ERC20(address(weth)), "vWETH", "vWETH");
        mockCondition = new MockCondition();
        vm.label(address(mockCondition), "GasCondition");
        vm.label(instance.account, "account");
        vm.label(WETH, "weth");
        vm.label(USDC, "usdc");

        // Setup executor
        autoSavings = new AutoSavings(conditionManager);

        // Add executor to account
        instance.addExecutor(address(autoSavings));
    }

    function mockPaymentEvent(uint256 amount) internal {
        deal(USDC, payer, amount);

        vm.prank(payer);
        usdc.transfer(instance.account, amount);
    }

    function testTrigger() public {
        mockPaymentEvent(1000 * 18);
        vm.startPrank(instance.account);

        ConditionConfig[] memory conditions = new ConditionConfig[](1);
        conditions[0] =
            ConditionConfig({ condition: ICondition(address(mockCondition)), conditionData: "" });

        conditionManager.setHash(address(autoSavings), conditions);
        autoSavings.setConfig({
            id: 0,
            spendToken: address(usdc),
            maxAmountIn: 1000,
            vault: IERC4626(address(vault))
        });

        autoSavings.trigger(
            IExecutorManager(address(instance.aux.executorManager)), 0, 1000, conditions
        );

        assertEq(vault.balanceOf(instance.account), 1000);
    }
}
