// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Imports various smart contract modules and interfaces from the modulekit package and others
import "modulekit/modulekit/ConditionalExecutorBase.sol";
import "modulekit/modulekit/integrations/uniswap/v3/UniswapSwaps.sol";
import "modulekit/modulekit/integrations/erc4626/ERC4626Deposit.sol";
import "modulekit/modulekit/interfaces/IExecutor.sol";
import "checknsignatures/CheckNSignatures.sol";
import "modulekit/core/ISessionKeyValidationModule.sol";
import { ValidatorSelectionLib } from "modulekit/modulekit/lib/ValidatorSelectionLib.sol";
import "solady/utils/LibSort.sol";

// Struct definition for token transaction events
struct TokenTxEvent {
    address token;
    address to;
}
/**
 * @title AutoSavings smart contract
 * @dev This contract allows automatic savings in a specified vault based on conditions.
 */

contract AutoSavings is ConditionalExecutor, ISessionKeyValidationModule {
    using ModuleExecLib for IExecutorManager;
    using ERC4626Deposit for IERC4626;
    using ValidatorSelectionLib for UserOperation;
    using LibSort for address[];

    // Struct to hold configuration for each savings action
    struct SavingsConfig {
        IERC4626 vault;
        uint256 maxAmountIn;
        uint48 lastTriggered;
        uint16 feePercentage;
    }

    // Struct to hold information about authorized relayers
    struct AuthorizedRelay {
        address[] authorizedSigners;
        uint256 threshold;
    }

    // Maps user accounts to their respective savings configuration
    // Note: this mapping is accessed by the validator, so must athere to 4337 storage restrictions
    mapping(address account => AuthorizedRelay) authorizedRelay;

    // Maps user accounts to their respective savings configuration
    mapping(address account => mapping(bytes32 id => SavingsConfig)) public savingsConfig;

    // Custom Errors
    error InvalidConfig(address account, bytes32 id);
    error SavingNotDue(address account, bytes32 id);
    error InvalidTarget();
    error InvalidAmount();
    error InvalidToken();
    error InvalidTxEventTo();
    error InvalidFunctionSelector();

    // Event for logging autosavings transactions
    event AutoSavingsTx(
        bytes32 id,
        address vault,
        address spendToken,
        address saveToken,
        uint256 amountReceived,
        uint256 amountSaved
    );

    // Event for logging when a new relayer is authorized
    event NewRelayer(address account, address[] relayer, uint256 threshold);

    // Event for logging when a new autosavings configuration is set
    event NewSavingsConfig(bytes32 id, uint256 maxAmountIn, uint16 feePercentage, address vault);

    // Constructor to set up the condition manager
    constructor(ComposableConditionManager _conditionManager)
        ConditionalExecutor(_conditionManager)
    { }

    /**
     * @dev Triggers the auto-saving mechanism based on predefined conditions.
     * @param spendToken The token to be spent.
     * @param manager The execution manager to use for executing transactions.
     * @param id The unique identifier for the savings configuration.
     * @param amountTransfered The amount of spendToken to be transferred.
     * @param conditions An array of conditions that need to be met to execute the saving.
     */
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

        // Calculate the amount to transfer with fee consideration
        uint256 amountIn = config.feePercentage * amountTransfered / 10_000;
        if (amountIn > config.maxAmountIn) revert InvalidConfig(msg.sender, id);

        // Check if a swap is required and execute it
        IERC20 vaultToken = IERC20(config.vault.asset());
        if (vaultToken != spendToken) {
            // Perform token swap if necessary
            // get current account balance of underlying vault token
            uint256 amountOut = vaultToken.balanceOf(msg.sender);

            // prepare a batched ExecutorAction that both approves ERC20 and calls Uniswap
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
            // execute swap
            manager.exec({ account: msg.sender, actions: swapActions });

            // get balance of underlying vault token after swap.
            // amountIn will now be the exact value that was yielded in the DEX swap
            amountIn = vaultToken.balanceOf(msg.sender) - amountOut;
        }

        // gained amount will now be deposited into vault using ModuleKits ERC4626 integration
        config.vault.approveAndDeposit({
            manager: manager,
            account: msg.sender,
            receiver: msg.sender,
            amount: amountIn
        });

        // emitting event
        emit AutoSavingsTx({
            id: id,
            vault: address(config.vault),
            spendToken: address(spendToken),
            saveToken: address(vaultToken),
            amountReceived: amountTransfered,
            amountSaved: amountIn
        });
    }

    /**
     * @notice Sets the relayer configuration for the calling account.
     * @param relayer The array of addresses designated as relayers.
     * @param threshold The number of required signatures to authorize a transaction.
     */
    function setRelayer(address[] memory relayer, uint256 threshold) external {
        // Ensure all relayers are unique and sorted
        relayer.uniquifySorted();

        if (relayer.length < threshold) revert InvalidConfig(msg.sender, 0);

        // Update the storage with the new relayer information
        AuthorizedRelay storage authorizedRelayRecord = authorizedRelay[msg.sender];
        authorizedRelayRecord.threshold = threshold;
        authorizedRelayRecord.authorizedSigners = relayer;

        // Emit event. new relayer is set
        emit NewRelayer(msg.sender, relayer, threshold);
    }

    /**
     * @notice Sets the savings configuration for the caller's account.
     * @param id The unique identifier for the savings configuration.
     * @param maxAmountIn The maximum amount that can be transferred in.
     * @param feePercentage The percentage fee applied to the transaction.
     * @param vault The vault in which the funds will be saved.
     */
    function setConfig(
        bytes32 id,
        uint256 maxAmountIn,
        uint16 feePercentage,
        IERC4626 vault
    )
        external
    {
        // Retrieve the caller's savings config from storage and update it
        SavingsConfig storage config = savingsConfig[msg.sender][id];

        config.maxAmountIn = maxAmountIn;
        config.vault = vault;
        config.feePercentage = feePercentage;
        // Note: The `lastTriggered` field is not updated here

        emit NewSavingsConfig(id, maxAmountIn, feePercentage, address(vault));
    }
    /**
     * @notice Validates a user operation involving a session key.
     * @dev  This SessionKey Validator only allows transaction to itself, not to other modules/contracts
     *          This Validator will check that only address(this) and trigger() function are called.
     * @param _op The user operation to validate.
     * @param _userOpHash The hash of the user operation.
     * @param _sessionKeyData The session key data related to the operation.
     * @param _sessionKeySignature The signature corresponding to the session key.
     * @param target The target contract of the user operation.
     * @param _offset The offset in the calldata where the operation is defined.
     * @return bool Returns true if the session user operation is valid.
     */

    function validateSessionUserOp(
        UserOperation calldata _op,
        bytes32 _userOpHash,
        bytes calldata _sessionKeyData,
        bytes calldata _sessionKeySignature,
        address target,
        uint256 _offset
    )
        external
        view
        override
        returns (bool)
    {
        // ensure that only this contract is called. No other external contracts shall be authorized.
        if (address(this) != target) revert InvalidTarget();
        // get function sig and call data from userOp according to offset.
        (bytes4 functionSig, bytes calldata triggerCallData) = _op.getUserOpCallData(_offset);
        TokenTxEvent memory tokenTxEvent;
        {
            // decode TokenTxEvent data from SessionKeyData. See SessionKeyManager.sol
            tokenTxEvent = abi.decode(_sessionKeyData, (TokenTxEvent));

            address spendToken = address(bytes20(triggerCallData[12:32]));

            // ensure that trigger(spendToken,,,,) is the same token as specified in the TokenTxEvent
            if (tokenTxEvent.token != spendToken) revert InvalidToken();
            // ensure that the SessionKeyValidator only allows calls to the trigger function
            if (functionSig != this.trigger.selector) revert InvalidFunctionSelector();
            // ensure that TokenTxEvent is an event where the account owner actually received tokens.
            if (tokenTxEvent.to != _op.sender) revert InvalidTxEventTo();
        }

        AuthorizedRelay storage authorizedRelayRecord = authorizedRelay[_op.sender];
        address[] memory recoveredSigners = CheckSignatures.recoverNSignatures({
            dataHash: keccak256(_sessionKeyData), // hash of TokenTxEvent
            signatures: _sessionKeySignature, // signature that was provided by SessionKeyManager
            requiredSignatures: authorizedRelayRecord.threshold // threshold of signatures that are required according to user
         });

        // ensure that recovered signers are unique. Malicious Actor could sign multiple times with same address
        recoveredSigners.uniquifySorted();

        // ensure that recovered signers are authorized by user
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
