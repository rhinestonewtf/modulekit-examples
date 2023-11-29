// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "../MainnetFork.t.sol";
import "murky/Merkle.sol";
import {
    RhinestoneModuleKit,
    RhinestoneModuleKitLib,
    RhinestoneAccount
} from "modulekit/test/utils/safe-base/RhinestoneModuleKit.sol";

import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import { MockERC721 } from "solmate/test/utils/mocks/MockERC721.sol";

import "../../src/executors/TokenDumperMerkle.sol";
import "modulekit/test/mocks/MockExecutor.sol";
import "modulekit/test/mocks/MockRegistry.sol";
import "modulekit/test/mocks/MockCondition.sol";

import "forge-std/interfaces/IERC20.sol";
import "modulekit/core/ComposableCondition.sol";
import "modulekit/modulekit/conditions/ScheduleCondition.sol";
import "modulekit/modulekit/conditions/MerkleTreeCondition.sol";
import "modulekit/modulekit/integrations/uniswap/helpers/MainnetAddresses.sol";

address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

contract TokenDumperTest is MainnetTest, RhinestoneModuleKit {
    using RhinestoneModuleKitLib for RhinestoneAccount; // <-- library that wraps smart account actions for easier testing

    MockExecutor mockExecutor;
    RhinestoneAccount instance; // <-- this is a rhinestone smart account instance
    address receiver;
    MockRegistry registry;
    MockCondition mockCondition;

    ComposableConditionManager conditionManager;

    TokenDumper tokenDumper;

    function setUp() public override {
        super.setUp();
        // setting up receiver address. This is the EOA that this test is sending funds to
        receiver = makeAddr("receiver");
        instance = makeRhinestoneAccount("1");
        vm.label(instance.account, "account");

        vm.label(WETH, "WETH");
        vm.label(USDC, "USDC");

        registry = new MockRegistry();
        mockCondition = new MockCondition();
        conditionManager = new ComposableConditionManager(registry);
        tokenDumper = new TokenDumper(conditionManager);
        deal(instance.account, 100 ether);
        deal(USDC, instance.account, 10_000 ** 18);
        deal(WETH, instance.account, 10_000 ** 18);

        instance.addExecutor(address(tokenDumper));
    }

    function test_DumpToken() public {
        // Prepare the merkle tree
        Merkle m = new Merkle();
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = "asdf";
        leaves[1] = tokenDumper._tokenToMerkleLeaf(IERC20(WETH));
        bytes32 root = m.getRoot(leaves);
        bytes32[] memory proof = m.getProof(leaves, 1);
        //-----------------

        ConditionConfig[] memory conditions = new ConditionConfig[](1);
        conditions[0] = ConditionConfig({
            condition: mockCondition,
            conditionData: abi.encode(MerkleTreeCondition.Params({ root: root }))
        });

        // add USDC to protected hodl tokens
        vm.startPrank(instance.account);

        tokenDumper.setTokenDumperConfig({ baseToken: IERC20(USDC), feePercentage: 200 });
        conditionManager.setHash(address(tokenDumper), conditions);
        vm.stopPrank();

        vm.prank(receiver);
        MerkleTreeCondition.MerkleParams memory subParams =
            MerkleTreeCondition.MerkleParams({ proof: proof, leaf: leaves[1] });
        bytes[] memory subParamsBytes = new bytes[](1);
        subParamsBytes[0] = abi.encode(subParams);
        tokenDumper.dump({
            account: instance.account,
            manager: IExecutorManager(address(instance.aux.executorManager)),
            dumpToken: IERC20(WETH),
            conditions: conditions,
            subParams: subParamsBytes
        });

        assertTrue(IERC20(USDC).balanceOf(receiver) > 0);
    }
}
