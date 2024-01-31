// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IERC7579Execution } from "modulekit/Accounts.sol";
import { SchedulingBase } from "./SchedulingBase.sol";
import { UniswapV3Integration } from "modulekit/Integrations.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

abstract contract ScheduledOrders is SchedulingBase {
    function executeOrder(bytes32 executionHash) external override canExecute(executionHash) {
        ExecutionConfig storage executionConfig = executionLog[msg.sender][executionHash];


        // decode from execution tokenIn, tokenOut and amount in
        (address tokenIn, address tokenOut, uint256 amountIn) =
            abi.decode(executionConfig.executionData, (address, address, uint256));

        IERC7579Execution.Execution[] memory executions = UniswapV3Integration.approveAndSwap({
            smartAccount: msg.sender,
            tokenIn: IERC20(tokenIn),
            tokenOut: IERC20(tokenOut),
            amountIn: amountIn,
            sqrtPriceLimitX96: 0 // setting zero means no limit for price to execute
         });

        IERC7579Execution(msg.sender).executeBatchFromExecutor(executions);

        executionConfig.lastExecutionTime = uint48(block.timestamp);
        executionConfig.numberOfExecutionsCompleted += 1;

        emit ExecutionTriggered(msg.sender, executionHash);
    }

    function name() external pure virtual override returns (string memory) {
        return "Scheduled Orders";
    }

    function version() external pure virtual override returns (string memory) {
        return "0.0.1";
    }
}
