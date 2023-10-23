// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import { WebAuthnLib } from "./utils/WebAuthnLib.sol";
import {
    ValidatorBase,
    UserOperation,
    VALIDATION_SUCCESS,
    VALIDATION_FAILED,
    ERC1271_MAGICVALUE
} from "modulekit/modulekit/ValidatorBase.sol";

struct PassKeyId {
    uint256 pubKeyX;
    uint256 pubKeyY;
    string keyId;
}

contract WebAuthnValidator is ValidatorBase {

    string public constant NAME = "PassKeys Ownership Registry Module";
    string public constant VERSION = "0.2.0";

    error NoPassKeyRegisteredForSmartAccount(address smartAccount);
    error AlreadyInitedForSmartAccount(address smartAccount);

    event NewPassKeyRegistered(address indexed smartAccount, string keyId);

    mapping(address account => PassKeyId) public smartAccountPassKeys;

    function addPassKey(
        bytes32 _keyHash,
        uint256 _pubKeyX,
        uint256 _pubKeyY,
        string memory _keyId
    )
        public
    {
        smartAccountPassKeys[msg.sender] = PassKeyId(_pubKeyX, _pubKeyY, _keyId);
        emit NewPassKeyRegistered(msg.sender, _keyId);
    }

    function getAuthorizedKey(address account) public view returns (PassKeyId memory passkey) {
        passkey = smartAccountPassKeys[account];
    }

    function removePassKey() public {
        smartAccountPassKeys[msg.sender] = PassKeyId(0, 0, "");
    }

    // TODO remove not needed variables
    function verifyPasskeySignature(
        UserOperation calldata userOp,
        bytes32 userOpHash
    )
        internal
        returns (bool isValidSignature)
    {
        (
            bytes32 keyHash,
            bytes memory authenticatorData,
            bytes1 authenticatorDataFlagMask,
            bytes memory clientData,
            uint256 clientChallengeDataOffset,
            uint256[2] memory rs
        ) = abi.decode(
            userOp.signature, (bytes32, bytes, bytes1, bytes, uint256, uint256[2])
        );

        PassKeyId memory passKey = smartAccountPassKeys[userOp.sender];
        require(passKey.pubKeyY != 0 && passKey.pubKeyY != 0, "Key not found");
        uint256[2] memory Q = [passKey.pubKeyX, passKey.pubKeyY];
        isValidSignature = WebAuthnLib.checkSignature(
            authenticatorData,
            authenticatorDataFlagMask,
            clientData,
            userOpHash,
            clientChallengeDataOffset,
            rs,
            Q
        );
    }

    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash
    )
        external
        override
        returns (uint256)
    {
        bool validSignature = verifyPasskeySignature(userOp, userOpHash);
        return validSignature ? 0 : 1;
    }

    /**
     * @dev isValidSignature according to BaseAuthorizationModule
     * @param _dataHash Hash of the data to be validated.
     * @param _signature Signature over the the _dataHash.
     * @return always returns 0xffffffff as signing messages is not supported by SessionKeys
     */
    function isValidSignature(
        bytes32 _dataHash,
        bytes memory _signature
    )
        public
        view
        override
        returns (bytes4)
    {
        return 0xffffffff; // do not support it here
    }
}