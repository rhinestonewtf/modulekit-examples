// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IERC7579Account } from "modulekit/Accounts.sol";
import { ERC7579ExecutorBase } from "modulekit/Modules.sol";
import { ModeLib } from "umsa/lib/ModeLib.sol";
import { ExecutionLib } from "umsa/lib/ExecutionLib.sol";
import { EncodedModuleTypes, ModuleTypeLib, ModuleType } from "umsa/lib/ModuleTypeLib.sol";

contract ColdStorageExecutor is ERC7579ExecutorBase {
    error UnauthorizedAccess();

    mapping(address subAccount => address owner) private _subAccountOwner;

    function executeOnSubAccount(address subAccount, bytes calldata callData) external payable {
        if (msg.sender != _subAccountOwner[subAccount]) {
            revert UnauthorizedAccess();
        }

        IERC7579Account(subAccount).executeFromExecutor(ModeLib.encodeSimpleSingle(), callData);
    }

    function onInstall(bytes calldata data) external override {
        address owner = address(bytes20(data[0:20]));
        _subAccountOwner[msg.sender] = owner;
    }

    function onUninstall(bytes calldata) external override {
        delete _subAccountOwner[msg.sender];
    }

    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == TYPE_EXECUTOR;
    }

    function getModuleTypes() external view returns (EncodedModuleTypes) { }

    function isInitialized(address smartAccount) external view returns (bool) {
        return _subAccountOwner[smartAccount] != address(0);
    }
}
