// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IERC7579Execution } from "modulekit/Accounts.sol";
import { SchedulingBase } from "./SchedulingBase.sol";

abstract contract ScheduledTransfers is SchedulingBase {
    function executeOrder(uint128 jobId) external override canExecute(jobId) {
        ExecutionConfig storage executionConfig = _executionLog[msg.sender][jobId];

        IERC7579Execution.Execution memory execution =
            abi.decode(executionConfig.executionData, (IERC7579Execution.Execution));

        executionConfig.lastExecutionTime = uint48(block.timestamp);
        executionConfig.numberOfExecutionsCompleted += 1;

        IERC7579Execution(msg.sender).executeFromExecutor(
            execution.target, execution.value, execution.callData
        );

        emit ExecutionTriggered(msg.sender, jobId);
    }

    function name() external pure virtual override returns (string memory) {
        return "Scheduled Transfers";
    }

    function version() external pure virtual override returns (string memory) {
        return "0.0.1";
    }
}
