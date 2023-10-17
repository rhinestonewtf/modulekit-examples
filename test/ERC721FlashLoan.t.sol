// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {
    RhinestoneModuleKit,
    RhinestoneModuleKitLib,
    RhinestoneAccount
} from "modulekit/test/utils/safe-base/RhinestoneModuleKit.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC721} from "solmate/test/utils/mocks/MockERC721.sol";

import "../src/NFTFlashLoan/ERC721FlashLoan.sol";
import "../src/NFTFlashLoan/interfaces/IERC3156FlashLender.sol";
import "../src/NFTFlashLoan/interfaces/IERC3156FlashBorrower.sol";

import "forge-std/console2.sol";

contract TokenBorrower is IERC3156FlashBorrower {
    function onFlashLoan(address lender, address token, uint256 tokenId, uint256 fee, bytes calldata data)
        external
        override
        returns (bytes32)
    {
        console2.log("FlashloanBorrower has the token");
        address feeToken = IERC6682(lender).flashFeeToken();
        IERC20(feeToken).approve(lender, fee);
        IERC721(token).transferFrom(address(this), lender, tokenId);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function initLending(address lender, address manager, address token, uint256 tokenId) external {
        IERC3156FlashLender(lender).flashLoan(
            IERC3156FlashBorrower(address(this)), token, tokenId, abi.encode(manager, bytes(""))
        );
    }
}

contract TokenGated {
    uint256 foo;

    IERC721 nft;

    event TokenGatedOperation();

    constructor(address _nft) {
        nft = IERC721(_nft);
    }

    modifier onlyNFTOwner(uint256 tokenId) {
        require(nft.ownerOf(tokenId) == msg.sender, "Only NFT owner can call this function");
        _;
    }

    function setFoo(uint256 tokenId, uint256 _foo) public onlyNFTOwner(tokenId) {
        foo = _foo;
        emit TokenGatedOperation();
    }
}

contract ERC721FlashLoanTest is Test, RhinestoneModuleKit {
    using RhinestoneModuleKitLib for RhinestoneAccount; // <-- library that wraps smart account actions for easier testing

    RhinestoneAccount instanceLender; // <-- this is a rhinestone smart account instance
    RhinestoneAccount instanceBorrower; // <-- this is a rhinestone smart account instance
    address receiver;
    MockERC20 token;
    MockERC721 nft;

    FlashloanLenderModule flashloan;
    TokenGated tokenGated;

    address devFeeReceiver;

    uint256 TOKENID;

    function setUp() public {
        // setting up receiver address. This is the EOA that this test is sending funds to
        receiver = makeAddr("receiver");
        devFeeReceiver = makeAddr("devFeeReceiver");

        // setting up mock executor and token
        token = new MockERC20("", "", 18);

        nft = new MockERC721("", "");

        tokenGated = new TokenGated(address(nft));

        flashloan = new FlashloanLenderModule(devFeeReceiver, 100);

        // create a new rhinestone account instance
        instanceLender = makeRhinestoneAccount("lender");
        vm.label(instanceLender.account, "lender");
        instanceBorrower = makeRhinestoneAccount("borrower");
        vm.label(instanceBorrower.account, "borrower");

        // dealing ether and tokens to newly created smart account
        vm.deal(instanceLender.account, 10 ether);
        vm.deal(instanceBorrower.account, 10 ether);
        TOKENID = 1;
        nft.mint(instanceLender.account, TOKENID);

        token.mint(instanceBorrower.account, 10_000_000 ether);
    }

    function testFlashloan() public {
        // setup LENDER
        instanceLender.addFallback({
            handleFunctionSig: IERC6682.availableForFlashLoan.selector,
            isStatic: true,
            handler: address(flashloan)
        });
        instanceLender.addFallback({
            handleFunctionSig: IERC6682.flashFeeToken.selector,
            isStatic: true,
            handler: address(flashloan)
        });
        instanceLender.addFallback({
            handleFunctionSig: IERC6682.flashFee.selector,
            isStatic: true,
            handler: address(flashloan)
        });

        instanceLender.addFallback({
            handleFunctionSig: IERC3156FlashLender.flashLoan.selector,
            isStatic: false,
            handler: address(flashloan)
        });
        instanceLender.addExecutor(address(flashloan));
        instanceBorrower.addExecutor(address(flashloan));
        vm.startPrank(instanceLender.account);
        flashloan.setFeeToken(address(token));
        flashloan.setFee(address(nft), TOKENID, 10 ** 18);
        vm.stopPrank();

        uint256 fee = IERC6682(instanceLender.account).flashFee(address(nft), TOKENID);
        // console2.log("foo", instanceLender.account, fee);
        // assertTrue(fee > 0, "Fee should be greater than 0");

        //---------------

        // setup borrower
        instanceBorrower.addFallback({
            handleFunctionSig: IERC3156FlashBorrower.onFlashLoan.selector,
            isStatic: false,
            handler: address(flashloan)
        });

        // trigger borrowing

        ExecutorAction[] memory actions = new ExecutorAction[](3);
        actions[0] = ERC20ModuleKit.approveAction({
            token: IERC20(address(token)),
            to: instanceLender.account,
            amount: 10_000 ether
        });
        actions[1] = ExecutorAction({
            to: payable(address(tokenGated)),
            value: 0,
            data: abi.encodeCall(TokenGated.setFoo, (TOKENID, 1337))
        });

        actions[2] = ERC721ModuleKit.transferFromAction({
            token: IERC721(address(nft)),
            from: instanceBorrower.account,
            to: instanceLender.account,
            tokenId: TOKENID
        });

        CallbackParams memory callbackParams = CallbackParams({
            managerForBorrower: IExecutorManager(address(instanceBorrower.aux.executorManager)),
            actions: actions
        });

        bytes memory callData = abi.encodeCall(
            IERC3156FlashLender.flashLoan,
            (
                IERC3156FlashBorrower(address(instanceBorrower.account)),
                address(nft),
                TOKENID,
                abi.encode(instanceLender.aux.executorManager, abi.encode(callbackParams))
            )
        );
        instanceBorrower.exec4337({target: instanceLender.account, callData: callData});

        // assertTrue(token.balanceOf(devFeeReceiver) > 0, "Dev fee should be greater than 0");
    }
}
