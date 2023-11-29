// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { ECDSA } from "solady/src/utils/ECDSA.sol";
import {
    RhinestoneModuleKit,
    RhinestoneModuleKitLib,
    RhinestoneAccount
} from "modulekit/test/utils/biconomy-base/RhinestoneModuleKit.sol";
import { ECDSAValidator, ERC1271_MAGICVALUE } from "../../src/validators/ECDSAValidator.sol";

contract ECDSAValidatorTest is Test, RhinestoneModuleKit {
    using RhinestoneModuleKitLib for RhinestoneAccount;
    using ECDSA for bytes32;

    RhinestoneAccount instance;
    ECDSAValidator ecdsaValidator;

    function setUp() public {
        // Setup account
        instance = makeRhinestoneAccount("1");
        vm.deal(instance.account, 10 ether);

        // Setup validator
        ecdsaValidator = new ECDSAValidator();
        (address owner,) = makeAddrAndKey("owner");
        vm.prank(instance.account);
        ecdsaValidator.setOwner(owner);

        // Add validator to account
        instance.addValidator(address(ecdsaValidator));
    }

    function testSendEth() public {
        // Create userOperation fields
        address receiver = makeAddr("receiver");
        uint256 value = 10 gwei;
        bytes memory callData = "";

        // Create signature
        (, uint256 key) = makeAddrAndKey("owner");
        bytes32 hash =
            instance.getUserOpHash({ target: receiver, value: value, callData: callData });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, hash.toEthSignedMessageHash());
        bytes memory signature = abi.encode(abi.encodePacked(r, s, v), address(ecdsaValidator));

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

    function test1271Signature() public {
        // Create signature
        (, uint256 key) = makeAddrAndKey("owner");
        bytes32 hash = keccak256("signature");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, hash.toEthSignedMessageHash());
        bytes memory signature = abi.encodePacked(r, s, v);

        // Validate signature
        vm.prank(instance.account);
        bytes4 returnValue = ecdsaValidator.isValidSignature(hash, signature);

        // Validate signature success
        assertEq(
            returnValue,
            ERC1271_MAGICVALUE, // EIP1271_MAGIC_VALUE
            "Signature should be valid"
        );
    }
}
