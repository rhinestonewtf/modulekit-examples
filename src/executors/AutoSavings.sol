// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "modulekit/modulekit/ConditionalExecutorBase.sol";
import "modulekit/modulekit/integrations/uniswap/v3/UniswapSwaps.sol";
import "modulekit/modulekit/integrations/erc4626/ERC4626Deposit.sol";
import "modulekit/modulekit/interfaces/IExecutor.sol";
import "checknsignatures/CheckNSignatures.sol";

import "../validators/SessionKey/ISessionKeyValidationModule.sol";

import "solady/utils/LibSort.sol";

struct TokenTxEvent {
    address token;
    address to;
}

contract AutoSavings is ConditionalExecutor, ISessionKeyValidationModule {
    using ModuleExecLib for IExecutorManager;
    using ERC4626Deposit for IERC4626;
    using LibSort for address[];

    struct SavingsConfig {
        IERC4626 vault;
        uint256 maxAmountIn;
        uint48 lastTriggered;
        uint16 feePercentage;
        uint256 maxFee;
    }

    struct AuthorizedRelay {
        address[] authorizedSigners;
        uint256 threshold;
    }

    mapping(address account => mapping(bytes32 id => SavingsConfig)) public savingsConfig;

    mapping(address account => AuthorizedRelay) authorizedRelay;

    error InvalidConfig(address account, bytes32 id);
    error SavingNotDue(address account, bytes32 id);
    error InvalidTarget();
    error InvalidAmount();
    error InvalidToken();
    error InvalidTxEventTo();
    error InvalidFunctionSelector();

    event AutoSavingsTx(
        bytes32 id,
        address vault,
        address spendToken,
        address saveToken,
        uint256 amountReceived,
        uint256 amountSaved
    );
    event NewRelayer(address account, address[] relayer, uint256 threshold);

    constructor(ComposableConditionManager _conditionManager)
        ConditionalExecutor(_conditionManager)
    { }

    function trigger(
        IERC20 spendToken,
        IExecutorManager manager,
        bytes32 id,
        uint256 amountTransfered,
        ConditionConfig[] calldata conditions
    )
        external
        onlyIfConditionsMet(msg.sender, conditions)
    {
        SavingsConfig storage config = savingsConfig[msg.sender][id];

        uint256 amountIn = config.feePercentage * amountTransfered / 10_000;
        if (amountIn > config.maxAmountIn) revert InvalidConfig(msg.sender, id);

        // check of swap is required
        IERC20 vaultToken = IERC20(config.vault.asset());
        if (vaultToken != spendToken) {
            uint256 amountOut = vaultToken.balanceOf(msg.sender);

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

            amountIn = vaultToken.balanceOf(msg.sender) - amountOut;
        }

        // // deposit into vault
        config.vault.approveAndDeposit({
            manager: manager,
            account: msg.sender,
            receiver: msg.sender,
            amount: amountIn
        });

        emit AutoSavingsTx({
            id: id,
            vault: address(config.vault),
            spendToken: address(spendToken),
            saveToken: address(vaultToken),
            amountReceived: amountTransfered,
            amountSaved: amountIn
        });
    }

    function setRelayer(address[] memory relayer, uint256 threshold) external {
        relayer.uniquifySorted();

        if (relayer.length < threshold) revert InvalidConfig(msg.sender, 0);

        AuthorizedRelay storage authorizedRelayRecord = authorizedRelay[msg.sender];
        authorizedRelayRecord.threshold = threshold;
        authorizedRelayRecord.authorizedSigners = relayer;

        emit NewRelayer(msg.sender, relayer, threshold);
    }

    function setConfig(
        bytes32 id,
        uint256 maxAmountIn,
        uint16 feePercentage,
        IERC4626 vault
    )
        external
    {
        SavingsConfig storage config = savingsConfig[msg.sender][id];

        config.maxAmountIn = maxAmountIn;
        config.vault = vault;
        config.feePercentage = feePercentage;
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
        {
            if (address(this) != address(bytes20(_op.callData[48:68]))) revert InvalidTarget();
        }

        bytes calldata triggerCallData = (_op.callData[164:]);
        TokenTxEvent memory tokenTxEvent;
        {
            bytes4 functionSig = bytes4(triggerCallData[0:4]);
            address spendToken = address(bytes20(triggerCallData[16:36]));
            //uint256 amountIn = uint256(bytes32(triggerCallData[100:132]));

            tokenTxEvent = abi.decode(_sessionKeyData, (TokenTxEvent));
            //if (tokenTxEvent.amount != amountIn) revert InvalidAmount();
            if (tokenTxEvent.token != spendToken) revert InvalidToken();
            if (functionSig != this.trigger.selector) revert InvalidFunctionSelector();

            if (tokenTxEvent.to != _op.sender) revert InvalidTxEventTo();
        }

        AuthorizedRelay storage authorizedRelayRecord = authorizedRelay[_op.sender];
        address[] memory recoveredSigners = CheckSignatures.recoverNSignatures({
            dataHash: keccak256(_sessionKeyData),
            signatures: _sessionKeySignature,
            requiredSignatures: authorizedRelayRecord.threshold
        });

        recoveredSigners.uniquifySorted();

        address[] memory authorizedRecoveredSigners =
            recoveredSigners.intersection(authorizedRelayRecord.authorizedSigners);

        if (authorizedRecoveredSigners.length >= authorizedRelayRecord.threshold) {
            return true;
        }

        return false;
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
