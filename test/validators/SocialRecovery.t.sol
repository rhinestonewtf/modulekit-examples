// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { ECDSA } from "solady/src/utils/ECDSA.sol";
import {
    RhinestoneModuleKit,
    RhinestoneModuleKitLib,
    RhinestoneAccount
} from "modulekit/test/utils/biconomy-base/RhinestoneModuleKit.sol";
import { SocialRecovery } from "../../src/validators/SocialRecovery.sol";

contract SocialRecoveryTest is Test, RhinestoneModuleKit {
    using RhinestoneModuleKitLib for RhinestoneAccount;
    using ECDSA for bytes32;

    RhinestoneAccount instance;
    SocialRecovery socialRecovery;

    address signer1;
    address signer2;
    address signer3;

    uint256 signer1Pk;
    uint256 signer2Pk;
    uint256 signer3Pk;

    function setUp() public {
        // Setup account
        instance = makeRhinestoneAccount("1");
        vm.deal(instance.account, 10 ether);

        // Setup validator
        socialRecovery = new SocialRecovery();
        (address owner,) = makeAddrAndKey("owner");
        vm.prank(instance.account);
        // ecdsaValidator.setOwner(owner);

        // Add validator to account
        instance.addValidator(address(socialRecovery));

        // Setup signers
        (signer1, signer1Pk) = makeAddrAndKey("signer1");
        (signer2, signer2Pk) = makeAddrAndKey("signer2");
        (signer3, signer3Pk) = makeAddrAndKey("signer3");
    }

    function testRecover() public {
        address[] memory guardians = new address[](5);
        guardians[1] = makeAddr("wont sign2");
        guardians[0] = signer2;
        guardians[2] = signer1;
        guardians[3] = makeAddr("wont sign1");
        guardians[4] = signer3;

        address smartAccount = instance.account;

        vm.prank(smartAccount);
        socialRecovery.setupGuardian(guardians, 3);

        assertTrue(socialRecovery.isGuardian(smartAccount, signer1), "signer1 missing");
        assertTrue(socialRecovery.isGuardian(smartAccount, signer2), "signer2 missing");
        assertTrue(socialRecovery.isGuardian(smartAccount, signer3), "signer3 missing");
        assertFalse(socialRecovery.isGuardian(smartAccount, makeAddr("not a guardian")));

        // check that the threshold is set correctly
        (uint8 threshold, uint8 guardianCount,) = socialRecovery.getConfig(smartAccount);
        assertEq(threshold, 3);
        assertEq(guardianCount, 5);

        // check that the nonce is set correctly
        (,, uint16 recoveryNonce) = socialRecovery.getConfig(smartAccount);
        bytes memory data = abi.encodePacked(recoveryNonce);
        bytes32 dataHash = keccak256(data);

        bytes memory signatures;
        uint8 v;
        bytes32 r;
        bytes32 s;
        {
            (v, r, s) = vm.sign(signer1Pk, dataHash);
            signatures = abi.encodePacked(r, s, v);
            (v, r, s) = vm.sign(signer2Pk, dataHash);
            signatures = abi.encodePacked(signatures, abi.encodePacked(r, s, v));
            (v, r, s) = vm.sign(signer3Pk, dataHash);
            signatures = abi.encodePacked(signatures, abi.encodePacked(r, s, v));
        }

        // Create userOperation fields
        address receiver = makeAddr("receiver");
        uint256 value = 10 gwei;
        bytes memory callData = "";

        // Create signature
        bytes memory signature =
            abi.encode(abi.encode(dataHash, signatures), address(socialRecovery));

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
