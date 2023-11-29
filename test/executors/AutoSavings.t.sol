// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import {
    RhinestoneModuleKit,
    RhinestoneModuleKitLib,
    RhinestoneAccount
} from "modulekit-multiaccount/multi.sol";
import "modulekit/modulekit/interfaces/IExecutor.sol";

import "modulekit/core/ComposableCondition.sol";
import { AutoSavings, TokenTxEvent } from "../../src/executors/AutoSavings.sol";
import "modulekit/test/mocks/MockRegistry.sol";
import "solmate/test/utils/mocks/MockERC4626.sol";
import "modulekit/test/mocks/MockCondition.sol";
import "solmate/test/utils/mocks/MockERC20.sol";
import "../MainnetFork.t.sol";
import "murky/Merkle.sol";
import { IERC4626 } from "modulekit/modulekit/integrations/interfaces/IERC4626.sol";
import "forge-std/interfaces/IERC20.sol";
import "modulekit/core/SessionKeyManager.sol";

import "checknsignatures/CheckNSignaturesFoundryHelper.sol";

address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

contract AutoSavingsTest is MainnetTest, RhinestoneModuleKit, CheckNSignaturesFoundryHelper {
    using RhinestoneModuleKitLib for RhinestoneAccount;

    RhinestoneAccount instance;
    MockRegistry registry;
    ComposableConditionManager conditionManager;
    AutoSavings autoSavings;

    MockCondition mockCondition;
    IERC20 usdc = IERC20(USDC);
    IERC20 weth = IERC20(WETH);
    MockERC4626 vault;
    Merkle m;

    string constant keySalt = "0";
    string constant keyName = "key";

    address payer;

    address[] relayerAddresses;
    uint256[] relayerPks;

    function _genSigners(uint256 n) internal {
        relayerAddresses = new address[](n);
        relayerPks = new uint256[](n);

        uint256 offset = 1337;
        for (uint256 i; i < n; i++) {
            relayerAddresses[i] = vm.addr(i + offset);
            relayerPks[i] = i + offset;
        }
    }

    function setUp() public override {
        super.setUp();

        m = new Merkle();

        _genSigners(3);
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
        instance.addValidator(address(instance.aux.sessionKeyManager));
    }

    function mockConditionConfig() internal view returns (ConditionConfig[] memory conditions) {
        conditions = new ConditionConfig[](1);
        conditions[0] =
            ConditionConfig({ condition: ICondition(address(mockCondition)), conditionData: "" });
    }

    function testTrigger(uint256 amount) public {
        vm.assume(amount > 10_000);
        vm.assume(amount < 100_000 ether);
        // metadata for session key
        uint256 validUntil = 0;
        uint256 validAfter = 180_000_000;
        address tokenToSave = address(usdc);
        bytes memory savingsEvent =
            abi.encode(TokenTxEvent({ token: tokenToSave, to: instance.account }));

        vm.startPrank(instance.account);
        ConditionConfig[] memory conditions = mockConditionConfig();
        conditionManager.setHash(address(autoSavings), conditions);
        autoSavings.setConfig({
            id: 0,
            maxAmountIn: amount,
            feePercentage: 100,
            vault: IERC4626(address(vault))
        });

        // user authorizes a specific relayer to trigger autosavings
        autoSavings.setRelayer(relayerAddresses, relayerAddresses.length);
        (, bytes32[] memory proof) = instance.addSessionKey({
            validUntil: validUntil,
            validAfter: validAfter,
            sessionValidationModule: address(autoSavings),
            sessionKeyData: savingsEvent
        });

        vm.stopPrank();

        // simulate a ERC20 transfer
        deal(tokenToSave, payer, amount);
        vm.prank(payer);
        usdc.transfer(instance.account, amount);

        // prepare sessionKeyParams for SessionKeyManager
        SessionKeyParams memory sessionKeyParams = SessionKeyParams({
            validUntil: validUntil,
            validAfter: validAfter,
            sessionValidationModule: address(autoSavings),
            sessionKeyData: savingsEvent,
            merkleProof: proof,
            sessionKeySignature: sign(relayerPks, savingsEvent) // sign with CheckNSignaturesFoundryHelper
         });

        // trigger 4337 exec
        // instance.exec4337({
        //     target: address(autoSavings),
        //     value: 0,
        //     callData: abi.encodeCall(
        //         autoSavings.trigger,
        //         (usdc, IExecutorManager(address(instance.aux.executorManager)), 0, amount, conditions)
        //         ),
        //     signature: abi.encode(sessionKeyParams),
        //     validator: address(instance.aux.sessionKeyManager)
        // });
    }
}
