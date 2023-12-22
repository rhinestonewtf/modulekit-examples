// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { ECDSA } from "solady/src/utils/ECDSA.sol";
import {
    RhinestoneModuleKit,
    RhinestoneModuleKitLib,
    RhinestoneAccount
} from "modulekit/test/utils/erc7579-base/RhinestoneModuleKit.sol";

import { FallbackHandler } from "src/ColdStorage_7579/FallbackHandler.sol";
import { FlashloanLender } from "src/ColdStorage_7579/FlashloanLender.sol";
import { FlashLoanType } from "src/ColdStorage_7579/Common.sol";
import { FlashloanCallback } from "src/ColdStorage_7579/FlashloanCallback.sol";
import { OwnableValidator } from "src/ColdStorage_7579/OwnableValidator.sol";
import { VaultHook } from "src/ColdStorage_7579/VaultHook.sol";

import "erc7579/interfaces/IMSA.sol";
import {
    IERC3156FlashLender,
    IERC3156FlashBorrower
} from "src/executors/NFTFlashloan/interfaces/IERC3156FlashLender.sol";

import { MockERC721 } from "solady/test/utils/mocks/MockERC721.sol";

contract MockTarget {
    uint256 public value;

    function setValue(uint256 _value) public {
        value = _value;
    }
}

contract VCSTest is Test, RhinestoneModuleKit {
    using RhinestoneModuleKitLib for RhinestoneAccount;

    RhinestoneAccount owner;
    RhinestoneAccount vaultAccount;

    // components needed for VCS
    FallbackHandler fallbackHandler;
    FlashloanLender flashloanLender;
    FlashloanCallback flashloanCallback;
    OwnableValidator ownableValidator;
    VaultHook vaultHook;

    MockTarget target;

    MockERC721 nft;

    function setUp() public {
        vm.warp(1_800_000_000);
        fallbackHandler = new FallbackHandler();
        flashloanLender = new FlashloanLender(address(fallbackHandler));
        vm.label(address(flashloanLender), "flashloan lender");
        flashloanCallback = new FlashloanCallback(address(fallbackHandler));
        vm.label(address(flashloanCallback), "flashloan callback");
        ownableValidator = new OwnableValidator();
        vaultHook = new VaultHook();

        owner = initAccount_owner();
        vaultAccount = initAccount_coldStorage(owner.account);

        target = new MockTarget();

        // send NFT to vault

        nft = new MockERC721();
        nft.mint(vaultAccount.account, 1337);
    }

    function installExtensibleFallbackHandler(
        RhinestoneAccount memory instance,
        address _fallbackHandler,
        bytes memory initData
    )
        public
    {
        instance.exec4337(
            instance.account,
            abi.encodeCall(IAccountConfig.installFallback, (_fallbackHandler, initData))
        );
    }

    function initAccount_owner() public returns (RhinestoneAccount memory ownerAccount) {
        ownerAccount = makeRhinestoneAccount("owner");
        vm.label(ownerAccount.account, "owner");
        vm.deal(ownerAccount.account, 1 ether);
        installExtensibleFallbackHandler(ownerAccount, address(fallbackHandler), "");
        ownerAccount.addExecutor(address(flashloanCallback));
        ownerAccount.exec4337(
            ownerAccount.account, // has to be a SELF call for auth to work
            abi.encodeCall(
                FallbackHandler.setFunctionSig,
                (
                    IERC3156FlashBorrower.onFlashLoan.selector,
                    FallbackHandler.FallBackType.Dynamic,
                    address(flashloanCallback)
                )
            )
        );
        ownerAccount.addValidator({
            validator: address(ownableValidator),
            initData: abi.encode(address(this))
        });
    }

    function initAccount_coldStorage(address vaultOwner)
        public
        returns (RhinestoneAccount memory account)
    {
        account = makeRhinestoneAccount("vault");
        vm.label(account.account, "vault");
        vm.deal(account.account, 1 ether);
        installExtensibleFallbackHandler(account, address(fallbackHandler), "");
        account.exec4337(
            account.account, // has to be a SELF call for auth to work
            abi.encodeCall(
                FallbackHandler.setFunctionSig,
                (
                    IERC3156FlashLender.flashLoan.selector,
                    FallbackHandler.FallBackType.Dynamic,
                    address(flashloanLender)
                )
            )
        );
        account.addExecutor(address(flashloanLender));

        uint128 vaultWaitPeriod = 14 days;
        account.addValidator({
            validator: address(ownableValidator),
            initData: abi.encode(vaultOwner)
        });
        account.addHook({
            hook: address(vaultHook),
            initData: abi.encode(vaultWaitPeriod, vaultOwner)
        });
    }

    function test_tryWithdraw__withinBlockedTime_ShouldFail() public {
        // TODO
        vaultAccount.expect4337Revert();
        vaultAccount.exec4337(
            address(nft),
            abi.encodeCall(MockERC721.transferFrom, (vaultAccount.account, owner.account, 1337))
        );

        assertFalse(nft.ownerOf(1337) == owner.account);
    }

    function test_tryWithdraw__afterBlockedTime_ShouldSucceed() public {
        IExecution.Execution memory execution = IExecution.Execution({
            target: address(nft),
            value: 0,
            callData: abi.encodeCall(
                MockERC721.transferFrom, (vaultAccount.account, owner.account, 1337)
                )
        });
        vaultAccount.exec4337(
            address(vaultHook), abi.encodeCall(VaultHook.requestTimelockedExecution, (execution, 0))
        );
        vm.roll(15 days);
        // TODO
        vaultAccount.exec4337(execution.target, execution.callData);

        assertEq(nft.ownerOf(1337), owner.account);
    }

    function test_flashloan() public {
        vm.prank(owner.account);
        // initiate flashloan
        bytes memory data; // FlashLoanType | signature | callData

        // TODO sign batched transaction.

        IExecution.Execution[] memory executions = new IExecution.Execution[](2);
        // Token gated action
        executions[0] = IExecution.Execution({
            target: address(target),
            value: 0,
            callData: abi.encodeCall(MockTarget.setValue, (0x4141))
        });
        executions[1] = IExecution.Execution({
            target: address(nft),
            value: 0,
            callData: abi.encodeCall(
                MockERC721.transferFrom, (owner.account, vaultAccount.account, 1337)
                )
        });
        bytes memory tokenGatedCall =
            abi.encodeCall(IExecution.executeBatchFromExecutor, (executions));
        data = abi.encode(FlashLoanType.ERC721, hex"41414141", tokenGatedCall);
        IERC3156FlashLender(vaultAccount.account).flashLoan(
            IERC3156FlashBorrower(owner.account), address(nft), 1337, data
        );
    }
}
