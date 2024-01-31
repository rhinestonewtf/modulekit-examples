// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "modulekit/core/sessionKey/ISessionValidationModule.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC7579Execution} from "modulekit/Accounts.sol";
import {ERC7579ExecutorBase} from "modulekit/Modules.sol";
import "modulekit/core/sessionKey/ISessionValidationModule.sol";

abstract contract SchedulingBase is
    ERC7579ExecutorBase,
    ISessionValidationModule
{
    error InvalidExecution();
    error InvalidMethod(bytes4);
    error InvalidValue();
    error InvalidAmount();
    error InvalidTarget();
    error InvalidRecipient();

    error InvalidJob();

    event ExecutionAdded(address indexed smartAccount, uint128 indexed jobId);

    event ExecutionTriggered(
        address indexed smartAccount,
        uint128 indexed jobId
    );

    event ExecutionCancelled(
        address indexed smartAccount,
        uint128 indexed jobId
    );

    mapping(address smartAccount => mapping(uint128 jobId => ExecutionConfig))
        internal _executionLog;

    mapping(address smartAccount => uint128 jobCount) internal _accountJobCount;

    struct ExecutionConfig {
        uint48 executeInterval;
        uint16 numberOfExecutions;
        uint16 numberOfExecutionsCompleted;
        uint48 startDate;
        uint160 sqrtPriceLimitX96;
        bool isEnabled;
        uint48 lastExecutionTime;
        bytes executionData;
    }

    struct ExecutorAccess {
        address sessionKeySigner;
        uint128 jobId;
    }

    struct Params {
        uint128 jobId;
    }

    function _isExecutionValid(uint128 jobId) internal view {
        ExecutionConfig storage executionConfig = _executionLog[msg.sender][
            jobId
        ];

        if (!executionConfig.isEnabled) {
            revert InvalidExecution();
        }

        if (
            executionConfig.lastExecutionTime +
                executionConfig.executeInterval <
            block.timestamp
        ) {
            revert InvalidExecution();
        }
        if (
            executionConfig.numberOfExecutionsCompleted >=
            executionConfig.numberOfExecutions
        ) {
            revert InvalidExecution();
        }
        if (executionConfig.startDate > block.timestamp) {
            revert InvalidExecution();
        }
    }

    modifier canExecute(uint128 jobId) {
        _isExecutionValid(jobId);
        _;
    }

    // abstract methohd to be implemented by the inheriting contract
    function executeOrder(uint128 jobId) external virtual;

    function createExecution(ExecutionConfig calldata data) internal {
        uint128 jobId = _accountJobCount[msg.sender] + 1;

        _executionLog[msg.sender][jobId] = ExecutionConfig({
            numberOfExecutionsCompleted: data.numberOfExecutionsCompleted,
            executeInterval: data.executeInterval,
            numberOfExecutions: data.numberOfExecutions,
            startDate: data.startDate,
            isEnabled: true,
            lastExecutionTime: data.lastExecutionTime,
            executionData: data.executionData,
            sqrtPriceLimitX96: data.sqrtPriceLimitX96
        });

        emit ExecutionAdded(msg.sender, jobId);
    }

    function addOrder(ExecutionConfig calldata executionConfig) external {
        createExecution(executionConfig);
    }

    function cancelOrder(uint128 jobId) external {
        ExecutionConfig storage executionConfig = _executionLog[msg.sender][
            jobId
        ];
        executionConfig.isEnabled = false;
        emit ExecutionCancelled(msg.sender, jobId);
    }

    function validateSessionParams(
        address destinationContract,
        uint256 callValue,
        bytes calldata callData,
        bytes calldata _sessionKeyData,
        bytes calldata /*_callSpecificData*/
    ) public virtual override returns (address) {
        ExecutorAccess memory access = abi.decode(
            _sessionKeyData,
            (ExecutorAccess)
        );

        bytes4 targetSelector = bytes4(callData[:4]);

        Params memory params = abi.decode(callData[4:], (Params));
        if (targetSelector != this.executeOrder.selector) {
            revert InvalidMethod(targetSelector);
        }

        if (params.jobId != access.jobId) {
            revert InvalidJob();
        }

        if (destinationContract != address(this)) {
            revert InvalidRecipient();
        }

        if (callValue != 0) {
            revert InvalidValue();
        }

        return access.sessionKeySigner;
    }

    function onInstall(bytes calldata data) external override {
        // ToDo: check if module already installed

        ExecutionConfig memory executionConfig = abi.decode(
            data,
            (ExecutionConfig)
        );

        uint128 jobId = _accountJobCount[msg.sender] + 1;

        _executionLog[msg.sender][jobId] = ExecutionConfig({
            numberOfExecutionsCompleted: executionConfig
                .numberOfExecutionsCompleted,
            executeInterval: executionConfig.executeInterval,
            numberOfExecutions: executionConfig.numberOfExecutions,
            startDate: executionConfig.startDate,
            isEnabled: true,
            lastExecutionTime: executionConfig.lastExecutionTime,
            executionData: executionConfig.executionData,
            sqrtPriceLimitX96: executionConfig.sqrtPriceLimitX96
        });
    }

    function onUninstall() external {
        uint128 count = _accountJobCount[msg.sender];
        for (uint128 i = 1; i <= count; i++) {
            delete _executionLog[msg.sender][i];
        }
        _accountJobCount[msg.sender] = 0;
    }

    function isModuleType(
        uint256 typeID
    ) external pure override returns (bool) {
        return typeID == TYPE_EXECUTOR;
    }
}
