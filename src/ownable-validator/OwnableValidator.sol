// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import { ERC7579ValidatorBase } from "modulekit/Modules.sol";
import { UserOperation } from "modulekit/external/ERC4337.sol";

import { SignatureCheckerLib } from "solady/src/utils/SignatureCheckerLib.sol";

contract OwnableValidator is ERC7579ValidatorBase {
    mapping(address subAccout => address owner) public owners;

    function onInstall(bytes calldata data) external override {
        address owner = abi.decode(data, (address));
        owners[msg.sender] = owner;
    }

    function onUninstall(bytes calldata) external override {
        delete owners[msg.sender];
    }

    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash
    )
        external
        view
        override
        returns (ValidationData)
    {
        bool isValid = SignatureCheckerLib.isValidSignatureNow(
            owners[userOp.sender], userOpHash, userOp.signature
        );
        return _packValidationData(isValid, 0, type(uint48).max);
    }

    function isValidSignatureWithSender(
        address,
        bytes32 hash,
        bytes calldata data
    )
        external
        view
        override
        returns (bytes4)
    {
        address owner = owners[msg.sender];
        return SignatureCheckerLib.isValidSignatureNow(owner, hash, data)
            ? EIP1271_SUCCESS
            : EIP1271_FAILED;
    }

    function name() external pure override returns (string memory) {
        return "OwnableValidator";
    }

    function version() external pure override returns (string memory) {
        return "0.0.1";
    }

    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == TYPE_VALIDATOR;
    }
}
