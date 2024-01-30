// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IERC7579Execution } from "modulekit/Accounts.sol";
import { SchedulingBase } from "./SchedulingBase.sol";

abstract contract ScheduledTransfers is SchedulingBase {
    function executeOrder(bytes32 executionHash) external override canExecute(executionHash) {
        ExecutionConfig storage executionConfig = executionLog[msg.sender][executionHash];

        IERC7579Execution smartAccount = IERC7579Execution(msg.sender);

        IERC7579Execution.Execution memory execution =
            abi.decode(executionConfig.executionData, (IERC7579Execution.Execution));

        smartAccount.executeFromExecutor(execution.target, execution.value, execution.callData);

        executionConfig.lastExecutionTime = uint48(block.timestamp);
        executionConfig.numberOfExecutionsCompleted += 1;

        emit ExecutionTriggered(msg.sender, executionHash);
    }

    function name() external pure virtual override returns (string memory) {
        return "Scheduled Transfers";
    }

    function version() external pure virtual override returns (string memory) {
        return "0.0.1";
    }
}
