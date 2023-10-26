// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "modulekit/modulekit/ConditionalExecutorBase.sol";
import "modulekit/modulekit/integrations/uniswap/v3/UniswapSwaps.sol";
import "modulekit/modulekit/integrations/erc4626/ERC4626Deposit.sol";
import "modulekit/modulekit/interfaces/IExecutor.sol";

import "forge-std/interfaces/IERC20.sol";
import "../validators/SessionKey/ISessionKeyValidationModule.sol";

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
        IERC20 spendToken = config.spendToken;
        if (vaultToken != spendToken) {
            uint256 amountOut = spendToken.balanceOf(msg.sender);

            // this execution could  be provided via calldata / storage
            manager.exec({
                account: msg.sender,
                action: UniswapSwaps.swapExactInputSingle({
                    smartAccount: msg.sender, // beneficiary of the swap
                    tokenIn: spendToken, // token to be sold
                    tokenOut: vaultToken, // token to be bought
                    amountIn: amountIn
                })
            });

            amountOut = spendToken.balanceOf(msg.sender) - amountOut;
            amountIn = amountOut;
        }

        // // deposit into vault
        config.vault.approveAndDeposit({
            manager: manager,
            account: msg.sender,
            receiver: msg.sender,
            amount: amountIn
        });
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
