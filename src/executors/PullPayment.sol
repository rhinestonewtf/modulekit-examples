// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

// Inspired by https://github.com/roleengineer/token-withdrawal-module/blob/master/src/TokenWithdrawalModule.sol

import { ExecutorBase } from "modulekit/modulekit/ExecutorBase.sol";
import { Denominations } from "modulekit/modulekit/integrations/Denominations.sol";
import {
    IExecutorManager,
    ExecutorAction,
    ModuleExecLib
} from "modulekit/modulekit/interfaces/IExecutor.sol";
import { ERC20ModuleKit } from "modulekit/modulekit/integrations/ERC20Actions.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

struct Withdrawal {
    address payable beneficiary;
    uint256 amount;
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

    event RelayerSet(address indexed account, address indexed relayer);

    error OnlyRelayer();
    error WithdrawalNotDue(address account);
    error InvalidConfig();

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
        address tokenAddress = withdrawal.tokenAddress;
        if (tokenAddress == address(0)) revert WithdrawalNotDue(account);
        withdrawal.lastExecuted = uint48(block.timestamp);

        ExecutorAction memory action;

        if (tokenAddress == Denominations.ETH) {
            action =
                ExecutorAction({ to: withdrawal.beneficiary, data: "", value: withdrawal.amount });
        } else {
            action = ERC20ModuleKit.transferAction({
                token: IERC20(withdrawal.tokenAddress),
                to: withdrawal.beneficiary,
                amount: withdrawal.amount
            });
        }
        manager.exec(account, action);

        emit WithdrawalExecuted(account, withdrawal.beneficiary, withdrawalIndex);
    }

    function setRelayer(address relayer) external {
        relayers[msg.sender] = relayer;

        emit RelayerSet(msg.sender, relayer);
    }

    function addWithdrawal(
        address payable beneficiary,
        uint256 amount,
        address tokenAddress,
        uint16 frequency
    )
        external
        returns (uint256 index)
    {
        if (tokenAddress == address(0)) revert InvalidConfig();
        if (beneficiary == address(0)) revert InvalidConfig();
        if (frequency == 0) revert InvalidConfig();
        index = withdrawals[msg.sender].length;
        withdrawals[msg.sender].push(
            Withdrawal({
                beneficiary: beneficiary,
                amount: amount,
                tokenAddress: tokenAddress,
                frequency: frequency,
                lastExecuted: uint48(block.timestamp)
            })
        );
        emit WithdrawalScheduled(msg.sender, beneficiary, index);
    }

    function removeWithdrawal(uint256 index) external {
        // NOT IMPLEMENTED. THIS EXECUTOR IS JUST AN EXAMPLE.
    }

    function _withdrawalIsDue(Withdrawal storage withdrawal) internal view returns (bool) {
        return block.timestamp > withdrawal.lastExecuted + withdrawal.frequency * 1 days;
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
