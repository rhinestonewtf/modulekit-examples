// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

// Inspired by https://github.com/roleengineer/token-withdrawal-module/blob/master/src/TokenWithdrawalModule.sol

import { ExecutorBase } from "modulekit/modulekit/ExecutorBase.sol";
import {
    IExecutorManager,
    ExecutorAction,
    ModuleExecLib
} from "modulekit/modulekit/interfaces/IExecutor.sol";
import { ERC20ModuleKit } from "modulekit/modulekit/integrations/ERC20Actions.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

struct Withdrawal {
    address payable beneficiary;
    uint256 value;
    address tokenAddress;
    uint16 frequency; // in days
    uint48 lastExecuted;
}

contract PullPayment is ExecutorBase {
    using ModuleExecLib for IExecutorManager;

    mapping(address account => address relayer) public relayers;
    mapping(address account => Withdrawal[] withdrawals) public withdrawals;

    event WithdrawalScheduled(address indexed account, address indexed beneficiary, uint256 index);

    event WithdrawalExecuted(address indexed account, address indexed beneficiary, uint256 index);

    error OnlyRelayer();
    error WithdrawalNotDue(address account);

    function executeWithdrawal(
        IExecutorManager manager,
        address account,
        uint256 withdrawalIndex
    )
        external
        onlyRelayer(account)
    {
        Withdrawal storage withdrawal = withdrawals[account][withdrawalIndex];

        if (!_withdrawalIsDue(withdrawal)) {
            revert WithdrawalNotDue(account);
        }
        withdrawal.lastExecuted = uint48(block.timestamp);

        ExecutorAction memory action;

        if (withdrawal.tokenAddress != address(0)) {
            action = ERC20ModuleKit.transferAction({
                token: IERC20(withdrawal.tokenAddress),
                to: withdrawal.beneficiary,
                amount: withdrawal.value
            });
        } else {
            action =
                ExecutorAction({ to: withdrawal.beneficiary, data: "", value: withdrawal.value });
        }
        manager.exec(account, action);

        emit WithdrawalExecuted(account, withdrawal.beneficiary, withdrawalIndex);
    }

    function setRelayer(address relayer) external {
        relayers[msg.sender] = relayer;
    }

    function addWithdrawal(
        address payable beneficiary,
        uint256 value,
        address tokenAddress,
        uint16 frequency
    )
        external
        returns (uint256 index)
    {
        index = withdrawals[msg.sender].length;
        withdrawals[msg.sender].push(
            Withdrawal({
                beneficiary: beneficiary,
                value: value,
                tokenAddress: tokenAddress,
                frequency: frequency,
                lastExecuted: 0
            })
        );
        emit WithdrawalScheduled(msg.sender, beneficiary, index);
    }

    function _withdrawalIsDue(Withdrawal storage withdrawal) internal view returns (bool) {
        // Question: should we initially set lastExecuted to block.timestamp so that first execution occurs on setup time + frequency?
        if (withdrawal.lastExecuted == 0) {
            return true;
        } else if (withdrawal.frequency == 0) {
            return false;
        } else {
            return block.timestamp > withdrawal.lastExecuted + withdrawal.frequency * 1 days;
        }
    }

    modifier onlyRelayer(address account) {
        if (msg.sender != relayers[account]) revert OnlyRelayer();
        _;
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
