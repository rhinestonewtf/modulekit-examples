// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { ERC7579HookBase } from "modulekit/Modules.sol";

struct DeadmansSwitchParams {
    uint256 timeout;
}

contract DeadmanSwitch is ERC7579HookBase {
    struct DeadmanSwitchStorage {
        uint48 lastAccess;
        address nominee;
    }

    mapping(address account => DeadmanSwitchStorage config) private _lastAccess;

    event Recovery(address account, address nominee);

    error MissingCondition();

    function onInstall(bytes calldata data) external override {
        address owner = abi.decode(data, (address));
        owners[msg.sender] = owner;
    }

    function onUninstall(bytes calldata) external override {
        delete owners[msg.sender];
    }

    function name() external override returns (string memory) {
        return "DeadmanSwitch";
    }

    function version() external override returns (string memory) {
        return "0.0.1";
    }

    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == TYPE_HOOK;
    }
}
