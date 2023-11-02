// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "modulekit/modulekit/interfaces/IHook.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "modulekit/core/ComposableCondition.sol";
import "modulekit/modulekit/interfaces/IExecutor.sol";
import "modulekit/modulekit/ValidatorBase.sol";
import "modulekit/modulekit/integrations/uniswap/v3/UniswapSwaps.sol";
import "modulekit/modulekit/ConditionalExecutorBase.sol";

import "forge-std/interfaces/IERC20.sol";
import { SentinelListLib } from "sentinellist/src/SentinelList.sol";

import "forge-std/console2.sol";

contract TokenDumper is ConditionalExecutor {
    using ModuleExecLib for IExecutorManager;
    using UniswapSwaps for address;
    using SentinelListLib for SentinelListLib.SentinelList;

    struct TokenDumperConfig {
        IERC20 baseToken;
        uint16 feePercentage;
    }

    mapping(address => bytes32 root) private dumpList;
    mapping(address => TokenDumperConfig) private tokenDumperConfig;

    error InvalidToken();
    error InvalidAccount();

    event TokenDump(address indexed account, address indexed token, uint256 amount);
    event NewHodlToken(address indexed account, bytes32 root);
    event NewTokenDumperConfig(
        address indexed account, address indexed baseToken, uint16 feePercentage
    );

    constructor(ComposableConditionManager _conditionManager)
        ConditionalExecutor(_conditionManager)
    { }

    modifier onlyDumpTokens(address account, IERC20 token, bytes32[] calldata merkleProof) {
        _onlyDumpTokens(account, token, merkleProof);
        _;
    }

    function _onlyDumpTokens(
        address account,
        IERC20 token,
        bytes32[] calldata merkleProof
    )
        private
        view
    {
        if (address(token) == address(0)) revert InvalidToken();
        bytes32 merkleRoot = dumpList[account];
        if (!MerkleProof.verify(merkleProof, merkleRoot, _tokenToMerkleLeaf(token))) {
            revert("SessionNotApproved");
        }
    }

    function _tokenToMerkleLeaf(IERC20 token) public pure returns (bytes32 leaf) {
        leaf = keccak256(abi.encodePacked(token));
    }

    function addDumpToken(bytes32 root) public {
        dumpList[msg.sender] = root;
        emit NewHodlToken(msg.sender, root);
    }

    function setTokenDumperConfig(IERC20 baseToken, uint16 feePercentage) external {
        tokenDumperConfig[msg.sender] =
            TokenDumperConfig({ baseToken: baseToken, feePercentage: feePercentage });

        emit NewTokenDumperConfig(msg.sender, address(baseToken), feePercentage);
    }

    function _swap(
        address account,
        IExecutorManager manager,
        IERC20 dumpToken,
        IERC20 outToken
    )
        private
    {
        uint256 balance = dumpToken.balanceOf(account);
        ExecutorAction[] memory swapActions = new ExecutorAction[](2);
        swapActions[0] = ERC20ModuleKit.approveAction({
            token: dumpToken,
            to: SWAPROUTER_ADDRESS,
            amount: balance
        });
        swapActions[1] = UniswapSwaps.swapExactInputSingle({
            smartAccount: account, // beneficiary of the swap
            tokenIn: dumpToken, // token to be sold
            tokenOut: outToken, // token to be bought
            amountIn: balance
        });
        manager.exec(account, swapActions);
    }

    function dump(
        address account,
        IExecutorManager manager,
        IERC20 dumpToken,
        bytes32[] calldata proof,
        ConditionConfig[] calldata conditions
    )
        external
        onlyDumpTokens(account, dumpToken, proof)
        onlyIfConditionsMet(account, conditions)
    {
        console2.log("dump");
        TokenDumperConfig memory config = tokenDumperConfig[account];
        if (address(config.baseToken) == address(0)) revert InvalidAccount();

        uint256 amountBefore = config.baseToken.balanceOf(account);
        _swap(account, manager, dumpToken, config.baseToken);
        console2.log("swap done");
        uint256 amountAfter = config.baseToken.balanceOf(account) - amountBefore;

        uint256 fee = (amountAfter * config.feePercentage) / 10_000;

        if (fee > 0) {
            manager.exec(
                account,
                ERC20ModuleKit.transferAction({
                    token: config.baseToken,
                    to: msg.sender,
                    amount: fee
                })
            );
        }

        emit TokenDump(account, address(dumpToken), amountAfter - fee);
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
