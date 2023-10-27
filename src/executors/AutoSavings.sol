// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "modulekit/modulekit/ConditionalExecutorBase.sol";
import "modulekit/modulekit/integrations/uniswap/v3/UniswapSwaps.sol";
import "modulekit/modulekit/integrations/erc4626/ERC4626Deposit.sol";
import "modulekit/modulekit/interfaces/IExecutor.sol";
import "checknsignatures/CheckNSignatures.sol";

import "forge-std/console2.sol";
import "../validators/SessionKey/ISessionKeyValidationModule.sol";

struct TokenTxEvent {
    address token;
    address from;
    address to;
    uint256 amount;
}

contract AutoSavings is ConditionalExecutor, ISessionKeyValidationModule {
    using ModuleExecLib for IExecutorManager;
    using ERC4626Deposit for IERC4626;

    struct SavingsConfig {
        IERC4626 vault;
        IERC20 spendToken;
        uint256 maxAmountIn;
        uint48 lastTriggered;
        uint256 maxFee;
    }

    mapping(address account => mapping(bytes32 id => SavingsConfig)) public savingsConfig;

    mapping(address account => address) authorizedRelay;

    error InvalidConfig(address account, bytes32 id);
    error SavingNotDue(address account, bytes32 id);

    constructor(ComposableConditionManager _conditionManager)
        ConditionalExecutor(_conditionManager)
    { }

    function trigger(
        IExecutorManager manager,
        bytes32 id,
        uint256 amountIn,
        ConditionConfig[] calldata conditions
    )
        external
        onlyIfConditionsMet(msg.sender, conditions)
    {
        SavingsConfig storage config = savingsConfig[msg.sender][id];

        if (amountIn > config.maxAmountIn) revert InvalidConfig(msg.sender, id);

        // check of swap is required
        IERC20 vaultToken = IERC20(config.vault.asset());
        console2.log("vaultToken", address(vaultToken));
        IERC20 spendToken = config.spendToken;
        if (vaultToken != spendToken) {
            uint256 amountOut = spendToken.balanceOf(msg.sender);

            ExecutorAction[] memory swapActions = new ExecutorAction[](2);
            swapActions[0] = ERC20ModuleKit.approveAction({
                token: spendToken,
                to: SWAPROUTER_ADDRESS,
                amount: amountIn
            });
            swapActions[1] = UniswapSwaps.swapExactInputSingle({
                smartAccount: msg.sender, // beneficiary of the swap
                tokenIn: spendToken, // token to be sold
                tokenOut: vaultToken, // token to be bought
                amountIn: amountIn
            });

            // this execution could  be provided via calldata / storage
            manager.exec({ account: msg.sender, actions: swapActions });

            amountIn = amountOut - spendToken.balanceOf(msg.sender);
        }

        console2.log("Depositing to vault:", amountIn);
        // // deposit into vault
        config.vault.approveAndDeposit({
            manager: manager,
            account: msg.sender,
            receiver: msg.sender,
            amount: amountIn
        });
    }

    function setRelayer(address relayer) external {
        authorizedRelay[msg.sender] = relayer;
    }

    function setConfig(
        bytes32 id,
        address spendToken,
        uint256 maxAmountIn,
        IERC4626 vault
    )
        external
    {
        SavingsConfig storage config = savingsConfig[msg.sender][id];

        config.spendToken = IERC20(spendToken);
        config.maxAmountIn = maxAmountIn;
        config.vault = vault;
    }

    function validateSessionUserOp(
        UserOperation calldata _op,
        bytes32 _userOpHash,
        bytes calldata _sessionKeyData,
        bytes calldata _sessionKeySignature
    )
        external
        view
        override
        returns (bool)
    {
        address callDataTarget = address(bytes20(_op.callData[48:68]));
        console2.log(callDataTarget);
        if (callDataTarget != address(this)) revert();

        TokenTxEvent memory tokenTxEvent = abi.decode(_sessionKeyData, (TokenTxEvent));
        bytes32 tokenTxEventHash = keccak256(_sessionKeyData);
        address[] memory signers =
            CheckSignatures.recoverNSignatures(tokenTxEventHash, _sessionKeySignature, 1);
        if (signers[0] != authorizedRelay[_op.sender] && signers[0] != tokenTxEvent.to) {
            return false;
        }

        return true;
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
