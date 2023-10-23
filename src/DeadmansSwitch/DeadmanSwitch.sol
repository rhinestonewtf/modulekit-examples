// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "modulekit/modulekit/IHook.sol";
import "modulekit/core/ComposableCondition.sol";
import "modulekit/modulekit/IExecutor.sol";
import "modulekit/modulekit/ValidatorBase.sol";
import "modulekit/modulekit/ConditionalExecutorBase.sol";

struct DeadmansSwitchParams {
    uint256 timeout;
}

contract DeadmanSwitch is IHook, ICondition, ConditionalExecutor {
    struct DeadmanSwitchStorage {
        uint256 lastAccess;
        address nominee;
    }

    mapping(address account => DeadmanSwitchStorage) private _lastAccess;

    event Recovery(address account, address nominee);

    error MissingCondition();

    constructor(ComposableConditionManager _conditionManager)
        ConditionalExecutor(_conditionManager)
    { }

    modifier onlyNominee(address account) {
        require(
            _lastAccess[account].nominee == msg.sender,
            "DeadmanSwitch: Only nominee can call this function"
        );
        _;
    }

    function lastAccess(address account) external view returns (uint256) {
        return _lastAccess[account].lastAccess;
    }

    // IHook functions
    function preCheck(
        address account,
        ExecutorTransaction calldata,
        uint256,
        bytes calldata
    )
        external
        override
        returns (bytes memory)
    {
        _lastAccess[account].lastAccess = block.timestamp;
    }

    // IHook functions
    function preCheckRootAccess(
        address account,
        ExecutorTransaction calldata rootAccess,
        uint256 executionType,
        bytes calldata executionMeta
    )
        external
        override
        returns (bytes memory preCheckData)
    { }

    // IHook functions
    function postCheck(
        address account,
        bool success,
        bytes calldata preCheckData
    )
        external
        override
    { }

    // IExecutor trigger
    function recover(
        address account,
        IExecutorManager manager,
        ExecutorTransaction calldata recovery,
        ConditionConfig[] calldata conditions
    )
        external
        onlyIfConditionsMet(account, conditions)
        onlyNominee(account)
    {
        if (!_enforceThisCondition(address(this), conditions)) revert MissingCondition();
        manager.executeTransaction(account, recovery);

        emit Recovery(account, msg.sender);
    }

    function _enforceThisCondition(
        address checkIfEnabledCondition,
        ConditionConfig[] calldata conditions
    )
        private
        pure
        returns (bool isEnabled)
    {
        for (uint256 i = 0; i < conditions.length; i++) {
            if (address(conditions[i].condition) == checkIfEnabledCondition) {
                return true;
            }
        }
    }

    // ICondition
    function checkCondition(
        address account,
        address,
        bytes calldata conditions,
        bytes calldata
    )
        external
        view
        override
        returns (bool)
    {
        DeadmansSwitchParams memory params = abi.decode(conditions, (DeadmansSwitchParams));
        return block.timestamp + params.timeout >= _lastAccess[account].lastAccess;
    }

    function supportsInterface(bytes4 interfaceID) external view override returns (bool) { }

    function name() external view override returns (string memory name) { }

    function version() external view override returns (string memory version) { }

    function metadataProvider()
        external
        view
        override
        returns (uint256 providerType, bytes memory location)
    { }

    function requiresRootAccess() external view override returns (bool requiresRootAccess) { }
}
