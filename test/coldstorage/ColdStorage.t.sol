// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "modulekit/ModuleKit.sol";
import "modulekit/Modules.sol";
import "modulekit/Helpers.sol";
import "modulekit/core/ExtensibleFallbackHandler.sol";
import "modulekit/core/sessionKey/ISessionValidationModule.sol";
import {
    SessionData, SessionKeyManagerLib
} from "modulekit/core/sessionKey/SessionKeyManagerLib.sol";
import "modulekit/Mocks.sol";
import { Solarray } from "solarray/Solarray.sol";
import { ECDSA } from "solady/src/utils/ECDSA.sol";

import { IERC7579Execution } from "modulekit/Accounts.sol";
import { FlashloanCallback } from "src/coldstorage-subaccount/FlashloanCallback.sol";
import { FlashloanLender } from "src/coldstorage-subaccount/FlashloanLender.sol";
import { ColdStorageHook } from "src/coldstorage-subaccount/ColdStorageHook.sol";
import { OwnableValidator } from "src/ownable-validator/OwnableValidator.sol";

import { ERC7579BootstrapConfig } from "modulekit/external/ERC7579.sol";

import "src/coldstorage-subaccount/interfaces/Flashloan.sol";

contract ColdStorageTest is RhinestoneModuleKit, Test {
    using RhinestoneModuleKitLib for RhinestoneAccount;
    using ECDSA for bytes32;

    MockERC20 internal token;

    // main account and dependencies
    RhinestoneAccount internal mainAccount;
    FlashloanCallback internal flashloanCallback;

    // ColdStorage Account and dependencies
    RhinestoneAccount internal coldStorage;
    FlashloanLender internal flashloanLender;
    ColdStorageHook internal coldStorageHook;
    OwnableValidator internal ownableValidator;

    MockValidator internal mockValidator;

    uint256 ownerPk;
    address owner;

    function setUp() public {
        init();

        flashloanLender = new FlashloanLender(address(coldStorage.aux.fallbackHandler));
        vm.label(address(flashloanLender), "flashloanLender");
        flashloanCallback = new FlashloanCallback(address(mainAccount.aux.fallbackHandler));
        vm.label(address(flashloanCallback), "flashloanCallback");
        ownableValidator = new OwnableValidator();
        vm.label(address(ownableValidator), "ownableValidator");
        mockValidator = new MockValidator();
        vm.label(address(mockValidator), "mockValidator");

        coldStorageHook = new ColdStorageHook();
        vm.label(address(coldStorageHook), "coldStorageHook");

        _setupMainAccount();
        _setUpColdstorage();

        deal(address(coldStorage.account), 100 ether);
        deal(address(mainAccount.account), 100 ether);

        token = new MockERC20();
        token.initialize("Mock Token", "MTK", 18);
        deal(address(token), coldStorage.account, 100 ether);

        (owner, ownerPk) = makeAddrAndKey("owner");
        vm.warp(1_799_999);
    }

    function _setupMainAccount() public {
        ExtensibleFallbackHandler.Params memory params = ExtensibleFallbackHandler.Params({
            selector: IERC3156FlashBorrower.onFlashLoan.selector,
            fallbackType: ExtensibleFallbackHandler.FallBackType.Dynamic,
            handler: address(flashloanCallback)
        });

        ERC7579BootstrapConfig[] memory validators =
            makeBootstrapConfig(address(mockValidator), abi.encode(""));
        ERC7579BootstrapConfig[] memory executors =
            makeBootstrapConfig(address(flashloanCallback), abi.encode(""));
        ERC7579BootstrapConfig memory hook = _emptyConfig();
        ERC7579BootstrapConfig memory fallBack =
            _makeBootstrapConfig(address(auxiliary.fallbackHandler), abi.encode(params));
        mainAccount = makeRhinestoneAccount("mainAccount", validators, executors, hook, fallBack);
    }

    function _setUpColdstorage() public {
        ExtensibleFallbackHandler.Params[] memory params = new ExtensibleFallbackHandler.Params[](6);
        params[0] = ExtensibleFallbackHandler.Params({
            selector: IERC3156FlashLender.maxFlashLoan.selector,
            fallbackType: ExtensibleFallbackHandler.FallBackType.Static,
            handler: address(flashloanLender)
        });
        params[1] = ExtensibleFallbackHandler.Params({
            selector: IERC3156FlashLender.flashFee.selector,
            fallbackType: ExtensibleFallbackHandler.FallBackType.Static,
            handler: address(flashloanLender)
        });
        params[2] = ExtensibleFallbackHandler.Params({
            selector: IERC3156FlashLender.flashLoan.selector,
            fallbackType: ExtensibleFallbackHandler.FallBackType.Dynamic,
            handler: address(flashloanLender)
        });
        params[3] = ExtensibleFallbackHandler.Params({
            selector: IERC6682.flashFeeToken.selector,
            fallbackType: ExtensibleFallbackHandler.FallBackType.Static,
            handler: address(flashloanLender)
        });
        params[4] = ExtensibleFallbackHandler.Params({
            selector: IERC6682.flashFee.selector,
            fallbackType: ExtensibleFallbackHandler.FallBackType.Static,
            handler: address(flashloanLender)
        });
        params[5] = ExtensibleFallbackHandler.Params({
            selector: IERC6682.availableForFlashLoan.selector,
            fallbackType: ExtensibleFallbackHandler.FallBackType.Static,
            handler: address(flashloanLender)
        });

        ERC7579BootstrapConfig[] memory validators =
            makeBootstrapConfig(address(ownableValidator), abi.encode(address(mainAccount.account)));
        ERC7579BootstrapConfig[] memory executors =
            makeBootstrapConfig(address(flashloanLender), abi.encode(""));
        ERC7579BootstrapConfig memory hook = _makeBootstrapConfig(
            address(coldStorageHook), abi.encode(uint128(7 days), address(mainAccount.account))
        );
        ERC7579BootstrapConfig memory fallBack =
            _makeBootstrapConfig(address(auxiliary.fallbackHandler), abi.encode(params));

        coldStorage = makeRhinestoneAccount("coldStorage", validators, executors, hook, fallBack);
    }

    function simulateDeposit() internal {
        vm.prank(mainAccount.account);
        token.transfer(coldStorage.account, 1 ether);
    }

    function _requestWithdraw(
        IERC7579Execution.Execution memory exec,
        uint256 additionalDelay
    )
        internal
    {
        bytes memory execCallData = ERC7579Helpers.encode({
            target: address(coldStorageHook),
            value: 0,
            callData: abi.encodeCall(
                ColdStorageHook.requestTimelockedExecution, (exec, additionalDelay)
                )
        });

        UserOperation memory userOp = coldStorage.toUserOp(execCallData);
        bytes32 userOpHash = coldStorage.hashUserOp(userOp);

        bytes memory signature = abi.encodePacked(address(mockValidator), "");
        coldStorage.exec4337({
            target: address(coldStorageHook),
            value: 0,
            callData: abi.encodeCall(
                ColdStorageHook.requestTimelockedExecution, (exec, additionalDelay)
                ),
            signature: signature,
            validator: address(ownableValidator)
        });
    }

    function _execWithdraw(IERC7579Execution.Execution memory exec) internal {
        bytes memory callData = ERC7579Helpers.encode(exec.target, exec.value, exec.callData);
        UserOperation memory userOp = coldStorage.toUserOp(callData);
        bytes32 userOpHash = coldStorage.hashUserOp(userOp);
        bytes memory signature = abi.encodePacked(address(mockValidator), "");

        coldStorage.exec4337({
            userOp: userOp,
            signature: signature,
            validator: address(ownableValidator)
        });
    }

    function test_withdraw() public {
        IERC7579Execution.Execution memory action = IERC7579Execution.Execution({
            target: address(token),
            value: 0,
            callData: abi.encodeWithSelector(
                MockERC20.transfer.selector, address(mainAccount.account), 100
                )
        });

        _requestWithdraw(action, 0);

        vm.warp(block.timestamp + 8 days);
        _execWithdraw(action);
    }
}
