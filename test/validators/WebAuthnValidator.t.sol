// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";
import {
    RhinestoneModuleKit,
    RhinestoneModuleKitLib,
    RhinestoneAccount
} from "modulekit/test/utils/biconomy-base/RhinestoneModuleKit.sol";
import { WebAuthnValidator, ERC1271_MAGICVALUE, PassKeyId } from "../../src/validators/WebAuthn/WebAuthnValidator.sol";

contract WebAuthnValidatorTest is Test, RhinestoneModuleKit {
    using RhinestoneModuleKitLib for RhinestoneAccount;
    using ECDSA for bytes32;

    RhinestoneAccount instance;
    WebAuthnValidator webAuthnValidator;

    string constant keySalt = "0";
        string constant keyName = "key";

    function setUp() public {
        // Setup account
        instance = makeRhinestoneAccount("1");
        vm.deal(instance.account, 10 ether);

        // Setup validator
        webAuthnValidator = new WebAuthnValidator();
        (address owner,) = makeAddrAndKey("owner");
        vm.prank(instance.account);

        // Get keys
         uint256[2] memory publicKey = createPasskey(keySalt);

        // Add two passkeys
        bytes memory addPassKeyCalldata = abi.encodeWithSelector(
            WebAuthnValidator.addPassKey.selector,
            keccak256(abi.encode(keyName)),
            publicKey[0],
            publicKey[1],
            keyName
        );
        instance.exec4337({ target: address(webAuthnValidator), callData: addPassKeyCalldata });

        // Add validator to account
        instance.addValidator(address(webAuthnValidator));
    }

    function testAddPassKey() public {
        // Get keys
        uint256[2] memory publicKey = createPasskey(keySalt);

        // Get active keys
        PassKeyId memory activeKeys =
            webAuthnValidator.getAuthorizedKey(address(instance.account));

        assertEq(
            activeKeys.pubKeyX,
            publicKey[0],
            "Incorrect pub Key X"
        );
        assertEq(
            activeKeys.pubKeyY,
            publicKey[1],
            "Incorrect pub Key Y"
        );
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
        bytes memory rawSignature =
            signMessageWithPasskey({ salt: keySalt, messageHash: hash, keyName: keyName });
        bytes memory signature = abi.encode(rawSignature, address(webAuthnValidator));

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

    // Helpers 

    function createPasskey(string memory salt) public returns (uint256[2] memory) {
        string[] memory cmd = new string[](6);

        cmd[0] = "yarn";
        cmd[1] = "--silent";
        cmd[2] = "ts-node";
        cmd[3] = "ecma/webauthnHelper.ts";
        cmd[4] = "generate";
        cmd[5] = salt;

        bytes memory res = vm.ffi(cmd);
        uint256[2] memory publicKey = abi.decode(res, (uint256[2]));
        return publicKey;
    }

    function signMessageWithPasskey(
        string memory salt,
        bytes32 messageHash,
        string memory keyName
    )
        public
        returns (bytes memory)
    {
        string[] memory cmd = new string[](8);

        cmd[0] = "yarn";
        cmd[1] = "--silent";
        cmd[2] = "ts-node";
        cmd[3] = "ecma/webauthnHelper.ts";
        cmd[4] = "sign";
        cmd[5] = salt;
        cmd[6] = iToHex(abi.encodePacked(messageHash));
        cmd[7] = keyName;

        bytes memory res = vm.ffi(cmd);

        return res;
    }

    function iToHex(bytes memory buffer) public pure returns (string memory) {
        // Fixed buffer size for hexadecimal convertion
        bytes memory converted = new bytes(buffer.length * 2);

        bytes memory _base = "0123456789abcdef";

        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }

        return string(abi.encodePacked("0x", converted));
    }
}
