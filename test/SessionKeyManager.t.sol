// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import "forge-std/console2.sol";
import {
    RhinestoneModuleKit,
    RhinestoneModuleKitLib,
    RhinestoneAccount
} from "modulekit/test/utils/safe-base/RhinestoneModuleKit.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {SessionStorage, SessionKeyManager} from "../src/SessionKeyManager/SessionKeyManager.sol";
import {ERC20SessionValidationModule} from "../src/SessionKeyManager/SessionKeyValidators/ERC20SessionKeyValidator.sol";

contract SessionKeyMangerTest is Test, RhinestoneModuleKit {
    using RhinestoneModuleKitLib for RhinestoneAccount;

    RhinestoneAccount instance;
    MockERC20 token;
    SessionKeyManager sessionKeyManager;

    ERC20SessionValidationModule sessionKeyValidator;

    function setUp() public {
        // setting up mock executor and token
        token = new MockERC20("", "", 18);

        sessionKeyValidator = new ERC20SessionValidationModule();

        sessionKeyManager = new SessionKeyManager();

        // create a new rhinestone account instance
        instance = makeRhinestoneAccount("1");

        // dealing ether and tokens to newly created smart account
        vm.deal(instance.account, 10 ether);
        token.mint(instance.account, 100 ether);
    }

    function testSetSession(bytes32 root) public {
        instance.addValidator(address(sessionKeyManager));

        vm.prank(instance.account);
        sessionKeyManager.setMerkleRoot(root);

        SessionStorage memory session = sessionKeyManager.getSessionKeys(address(instance.account));
        assertEq(session.merkleRoot, root);
    }
}
