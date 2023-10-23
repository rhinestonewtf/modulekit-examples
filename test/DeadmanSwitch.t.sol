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

import "../src/DeadmansSwitch/DeadmanSwitch.sol";
import "modulekit/test/mocks/MockExecutor.sol";

import "forge-std/console2.sol";

contract ERC721FlashLoanTest is Test, RhinestoneModuleKit {
    using RhinestoneModuleKitLib for RhinestoneAccount; // <-- library that wraps smart account actions for easier testing

    MockExecutor mockExecutor;
    RhinestoneAccount instance; // <-- this is a rhinestone smart account instance
    address receiver;
    MockERC20 token;

    DeadmanSwitch dms;

    function setUp() public {
        // setting up receiver address. This is the EOA that this test is sending funds to
        receiver = makeAddr("receiver");

        mockExecutor = new MockExecutor();

        // setting up mock executor and token
        token = new MockERC20("", "", 18);

        dms = new DeadmanSwitch();

        // create a new rhinestone account instance
        instance = makeRhinestoneAccount("1");

        // dealing ether and tokens to newly created smart account
        vm.deal(instance.account, 10 ether);
        token.mint(address(instance.account), 10 ** 18);
        instance.addExecutor(address(mockExecutor));
    }

    function activate_hook() internal {
        instance.addHook(address(dms));
        instance.addValidator(address(dms));

        vm.warp(16_000_000);

        assertEq(token.balanceOf(receiver), 0);
        mockExecutor.exec(
            instance.aux.executorManager, instance.account, address(token), receiver, 100
        );
        assertEq(token.balanceOf(receiver), 100);

        uint256 lastExec = dms.lastAccess(instance.account);
        assertEq(lastExec, 16_000_000);

        vm.warp(16_000_001);
    }
}
