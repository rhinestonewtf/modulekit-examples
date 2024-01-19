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
import { ColdStorageExecutor } from "src/coldstorage-subaccount/ColdStorageExecutor.sol";
import { OwnableValidator } from "src/ownable-validator/OwnableValidator.sol";

import { ERC7579BootstrapConfig } from "modulekit/external/ERC7579.sol";

import "src/coldstorage-subaccount/interfaces/Flashloan.sol";

contract ColdStorageTest is RhinestoneModuleKit, Test {
    using ModuleKitHelpers for *;
    using ModuleKitUserOp for *;
    using ECDSA for bytes32;

    MockERC20 internal token;

    // main account and dependencies
    RhinestoneAccount internal mainAccount;
    FlashloanCallback internal flashloanCallback;

    // ColdStorage Account and dependencies
    RhinestoneAccount internal coldStorage;
    FlashloanLender internal flashloanLender;
    ColdStorageHook internal coldStorageHook;
    ColdStorageExecutor internal coldStorageExecutor;
    OwnableValidator internal ownableValidator;

    MockValidator internal mockValidator;

    Account owner;

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

        coldStorageExecutor = new ColdStorageExecutor();
        vm.label(address(coldStorageExecutor), "coldStorageExecutor");

        owner = makeAccount("owner");
        _setupMainAccount();
        _setUpColdstorage();

        deal(address(coldStorage.account), 100 ether);
        deal(address(mainAccount.account), 100 ether);

        token = new MockERC20();
        token.initialize("Mock Token", "MTK", 18);
        deal(address(token), mainAccount.account, 100 ether);

        console2.log("owner", owner.addr);
        vm.warp(1_799_999);

        mainAccount.exec({
            target: address(token),
            value: 0,
            callData: abi.encodeCall(IERC20.transfer, (address(coldStorage.account), 1 ether))
        });
    }

    function _setupMainAccount() public {
        ExtensibleFallbackHandler.Params[] memory params = new ExtensibleFallbackHandler.Params[](1);
        params[0] = ExtensibleFallbackHandler.Params({
            selector: IERC3156FlashBorrower.onFlashLoan.selector,
            fallbackType: ExtensibleFallbackHandler.FallBackType.Dynamic,
            handler: address(flashloanCallback)
        });

        ERC7579BootstrapConfig[] memory validators =
            makeBootstrapConfig(address(ownableValidator), abi.encode(owner.addr));
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

        address[] memory addresses = new address[](2);
        bytes[] memory callData = new bytes[](2);

        addresses[0] = address(flashloanLender);
        addresses[1] = address(coldStorageExecutor);

        callData[0] = abi.encode("");
        callData[1] = abi.encode(address(mainAccount.account));

        ERC7579BootstrapConfig[] memory executors = makeBootstrapConfig(addresses, callData);

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
        UserOpData memory userOpData = mainAccount.getExecOps({
            target: address(coldStorage.account),
            value: 0,
            callData: abi.encodeCall(
                ColdStorageHook.requestTimelockedExecution, (exec, additionalDelay)
                ),
            txValidator: address(ownableValidator)
        });

        bytes memory signature = signHash(owner.key, userOpData.userOpHash);
        address recover =
            ECDSA.recover(ECDSA.toEthSignedMessageHash(userOpData.userOpHash), signature);
        assertEq(recover, owner.addr);
        userOpData.userOp.signature = signature;
        userOpData.execUserOps();
    }

    function signHash(uint256 privKey, bytes32 digest) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, ECDSA.toEthSignedMessageHash(digest));
        return abi.encodePacked(r, s, v);
    }

    function _execWithdraw(IERC7579Execution.Execution memory exec) internal {
        UserOpData memory userOpData = mainAccount.getExecOps(
            exec.target, exec.value, exec.callData, address(ownableValidator)
        );
        bytes memory signature = signHash(owner.key, userOpData.userOpHash);
        userOpData.userOp.signature = signature;
        userOpData.execUserOps();
    }

    function test_withdraw() public {
        uint256 prevBalance = token.balanceOf(address(mainAccount.account));
        uint256 amountToWithdraw = 100;

        IERC7579Execution.Execution memory action = IERC7579Execution.Execution({
            target: address(token),
            value: 0,
            callData: abi.encodeWithSelector(
                MockERC20.transfer.selector, address(mainAccount.account), amountToWithdraw
                )
        });

        _requestWithdraw(action, 0);

        vm.warp(block.timestamp + 8 days);
        _execWithdraw(action);

        uint256 newBalance = token.balanceOf(address(mainAccount.account));
        assertEq(newBalance, prevBalance + amountToWithdraw);
    }

    function test_setWaitPeriod() public {
        uint256 newWaitPeriod = 2 days;

        IERC7579Execution.Execution memory action = IERC7579Execution.Execution({
            target: address(coldStorage.account),
            value: 0,
            callData: abi.encodeWithSelector(ColdStorageHook.setWaitPeriod.selector, (newWaitPeriod))
        });

        _requestWithdraw(action, 0);

        vm.warp(block.timestamp + 8 days);
        _execWithdraw(action);

        IERC7579Execution.Execution memory newAction = IERC7579Execution.Execution({
            target: address(token),
            value: 0,
            callData: abi.encodeWithSelector(
                MockERC20.transfer.selector, address(mainAccount.account), 100
                )
        });

        _requestWithdraw(newAction, 0);

        vm.warp(block.timestamp + newWaitPeriod);
        _execWithdraw(newAction);

        (uint128 updatedWaitPeriod,) = coldStorageHook.vaultConfig(address(coldStorage.account));
        assertEq(updatedWaitPeriod, uint128(newWaitPeriod));
    }
}
