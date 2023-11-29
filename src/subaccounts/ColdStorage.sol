// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ownable } from "solady/src/auth/Ownable.sol";
import { WETH } from "solady/src/tokens/WETH.sol";

import "forge-std/interfaces/IERC721.sol";

contract ColdStorage is Ownable, IERC721TokenReceiver {
    struct InitParams {
        uint128 minSlotTime;
        uint128 maxSlotTime;
        uint128 minTimeTillValid;
    }

    struct WithdrawSlot {
        uint128 validAfter;
        uint128 validBefore;
    }

    uint256 public MIN_SLOT_TIME;
    uint256 public MAX_SLOT_TIME;
    uint256 public MIN_TIME_TILL_VALID;

    WETH immutable weth;

    bytes32 public constant TYPEHASH_ERC20 = keccak256("ERC20(address token,uint256 amount)");
    bytes32 public constant TYPEHASH_ERC721 = keccak256("ERC721(address token,uint256 tokenId)");

    event WithdrawERC20(IERC20 token, uint256 amount);

    error InvalidTime();
    error InvalidWithdrawProof();

    mapping(bytes32 queueRoot => WithdrawSlot) public _withdraw;

    constructor(WETH _weth) {
        weth = _weth;
    }

    modifier timeLock(bytes32 queueRoot) {
        WithdrawSlot memory slot = _withdraw[queueRoot];
        if (!_checkTimeLock(slot)) revert InvalidTime();
        _;
    }

    function init(InitParams calldata initParams) external {
        _initializeOwner(msg.sender);
        if (initParams.minSlotTime > initParams.maxSlotTime) {
            revert("minDelay > maxDelay");
        }

        MIN_SLOT_TIME = initParams.minSlotTime;
        MAX_SLOT_TIME = initParams.maxSlotTime;
        MIN_TIME_TILL_VALID = initParams.minTimeTillValid;
    }

    function _checkTimeLock(WithdrawSlot memory slot) internal view returns (bool valid) {
        if (slot.validBefore == 0) return false;
        if (slot.validAfter == 0) return false;
        if (slot.validBefore < slot.validAfter) return false;
        if (slot.validBefore - slot.validAfter < MIN_SLOT_TIME) return false;
        if (slot.validBefore - slot.validAfter > MAX_SLOT_TIME) return false;
        if (slot.validAfter - MIN_TIME_TILL_VALID > block.timestamp) {
            return false;
        }
        return true;
    }

    function queueWithdrawal(bytes32 queueRoot, WithdrawSlot calldata config) public onlyOwner {
        if (!_checkTimeLock(config)) revert InvalidTime();
        _withdraw[queueRoot] = config;
    }

    function removeWithdrawal(bytes32 queueRoot) public onlyOwner {
        delete _withdraw[queueRoot];
    }

    function withdrawERC20(
        bytes32 queueRoot,
        IERC20 token,
        uint256 value,
        bytes32[] calldata _proof
    )
        public
        timeLock(queueRoot)
    {
        // check if the queueRoot is valid
        bytes32 leaf = getQueueLeaf(TYPEHASH_ERC20, address(token), value);
        if (!MerkleProof.verify(_proof, queueRoot, leaf)) {
            revert InvalidWithdrawProof();
        }

        // transfer ERC20 to owner
        SafeERC20.safeTransfer(token, owner(), value);

        emit WithdrawERC20(token, value);
    }

    function getQueueLeaf(
        bytes32 typeHash,
        address token,
        uint256 value
    )
        public
        pure
        returns (bytes32 leaf)
    {
        if (typeHash == TYPEHASH_ERC20 || typeHash == TYPEHASH_ERC721) {
            leaf = keccak256(abi.encode(typeHash, token, value));
        } else {
            revert();
        }
    }

    // in case ETH was send to the counter factual address
    function wrapETH() public {
        weth.deposit{ value: address(this).balance }();
    }

    receive() external payable { }

    // functions to receive ERC721 and ERC1155
    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    )
        external
        override
        returns (bytes4)
    {
        return IERC721TokenReceiver.onERC721Received.selector;
    }
}
