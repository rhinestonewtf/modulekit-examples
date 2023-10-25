// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "modulekit/modulekit/ConditionalExecutorBase.sol";

import "forge-std/interfaces/IERC20.sol";

contract AutoSavingsDemo is ConditionalExecutorBase {
    struct SavingsConfig {
        IERC20 token;
        uint48 lastTriggered;
        uint16 minHoursExpired;
        address savingsAccount;
    }

    mapping(address account => mapping(bytes32 id => SavingsConfig)) public savingsConfig;

    error InvalidConfig(address account, bytes32 id);
    error SavingNotDue(address account, bytes32 id);

    constructor(ComposableConditionManager _conditionManager)
        ConditionalExecutor(_conditionManager)
    { }

    function trigger(address account, IExecutorManager manager, bytes32 id) external {
        SavingsConfig storage config = savingsConfig[account][id];
        if (address(token) == address(0)) revert InvalidConfig(account, id);

        // if user set a different savings account than his/her smart account address
        address savingsAccount = config.savingsAccount;
        savingsAccount == address(0) ? account : savingsAccount;

        // check if due
        bool due = (config.lastTriggered + config.minHoursExpired) <= block.timestamp;
        if (!due) revert SavingNotDue(account, id);
    }


}
