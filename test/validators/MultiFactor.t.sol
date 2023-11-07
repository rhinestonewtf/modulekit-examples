// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";
import {
    RhinestoneModuleKit,
    RhinestoneModuleKitLib,
    RhinestoneAccount
} from "modulekit/test/utils/biconomy-base/RhinestoneModuleKit.sol";

import { MockValidator } from "modulekit/test/mocks/MockValidator.sol";
import { ECDSAValidator, ERC1271_MAGICVALUE } from "../../src/validators/ECDSAValidator.sol";
import { MultiFactor } from "../../src/validators/MultiFactor.sol";

contract MultiFactorTest is Test, RhinestoneModuleKit {
    using RhinestoneModuleKitLib for RhinestoneAccount;
    using ECDSA for bytes32;

    RhinestoneAccount instance;
    MultiFactor multiFactor;

    MockValidator validator1;
    MockValidator validator2;

    function setUp() public {
        // Setup account
        instance = makeRhinestoneAccount("1");

        multiFactor = new MultiFactor();
        vm.deal(instance.account, 10 ether);

        // Setup validator
        validator1 = new MockValidator();
        vm.label(address(validator1), "validator1");
        validator2 = new MockValidator();
        vm.label(address(validator2), "validator2");
        (address owner,) = makeAddrAndKey("owner");
        vm.startPrank(instance.account);
        multiFactor.initValidator();
        multiFactor.addSubValidator(address(validator1));
        multiFactor.addSubValidator(address(validator2));
        vm.stopPrank();

        // Add validator to account
        instance.addValidator(address(multiFactor));
    }

    function testMultiFactor() public {
        // Create userOperation fields
        address receiver = makeAddr("receiver");
        uint256 value = 10 gwei;
        bytes memory callData = "";

        // Create signature
        (, uint256 key) = makeAddrAndKey("owner");
        bytes32 hash =
            instance.getUserOpHash({ target: receiver, value: value, callData: callData });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, hash.toEthSignedMessageHash());
        bytes memory sig1 = abi.encodePacked(r, s, v);
        bytes memory sig2 = abi.encodePacked(r, s, v);
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = sig1;
        signatures[1] = sig2;
        address[] memory validators = new address[](2);
        validators[0] = address(validator1);
        validators[1] = address(validator2);
        bytes memory signature =
            abi.encode(abi.encode(validators, signatures), address(multiFactor));

        // Create userOperation
        instance.exec4337({
            target: receiver,
            value: value,
            callData: callData,
            signature: signature
        });

        // Validate userOperation
        assertEq(receiver.balance, 10 gwei, "Receiver should have 10 gwei");
    }
}
