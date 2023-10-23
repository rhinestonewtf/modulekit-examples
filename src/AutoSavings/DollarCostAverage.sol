// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "modulekit/modulekit/IHook.sol";
import "modulekit/core/ComposableCondition.sol";
import "modulekit/modulekit/IExecutor.sol";
import "modulekit/modulekit/ValidatorBase.sol";
import "modulekit/modulekit/integrations/uniswap/v3/UniswapSwaps.sol";
import "modulekit/modulekit/ConditionalExecutorBase.sol";

import "forge-std/interfaces/IERC20.sol";

contract DCA is ConditionalExecutor {
    using ModuleExecLib for IExecutorManager;
    using UniswapSwaps for address;

    struct DCAStrategy {
        IERC20 spendToken;
        IERC20 buyToken;
        uint256 spendAmount;
    }

    mapping(address account => mapping(uint256 => DCAStrategy)) private _dca;

    error InvalidStrategy(address account, uint256 strategyId);

    constructor(ComposableConditionManager _conditionManager)
        ConditionalExecutor(_conditionManager)
    { }

    function _triggerDCA(
        address account,
        uint256 strategyId,
        ConditionConfig[] calldata conditions
    )
        private
        view
        onlyIfConditionsMet(account, conditions)
        returns (ExecutorAction memory action)
    {
        DCAStrategy storage strategy = _dca[account][strategyId];
        if (strategy.spendAmount == 0) revert InvalidStrategy(account, strategyId);
        action = account.swapExactInputSingle(
            strategy.spendToken, strategy.buyToken, strategy.spendAmount
        );
    }

    function setStrategy(uint256 strategyId, DCAStrategy calldata strategy) external {
        _dca[msg.sender][strategyId] = strategy;
    }

    function triggerDCA(
        address account,
        IExecutorManager manager,
        uint256 strategyId,
        ConditionConfig[] calldata conditions
    )
        external
    {
        ExecutorAction[] memory actions = new ExecutorAction[](1);
        actions[0] = _triggerDCA(account, strategyId, conditions);
        manager.exec(account, actions);
    }

    function triggerDCA(
        address account,
        IExecutorManager manager,
        uint256[] calldata strategyIds,
        ConditionConfig[][] calldata conditions
    )
        external
    {
        uint256 length = strategyIds.length;
        if (length != conditions.length) revert InvalidStrategy(account, strategyIds[0]);
        ExecutorAction[] memory actions = new ExecutorAction[](length);

        for (uint256 i; i < length; i++) {
            actions[i] = _triggerDCA(account, strategyIds[i], conditions[i]);
        }
        manager.exec(account, actions);
    }

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
