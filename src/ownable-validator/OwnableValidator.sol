// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import { ERC7579ValidatorBase } from "modulekit/Modules.sol";
import { UserOperation } from "modulekit/external/ERC4337.sol";

import { SignatureCheckerLib } from "solady/src/utils/SignatureCheckerLib.sol";
import { ECDSA } from "solady/src/utils/ECDSA.sol";

import "forge-std/console2.sol";

contract OwnableValidator is ERC7579ValidatorBase {
    using SignatureCheckerLib for address;

    mapping(address subAccout => address owner) public owners;

    function onInstall(bytes calldata data) external override {
        if (data.length == 0) return;
        address owner = abi.decode(data, (address));
        console2.log("setup", msg.sender, owner);
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
        console2.log("\n\nvalidateUserOp");
        console2.log("Account", msg.sender);
        console2.log("UserOpHash");
        console2.logBytes32(userOpHash);
        console2.logBytes32(ECDSA.toEthSignedMessageHash(userOpHash));
        bool validSig = owners[userOp.sender].isValidSignatureNow(
            ECDSA.toEthSignedMessageHash(userOpHash), userOp.signature
        );

        console2.log("valdiate user ops");
        console2.logBytes32(ECDSA.toEthSignedMessageHash(userOpHash));
        console2.logBytes(userOp.signature[20:]);
        console2.log("valid sig", validSig);
        console2.log("\n\n\n");
        return _packValidationData(!validSig, type(uint48).max, 0);
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
        console2.log("isValidSignNow", owner);
        console2.logBytes32(hash);
        console2.logBytes(data);
        address recover = ECDSA.recover(hash, data);
        console2.log("recover", recover, owner);
        bool valid = SignatureCheckerLib.isValidSignatureNow(owner, hash, data);
        console2.log(owner, valid);
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
