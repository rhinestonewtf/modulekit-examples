// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { ISessionValidationModule } from "modulekit/core/sessionKey/ISessionValidationModule.sol";
import { ERC7579ExecutorBase } from "modulekit/Modules.sol";
import { IERC7579Execution } from "modulekit/ModuleKitLib.sol";

import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import {
    ERC20Integration, ERC4626Integration, UniswapV3Integration
} from "modulekit/Integrations.sol";

// Struct definition for token transaction events
struct TokenTxEvent {
    address token;
    address to;
}
/**
 * @title AutoSavings smart contract
 * @dev This contract allows automatic savings in a specified vault based on conditions.
 */

contract AutoSavings is ISessionValidationModule, ERC7579ExecutorBase {
    // Struct to hold configuration for each savings action
    struct SavingsConfig {
        IERC4626 vault;
        uint256 maxAmountIn;
        uint16 feePercentage;
        uint48 lastTriggered;
    }

    struct SessionKeyAccess {
        address sessionKeySigner;
        address token;
        bytes32 id;
        uint128 maxAmount;
    }

    struct Params {
        IERC20 spendToken;
        bytes32 id;
        uint256 amountIn;
    }

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

    function onInstall(bytes calldata data) external override { }

    function onUninstall(bytes calldata) external override { }

    function trigger(Params calldata params) external {
        SavingsConfig storage config = savingsConfig[msg.sender][params.id];

        uint256 amountIn = params.amountIn;

        if (amountIn > config.maxAmountIn) revert InvalidConfig(msg.sender, params.id);

        // Check if a swap is required and execute it
        IERC20 vaultToken = IERC20(config.vault.asset());
        if (vaultToken != params.spendToken) {
            IERC7579Execution.Execution[] memory approvalAndSwap = UniswapV3Integration
                .approveAndSwap({
                smartAccount: msg.sender, // beneficiary of the swap
                tokenIn: params.spendToken, // token to be sold
                tokenOut: vaultToken, // token to be bought
                amountIn: amountIn,
                sqrtPriceLimitX96: 0
            });
            bytes[] memory retDatas =
                IERC7579Execution(msg.sender).executeBatchFromExecutor(approvalAndSwap);
            amountIn = abi.decode(retDatas[1], (uint256));
        }

        IERC7579Execution.Execution[] memory depositIntoVault = new IERC7579Execution.Execution[](2);
        depositIntoVault[0] = ERC20Integration.approve({
            token: vaultToken,
            spender: address(config.vault),
            amount: amountIn
        });
        depositIntoVault[1] = ERC4626Integration.deposit({
            vault: config.vault,
            assets: amountIn,
            receiver: msg.sender
        });

        IERC7579Execution(msg.sender).executeBatchFromExecutor(depositIntoVault);
        // emitting event
        emit AutoSavingsTx({
            id: params.id,
            vault: address(config.vault),
            spendToken: address(params.spendToken),
            saveToken: address(vaultToken),
            amountReceived: params.amountIn,
            amountSaved: amountIn
        });
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

    function validateSessionParams(
        address to,
        uint256 value,
        bytes calldata callData,
        bytes calldata sessionKeyData,
        bytes calldata
    )
        external
        returns (address)
    {
        Params memory params = abi.decode(callData[4:], (Params));
        SessionKeyAccess memory sessionkeyAccess = abi.decode(sessionKeyData, (SessionKeyAccess));
        bytes4 functionSig = bytes4(callData[:4]);
        if (functionSig != this.trigger.selector) revert InvalidFunctionSelector();
        if (to != address(this)) revert InvalidTarget();
        if (value != 0) revert InvalidAmount();

        // ensure that params are in scope of sessionKey
        if (address(params.spendToken) != sessionkeyAccess.token) revert InvalidToken();
        if (params.id != sessionkeyAccess.id) revert();
        if (params.amountIn > sessionkeyAccess.maxAmount) revert InvalidAmount();
    }

    function name() external pure override returns (string memory name) {
        return "AutoSavings";
    }

    function version() external pure override returns (string memory version) {
        return "0.0.1";
    }

    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == TYPE_EXECUTOR;
    }
}
