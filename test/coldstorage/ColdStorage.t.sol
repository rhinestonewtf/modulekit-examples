// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "modulekit/ModuleKit.sol";
import "modulekit/Modules.sol";
import "modulekit/core/sessionKey/ISessionValidationModule.sol";
import {
    SessionData, SessionKeyManagerLib
} from "modulekit/core/sessionKey/SessionKeyManagerLib.sol";
import "modulekit/Mocks.sol";
import { Solarray } from "solarray/Solarray.sol";
import { ECDSA } from "solady/src/utils/ECDSA.sol";

import { IERC7579Execution } from "modulekit/ModuleKitLib.sol";
import { FlashloanCallback } from "src/coldstorage-subaccount/FlashloanCallback.sol";
import { FlashloanLender } from "src/coldstorage-subaccount/FlashloanLender.sol";
import { ColdStorageHook } from "src/coldstorage-subaccount/ColdStorageHook.sol";
import { OwnableValidator } from "src/ownable-validator/OwnableValidator.sol";

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

    uint256 ownerPk;
    address owner;

    function setUp() public {
        mainAccount = makeRhinestoneAccount("mainAccount");
        coldStorage = makeRhinestoneAccount("coldStorage");
        deal(address(coldStorage.account), 100 ether);
        deal(address(mainAccount.account), 100 ether);

        token = new MockERC20();
        token.initialize("Mock Token", "MTK", 18);
        deal(address(token), coldStorage.account, 100 ether);

        (owner, ownerPk) = makeAddrAndKey("owner");

        flashloanLender = new FlashloanLender(address(coldStorage.aux.fallbackHandler));
        flashloanCallback = new FlashloanCallback(address(mainAccount.aux.fallbackHandler));
        ownableValidator = new OwnableValidator();

        coldStorageHook = new ColdStorageHook();

        _setupMainAccount();
        _setUpColdstorage();
        vm.warp(1_799_999);
    }

    function _setupMainAccount() public {
        // configure main account to be able to handle flashloan callback
        mainAccount.installFallback({
            handleFunctionSig: IERC3156FlashBorrower.onFlashLoan.selector,
            isStatic: false,
            handler: address(flashloanCallback)
        });
        mainAccount.installExecutor(address(flashloanCallback));
        mainAccount.installValidator(address(ownableValidator), abi.encode(owner));
    }

    function _setUpColdstorage() public {
        // configure coldStorage subaccount to handle ERC3156 flashloan requests
        coldStorage.installFallback({
            handleFunctionSig: IERC3156FlashLender.maxFlashLoan.selector,
            isStatic: true,
            handler: address(flashloanLender)
        });
        coldStorage.installFallback({
            handleFunctionSig: IERC3156FlashLender.flashFee.selector,
            isStatic: true,
            handler: address(flashloanLender)
        });
        coldStorage.installFallback({
            handleFunctionSig: IERC3156FlashLender.flashLoan.selector,
            isStatic: false,
            handler: address(flashloanLender)
        });
        // configure coldStorage subaccount to handle ERC6682 flashloan requests
        coldStorage.installFallback({
            handleFunctionSig: IERC6682.flashFeeToken.selector,
            isStatic: true,
            handler: address(flashloanLender)
        });
        coldStorage.installFallback({
            handleFunctionSig: IERC6682.flashFee.selector,
            isStatic: true,
            handler: address(flashloanLender)
        });
        coldStorage.installFallback({
            handleFunctionSig: IERC6682.availableForFlashLoan.selector,
            isStatic: true,
            handler: address(flashloanLender)
        });

        coldStorage.installExecutor(address(flashloanLender));

        coldStorage.installValidator(
            address(ownableValidator), abi.encode(address(mainAccount.account))
        );

        // install hook
        coldStorage.installHook(
            address(coldStorageHook), abi.encode(uint128(7 days), address(mainAccount.account))
        );
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
        bytes memory execCallData = ERC7579Helpers.encodeExecution(
            address(coldStorageHook),
            0,
            abi.encodeCall(ColdStorageHook.requestTimelockedExecution, (exec, additionalDelay))
        );

        UserOperation memory userOp = ERC7579Helpers.toUserOp(execCallData, coldStorage.account);
        bytes32 userOpHash = coldStorage.hashUserOp(userOp);

        bytes memory signature = abi.encodePacked(address(mainAccount.defaultValidator), "");

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
        bytes memory callData =
            ERC7579Helpers.encodeExecution(exec.target, exec.value, exec.callData);
        UserOperation memory userOp = ERC7579Helpers.toUserOp(callData, coldStorage.account);
        bytes32 userOpHash = coldStorage.hashUserOp(userOp);
        bytes memory signature = abi.encodePacked(address(mainAccount.defaultValidator), "");

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
