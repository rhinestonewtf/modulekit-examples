// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {
    ValidatorBase,
    UserOperation,
    VALIDATION_SUCCESS,
    VALIDATION_FAILED,
    ERC1271_MAGICVALUE
} from "modulekit/modulekit/ValidatorBase.sol";
import { CheckSignatures } from "checknsignatures/CheckNSignatures.sol";
import { SentinelListLib } from "sentinellist/SentinelList.sol";

import "forge-std/console2.sol";

contract SocialRecovery is ValidatorBase {
    using SentinelListLib for SentinelListLib.SentinelList;
    using CheckSignatures for bytes32;

    struct SocialRecoveryConfig {
        uint8 threshold;
        uint8 guardianCount;
        uint16 recoveryNonce;
        SentinelListLib.SentinelList guardians;
    }

    mapping(address account => SocialRecoveryConfig) internal guardians;

    event AddedGuardian(address indexed guardian);
    event RemovedGuardian(address indexed guardian);
    event ChangedThreshold(uint256 threshold);

    error InvalidNonce();
    error InvalidGuardian(address guardian);
    error InvalidThreshold(uint8 threshold);
    error InvalidAddress();
    error AlreadySetup();
    error NotInitialized();

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
        override
        returns (uint256)
    {
        SocialRecoveryConfig storage config = guardians[userOp.sender];
        if (config.threshold == 0) return VALIDATION_FAILED;
        (bytes memory signature,) = abi.decode(userOp.signature, (bytes, address));
        (bytes32 dataHash, bytes memory signatures) = abi.decode(signature, (bytes32, bytes));
        if (keccak256(abi.encodePacked(config.recoveryNonce)) != dataHash) revert InvalidNonce();
        config.recoveryNonce++;

        // get all guardians
        address[] memory recoveredGuardians =
            dataHash.recoverNSignatures(signatures, config.threshold);

        if (recoveredGuardians.length < config.threshold) {
            return VALIDATION_FAILED;
        }

        //check if guardians are in the list
        for (uint256 i; i < recoveredGuardians.length; i++) {
            if (!config.guardians.contains(recoveredGuardians[i])) {
                return VALIDATION_FAILED;
            }
        }
        return VALIDATION_SUCCESS;
    }

    function getConfig(address account)
        external
        view
        returns (uint8 threshold, uint8 guardianCount, uint16 recoveryNonce)
    {
        SocialRecoveryConfig storage config = guardians[account];
        return (config.threshold, config.guardianCount, config.recoveryNonce);
    }

    function setupGuardian(address[] memory _guardians, uint8 _threshold) external {
        SocialRecoveryConfig storage config = guardians[msg.sender];

        uint256 length = _guardians.length;
        if (config.threshold != 0) revert AlreadySetup();
        if (_threshold > length) revert InvalidThreshold(_threshold);

        config.guardians.init();

        for (uint256 i; i < length; i++) {
            _addGuardian(config, _guardians[i]);
        }
        config.threshold = _threshold;
        config.guardianCount = uint8(length);
    }

    function _addGuardian(SocialRecoveryConfig storage config, address guardian) internal {
        if (guardian == address(0)) revert InvalidAddress();

        config.guardians.push(guardian);
        config.guardianCount++;
        emit AddedGuardian(guardian);
    }

    function addGuardian(address guardian) external {
        SocialRecoveryConfig storage config = guardians[msg.sender];
        _addGuardian(config, guardian);
    }

    function changeThreshold(uint8 _threshold) public {
        SocialRecoveryConfig storage config = guardians[msg.sender];

        if (_threshold > config.guardianCount) revert InvalidThreshold(_threshold);
        if (_threshold == 0) revert InvalidThreshold(_threshold);

        config.threshold = _threshold;

        emit ChangedThreshold(_threshold);
    }

    function removeGuardian(address prevGuardian, address guardian, uint8 _threshold) external {
        SocialRecoveryConfig storage config = guardians[msg.sender];

        config.guardians.pop(prevGuardian, guardian);
        emit RemovedGuardian(guardian);
        // Change threshold if threshold was changed.
        if (config.threshold != _threshold) changeThreshold(_threshold);
    }

    function isGuardian(address account, address guardian) external view returns (bool) {
        SocialRecoveryConfig storage config = guardians[account];
        return config.guardians.contains(guardian);
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
        return 0xffffffff; // Not supported
    }
}
