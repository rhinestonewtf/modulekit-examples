// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "modulekit/core/sessionKey/ISessionValidationModule.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IERC7579Execution } from "modulekit/Accounts.sol";
import { ERC7579ExecutorBase } from "modulekit/Modules.sol";

contract TimeLock {
    struct TimeLockLog {
        uint48 lastRan;
        uint48 interval; // in seconds
    }

    mapping(address smartAccount => mapping(uint256 jobId => TimeLockLog)) public timeLockLog;

    function logTime(address smartAccount, uint256 jobId) internal {
        timeLockLog[smartAccount][jobId].lastRan = uint48(block.timestamp);
    }

    function safeLogTime(address smartAccount, uint256 jobId) internal {
        TimeLockLog storage log = timeLockLog[smartAccount][jobId];

        if (log.lastRan + log.interval < block.timestamp) {
            log.lastRan = uint48(block.timestamp);
        } else {
            revert();
        }
    }

    function setInterval(address smartAccount, uint256 jobId, uint48 interval) internal {
        timeLockLog[smartAccount][jobId].interval = interval;
    }
}

contract ScheduledTransaction is TimeLock, ERC7579ExecutorBase, ISessionValidationModule {
    struct ExecutorAccess {
        address sessionKeySigner;
        uint128 jobId;
    }

    struct Config {
        bytes execution;
    }

    struct Params {
        uint256 jobId;
    }

    error InvalidMethod(bytes4);
    error InvalidValue();
    error InvalidAmount();
    error InvalidTarget();
    error InvalidRecipient();

    mapping(address account => mapping(uint256 jobId => Config)) internal _log;

    function getScheduleConfig(
        address account,
        uint256 jobId
    )
        public
        view
        returns (Config memory)
    {
        return _log[account][jobId];
    }

    function execScheduledTx(Params calldata params) external {
        IERC7579Execution smartAccount = IERC7579Execution(msg.sender);

        Config storage log = _log[msg.sender][params.jobId];
        safeLogTime(msg.sender, params.jobId);

        IERC7579Execution.Execution[] memory executions =
            abi.decode(log.execution, (IERC7579Execution.Execution[]));
        smartAccount.executeBatchFromExecutor(executions);
    }

    function validateSessionParams(
        address destinationContract,
        uint256 callValue,
        bytes calldata callData,
        bytes calldata _sessionKeyData,
        bytes calldata /*_callSpecificData*/
    )
        public
        virtual
        override
        returns (address)
    {
        ExecutorAccess memory access = abi.decode(_sessionKeyData, (ExecutorAccess));

        bytes4 targetSelector = bytes4(callData[:4]);
        Params memory params = abi.decode(callData[4:], (Params));
        if (targetSelector != this.execScheduledTx.selector) {
            revert InvalidMethod(targetSelector);
        }

        if (params.jobId != access.jobId) {
            revert InvalidRecipient();
        }

        if (destinationContract != address(this)) {
            revert InvalidTarget();
        }

        if (callValue != 0) {
            revert InvalidValue();
        }

        return access.sessionKeySigner;
    }

    function onInstall(bytes calldata data) external override {
        if (data.length == 0) return;
        (uint256 jobId, IERC7579Execution.Execution[] memory executions) =
            abi.decode(data, (uint256, IERC7579Execution.Execution[]));
        _log[msg.sender][jobId] = Config({ execution: abi.encode(executions) });
    }

    function onUninstall(bytes calldata data) external override { }

    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == TYPE_EXECUTOR;
    }

    function name() external pure virtual override returns (string memory) {
        return "Scheduled Transaction";
    }

    function version() external pure virtual override returns (string memory) {
        return "0.0.1";
    }
}
