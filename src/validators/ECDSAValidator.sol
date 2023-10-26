// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {
    ValidatorBase,
    UserOperation,
    VALIDATION_SUCCESS,
    VALIDATION_FAILED,
    ERC1271_MAGICVALUE
} from "modulekit/modulekit/ValidatorBase.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";

contract ECDSAValidator is ValidatorBase {
    using ECDSA for bytes32;

    mapping(address => address) public owners;

    /**
     * @dev sets the owner of the validator
     * @param owner Address of the owner.
     */
    function setOwner(address owner) external {
        owners[msg.sender] = owner;
    }

    /**
     * @dev validates userOperation
     * @param userOp User Operation to be validated.
     * @param userOpHash Hash of the User Operation to be validated.
     * @return sigValidationResult 0 if signature is valid, 1 otherwise.
     */
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash
    )
        external
        view
        override
        returns (uint256)
    {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        (bytes memory sig,) = abi.decode(userOp.signature, (bytes, address));

        if (owners[msg.sender] != hash.recover(sig)) {
            return VALIDATION_FAILED;
        }
        return VALIDATION_SUCCESS;
    }

    /**
     * @dev validates a 1271 signature request
     * @param signedDataHash Hash of the signed data.
     * @param moduleSignature Signature to be validated.
     * @return eip1271Result 0x1626ba7e if signature is valid, 0xffffffff otherwise.
     */
    function isValidSignature(
        bytes32 signedDataHash,
        bytes memory moduleSignature
    )
        public
        view
        override
        returns (bytes4)
    {
        bytes32 hash = signedDataHash.toEthSignedMessageHash();
        if (owners[msg.sender] != hash.recover(moduleSignature)) {
            return 0xffffffff;
        }
        return ERC1271_MAGICVALUE;
    }
}
