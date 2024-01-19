// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IERC7579Execution } from "modulekit/Accounts.sol";
import { ERC7579ExecutorBase } from "modulekit/Modules.sol";

contract ColdStorageExecutor is ERC7579ExecutorBase {
    error UnauthorizedAccess();

    mapping(address => address) private _subAccountOwner;

    function executeOnSubAccount(
        address subAccount,
        address target,
        uint256 value,
        bytes calldata callData
    )
        external
        payable
    {
        if (msg.sender != _subAccountOwner[subAccount]) {
            revert UnauthorizedAccess();
        }

        IERC7579Execution smartAccount = IERC7579Execution(subAccount);
        smartAccount.executeFromExecutor(target, value, callData);
    }

    function onInstall(bytes calldata data) external override {
        address owner = abi.decode(data, (address));
        _subAccountOwner[msg.sender] = owner;
    }

    function onUninstall(bytes calldata data) external override {
        delete _subAccountOwner[msg.sender];
    }

    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == TYPE_EXECUTOR;
    }

    function name() external pure virtual override returns (string memory) {
        return "ColdStorageExecutor";
    }

    function version() external pure virtual override returns (string memory) {
        return "0.0.1";
    }
}
