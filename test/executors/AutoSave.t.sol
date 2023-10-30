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
import { AutoSavings, TokenTxEvent } from "../../src/executors/AutoSavings.sol";
import "modulekit/test/mocks/MockRegistry.sol";
import "solmate/test/utils/mocks/MockERC4626.sol";
import "modulekit/test/mocks/MockCondition.sol";
import "solmate/test/utils/mocks/MockERC20.sol";
import "../MainnetFork.t.sol";
import "murky/src/Merkle.sol";
import { IERC4626 } from "modulekit/modulekit/integrations/interfaces/IERC4626.sol";
import "forge-std/interfaces/IERC20.sol";
import "../../src/validators/SessionKey/SessionKeyManager.sol";

import "checknsignatures/CheckNSignaturesFoundryHelper.sol";

address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

contract AutoSaveTest is MainnetTest, RhinestoneModuleKit, CheckNSignaturesFoundryHelper {
    using RhinestoneModuleKitLib for RhinestoneAccount;

    RhinestoneAccount instance;
    MockRegistry registry;
    ComposableConditionManager conditionManager;
    AutoSavings autoSavings;

    SessionKeyManager sessionKeyManager;

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

        sessionKeyManager = new SessionKeyManager();
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
        instance.addValidator(address(sessionKeyManager));

        // setup session key

        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = sessionKeyManager._sessionMerkelLeaf(
            0, 18_000_000, address(mockCondition), abi.encodePacked()
        );
    }

    function mockSetSessionKey(
        address sessionKeyValidator,
        bytes memory sessionKeyData
    )
        internal
        returns (bytes32[] memory proof)
    {
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = "";
        leaves[1] = sessionKeyManager._sessionMerkelLeaf(
            0, 180_000_000, sessionKeyValidator, sessionKeyData
        );

        bytes32 root = m.getRoot(leaves);
        sessionKeyManager.setMerkleRoot(root);

        proof = m.getProof(leaves, 1);
    }

    function mockPaymentEvent(uint256 amount) internal {
        deal(USDC, payer, amount);

        vm.prank(payer);
        usdc.transfer(instance.account, amount);
    }

    function testTrigger() public {
        mockPaymentEvent(0x41414141);
        vm.startPrank(instance.account);

        autoSavings.setRelayer(relayerAddresses, relayerAddresses.length);

        bytes32[] memory proof = mockSetSessionKey(address(autoSavings), "");

        ConditionConfig[] memory conditions = new ConditionConfig[](1);
        conditions[0] =
            ConditionConfig({ condition: ICondition(address(mockCondition)), conditionData: "" });

        SessionKeyParams memory sessionKeyParams = SessionKeyParams({
            validUntil: 0,
            validAfter: 180_000_000,
            sessionValidationModule: address(autoSavings),
            sessionKeyData: abi.encode(
                TokenTxEvent({
                    token: address(usdc),
                    from: payer,
                    to: instance.account,
                    amount: 0x41414141
                })
                ),
            merkleProof: proof,
            sessionKeySignature: ""
        });

        sessionKeyParams.sessionKeySignature = sign(relayerPks, sessionKeyParams.sessionKeyData);

        console2.log("address autoSavings", address(autoSavings));

        conditionManager.setHash(address(autoSavings), conditions);
        autoSavings.setConfig({
            id: 0,
            maxAmountIn: 0x41414141,
            feePercentage: 100,
            vault: IERC4626(address(vault))
        });

        bytes memory encSignature = abi.encode(sessionKeyParams);

        instance.exec4337({
            target: address(autoSavings),
            value: 0,
            callData: abi.encodeCall(
                autoSavings.trigger,
                (
                    usdc,
                    IExecutorManager(address(instance.aux.executorManager)),
                    0,
                    0x41414141,
                    conditions
                )
                ),
            signature: ValidatorSelectionLib.encodeValidator(encSignature, address(sessionKeyManager))
        });
    }
}
