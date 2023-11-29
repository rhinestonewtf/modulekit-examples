// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import "src/subaccounts/ColdStorage.sol";
import "modulekit/Mocks.sol";
import "murky/Merkle.sol";
import "forge-std/console2.sol";
import { WETH } from "solady/src/tokens/WETH.sol";

contract ColdStorageTest is Test {
    ColdStorage coldStorage;

    MockERC20 usdc;
    WETH weth;

    Merkle m;

    function setUp() public {
        m = new Merkle();
        usdc = new MockERC20("USDC", "USDC", 18);
        weth = new WETH();
        coldStorage = new ColdStorage(weth);
        _init();
        usdc.mint(address(this), 1000 ether);
        deal(address(this), 10 ether);
    }

    function _init() internal {
        ColdStorage.InitParams memory initParams = ColdStorage.InitParams({
            minSlotTime: 1 days,
            maxSlotTime: 7 days,
            minTimeTillValid: 1 days
        });
        coldStorage.init(initParams);
    }

    function test_WhenAccountCloneIsInitialized() external {
        // it should set owner
        assertTrue(coldStorage.owner() == address(this));
        // it should set min timeslot
        assertTrue(coldStorage.MIN_SLOT_TIME() == 1 days);
        // it should set max timeslot
        assertTrue(coldStorage.MAX_SLOT_TIME() == 7 days);
        // it should set min delay
        assertTrue(coldStorage.MIN_TIME_TILL_VALID() == 1 days);
    }

    function _setQueue(bytes32 queueRoot, uint256 validBefore, uint256 validAfter) internal {
        ColdStorage.WithdrawSlot memory slot = ColdStorage.WithdrawSlot({
            validAfter: uint128(validAfter),
            validBefore: uint128(validBefore)
        });
        coldStorage.queueWithdrawal(queueRoot, slot);
    }

    function test_RevertWhen_TimeslotIsTooSmall(uint128 validBefore, uint128 validAfter) external {
        // it should revert
        vm.assume(validBefore > validAfter);
        vm.assume(validBefore - validAfter > 1 days);
        vm.assume(validBefore - validAfter < 7 days);
        vm.expectRevert(ColdStorage.InvalidTime.selector);
        _setQueue(bytes32("1"), validBefore, validAfter);
    }

    function test_RevertWhen_QueueRootIsZero() external {
        // it should revert
        vm.expectRevert();
        _setQueue(bytes32(0), block.timestamp, block.timestamp + 2 days);
    }

    function test_RevertWhen_TimeslotIsTooLarge() external {
        // it should revert
    }

    function test_RevertWhen_TokenIsNotApproved() external whenWithdrawIsCalled {
        // it should revert
    }

    function test_WhenTokenIsWithdrawnTwice() external whenWithdrawIsCalled {
        // it should withdraw tokens
    }

    function test_WhenTokenIsApproved() external whenWithdrawIsCalled {
        usdc.transfer(address(coldStorage), 100 ether);
        assertTrue(usdc.balanceOf(address(coldStorage)) == 100 ether);

        vm.roll(18_674_939);

        // make a timeslot to withdraw

        // create merkel root for specific token
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = "asdf";
        leaves[1] = coldStorage.getQueueLeaf(coldStorage.TYPEHASH_ERC20(), address(usdc), 50 ether);

        bytes32 root = m.getRoot(leaves);
        bytes32[] memory proof = m.getProof(leaves, 1);

        assertTrue(m.verifyProof(root, proof, leaves[1]));

        uint128 validAfter = uint128(block.timestamp + coldStorage.MIN_TIME_TILL_VALID());
        coldStorage.queueWithdrawal(
            root,
            ColdStorage.WithdrawSlot({
                validAfter: validAfter,
                validBefore: uint128(block.timestamp + 2 days)
            })
        );

        vm.warp(validAfter);

        // it should transfer tokens
        coldStorage.withdrawERC20(root, IERC20(address(usdc)), 50 ether, proof);
        // it should emit Withdrawal event
        // it should update balance
        assertTrue(usdc.balanceOf(address(coldStorage)) == 50 ether);
    }

    function test_WhenETHIsSentToColdStorage() external {
        // it should wrap ETH to WETH
        payable(address(coldStorage)).transfer(1 ether);
        coldStorage.wrapETH();
        // it should convert to WETH
        assertTrue(weth.balanceOf(address(coldStorage)) == 1 ether);
        assertTrue(address(coldStorage).balance == 0);
    }

    modifier whenWithdrawIsCalled() {
        _;
    }
}
