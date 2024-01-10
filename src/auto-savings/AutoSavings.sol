// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "modulekit/modules/utils/ERC7579ValidatorLib.sol";
import "modulekit/core/sessionKey/ISessionValidationModule.sol";
import { ERC4626Integration } from "modulekit/integrations/ERC4626.sol";
import { ERC20Integration } from "modulekit/integrations/ERC20.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";
import { IERC7579Execution } from "modulekit/ModuleKitLib.sol";
import { ERC7579ExecutorBase } from "modulekit/Modules.sol";

contract AutoSavingToVault is ERC7579ExecutorBase, ISessionValidationModule {
    struct Params {
        address token;
        address vault;
        uint256 amount;
    }

    struct ScopedAccess {
        address sessionKeySigner;
        address onlyToken;
        address onlyVault;
    }

    struct SpentLog {
        uint128 spent;
        uint128 maxAmount;
    }

    using ERC7579ValidatorLib for *;
    using ERC4626Integration for *;

    error InvalidMethod(bytes4);
    error InvalidValue();
    error InvalidAmount();
    error InvalidTarget();
    error InvalidRecipient();

    mapping(address account => mapping(address token => SpentLog)) internal _log;

    function getSpentLog(address account, address token) public view returns (SpentLog memory) {
        return _log[account][token];
    }

    function onInstall(bytes calldata data) external override {
        (address[] memory tokens, SpentLog[] memory log) = abi.decode(data, (address[], SpentLog[]));

        for (uint256 i; i < tokens.length; i++) {
            _log[msg.sender][tokens[i]] = log[i];
        }
    }

    function onUninstall(bytes calldata data) external override { }

    function autoSave(Params calldata params) external {
        IERC4626 vault = IERC4626(params.vault);

        IERC7579Execution.Execution[] memory approveAndDeposit =
            new IERC7579Execution.Execution[](2);
        approveAndDeposit[0] =
            ERC20Integration.approve(IERC20(params.token), msg.sender, params.amount);
        approveAndDeposit[1] = ERC4626Integration.deposit(vault, params.amount, msg.sender);

        IERC7579Execution(msg.sender).executeBatchFromExecutor(approveAndDeposit);
    }

    modifier onlyThis(address destinationContract) {
        if (destinationContract != address(this)) revert InvalidTarget();
        _;
    }

    modifier onlyFunctionSig(bytes4 allowed, bytes4 received) {
        if (allowed != received) revert InvalidMethod(received);
        _;
    }

    modifier onlyZeroValue(uint256 callValue) {
        if (callValue != 0) revert InvalidValue();
        _;
    }

    function validateSessionParams(
        address destinationContract,
        uint256 callValue,
        bytes calldata callData,
        bytes calldata _sessionKeyData,
        bytes calldata /*_callSpecificData*/
    )
        public
        virtual
        override
        onlyFunctionSig(this.autoSave.selector, bytes4(callData[:4]))
        onlyZeroValue(callValue)
        onlyThis(destinationContract)
        returns (address)
    {
        ScopedAccess memory access = abi.decode(_sessionKeyData, (ScopedAccess));
        Params memory params = abi.decode(callData[4:], (Params));

        if (params.token != access.onlyToken) {
            revert InvalidRecipient();
        }

        if (params.vault != access.onlyVault) {
            revert InvalidRecipient();
        }

        return access.sessionKeySigner;
    }

    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == TYPE_EXECUTOR;
    }

    function name() external pure virtual override returns (string memory) {
        return "AutoSaving";
    }

    function version() external pure virtual override returns (string memory) {
        return "0.0.1";
    }
}
