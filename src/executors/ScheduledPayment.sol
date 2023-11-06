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

struct Payment {
    address payable beneficiary;
    uint256 amount;
    address tokenAddress;
    uint16 frequency; // in days
    uint48 lastExecuted;
}

contract ScheduledPayment is ExecutorBase {
    using ModuleExecLib for IExecutorManager;

    mapping(address account => address relayer) public relayers;
    mapping(address account => Payment[] payment) public payments;

    event PaymentScheduled(address indexed account, address indexed beneficiary, uint256 index);

    event PaymentExecuted(address indexed account, address indexed beneficiary, uint256 index);

    event RelayerSet(address indexed account, address indexed relayer);

    error OnlyRelayer();
    error PaymentNotDue(address account);
    error InvalidConfig();

    function executePayment(
        IExecutorManager manager,
        address account,
        uint256 paymentIndex
    )
        external
        onlyRelayer(account)
    {
        Payment storage payment = payments[account][paymentIndex];

        if (!_paymentIsDue(payment)) {
            revert PaymentNotDue(account);
        }
        address tokenAddress = payment.tokenAddress;
        payment.lastExecuted = uint48(block.timestamp);

        ExecutorAction memory action;

        address payable beneficiary = payment.beneficiary;

        if (tokenAddress == Denominations.ETH) {
            action = ExecutorAction({ to: beneficiary, data: "", value: payment.amount });
        } else {
            action = ERC20ModuleKit.transferAction({
                token: IERC20(tokenAddress),
                to: beneficiary,
                amount: payment.amount
            });
        }
        manager.exec(account, action);

        emit PaymentExecuted(account, beneficiary, paymentIndex);
    }

    function setRelayer(address relayer) external {
        relayers[msg.sender] = relayer;

        emit RelayerSet(msg.sender, relayer);
    }

    function addPayment(
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
        index = payments[msg.sender].length;
        payments[msg.sender].push(
            Payment({
                beneficiary: beneficiary,
                amount: amount,
                tokenAddress: tokenAddress,
                frequency: frequency,
                lastExecuted: uint48(block.timestamp)
            })
        );
        emit PaymentScheduled(msg.sender, beneficiary, index);
    }

    function removePayment(uint256 index) external {
        // NOT IMPLEMENTED. THIS EXECUTOR IS JUST AN EXAMPLE.
    }

    function _paymentIsDue(Payment storage payment) internal view returns (bool) {
        return block.timestamp > payment.lastExecuted + payment.frequency * 1 days;
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
