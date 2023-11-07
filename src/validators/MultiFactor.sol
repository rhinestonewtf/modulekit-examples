// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "modulekit/common/erc4337/Helpers.sol";
import "modulekit/modulekit/ValidatorBase.sol";
import "modulekit/modulekit/lib/ValidatorSelectionLib.sol";

import "sentinellist/src/SentinelList.sol";

import "forge-std/console2.sol";

contract MultiFactor is ValidatorBase {
    using ValidatorSelectionLib for UserOperation;
    using SentinelListLib for SentinelListLib.SentinelList;

    mapping(address account => SentinelListLib.SentinelList) private subValidators;

    event AddSubValidator(address indexed account, address indexed subValidator);
    event RemoveSubValidator(address indexed account, address indexed subValidator);

    function initValidator() external {
        subValidators[msg.sender].init();
    }

    function addSubValidator(address subValidator) external {
        subValidators[msg.sender].push(subValidator);
        emit AddSubValidator(msg.sender, subValidator);
    }

    function removeSubValidator(address prevValidator, address subValidator) external {
        subValidators[msg.sender].pop(prevValidator, subValidator);
        emit RemoveSubValidator(msg.sender, subValidator);
    }

    /**
     * @dev validates userOperation
     * @param userOp User Operation to be validated.
     * @param userOpHash Hash of the User Operation to be validated.
     * @return sigValidationResult 0 if signature is valid, SIG_VALIDATION_FAILED otherwise.
     */
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash
    )
        external
        virtual
        override
        returns (uint256)
    {
        (bytes memory signature,) = abi.decode(userOp.signature, (bytes, address));
        (address[] memory validators, bytes[] memory signatures) =
            abi.decode(signature, (address[], bytes[]));

        uint256 validatorsLength = validators.length;
        if (validatorsLength != signatures.length) return 1;

        for (uint256 i; i < validatorsLength; i++) {
            if (!subValidators[userOp.sender].contains(validators[i])) return 1;
            if (IValidator(validators[i]).validateUserOp(userOp, userOpHash) == 1) return 1;
        }

        return 0;
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
