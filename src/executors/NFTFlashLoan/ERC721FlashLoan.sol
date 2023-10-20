// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IERC721 } from "forge-std/interfaces/IERC721.sol";

import { IFallbackMethod } from "modulekit/common/FallbackHandler.sol";
import { ERC721ModuleKit } from "modulekit/modulekit/integrations/ERC721Actions.sol";
import { ERC20ModuleKit } from "modulekit/modulekit/integrations/ERC20Actions.sol";

import { ExecutorBase } from "modulekit/modulekit/ExecutorBase.sol";
import { IExecutorManager, ExecutorAction, ModuleExecLib } from "modulekit/modulekit/IExecutor.sol";

import { IERC3156FlashBorrower } from "./interfaces/IERC3156FlashBorrower.sol";
import { IERC3156FlashLender } from "./interfaces/IERC3156FlashLender.sol";

interface IERC6682 {
    function flashFeeToken() external view returns (address);
    function flashFee(address token, uint256 tokenId) external view returns (uint256);
    function availableForFlashLoan(address token, uint256 tokenId) external view returns (bool);
}

struct CallbackParams {
    IExecutorManager managerForBorrower;
    ExecutorAction[] actions;
}
/**
 * @title FlashloanLenderModule
 * @dev This contract provides flash loan capabilities by lending NFTs and collecting fees in ERC20 tokens.
 * It extends the ExecutorBase and implements the IFallbackMethod.
 * this contract works with the ExtensibleFallbackManager
 */

contract FlashloanLenderModule is ExecutorBase, IFallbackMethod {
    using ModuleExecLib for IExecutorManager;

    // Custom errors to represent various flash loan failures
    error FlashLoan_TokenNotTransferedBack();
    error FlashLoan_CallbackFailed();
    error FlashLoan_TokenNotAvailable();

    event FeeToken(address indexed account, address indexed token);
    event Fee(address indexed account, address indexed token, uint256 indexed tokenId, uint256 fee);
    event FlashLoan(
        address indexed account, address indexed token, uint256 indexed tokenId, uint256 fee
    );

    mapping(address account => mapping(address token => mapping(uint256 tokenId => uint256 fee)))
        public _feePerToken;

    mapping(address account => address flashFeeToken) public _flashFeeTokenPerAccount;

    address immutable FEE_RECIPIENT;
    uint256 immutable FEE_PERCENTAGE;

    constructor(address feeRecipient, uint256 feePercentage) {
        FEE_RECIPIENT = feeRecipient;
        FEE_PERCENTAGE = feePercentage;
    }

    function calcDevFee(uint256 borrowerFee, uint256 bps) public pure returns (uint256) {
        require((borrowerFee * bps) >= 10_000, "Fee too low");
        return borrowerFee * bps / 10_000;
    }

    /**
     * @notice Sets the token to be used for collecting flash loan fees.
     * @param feeToken The address of the ERC20 token to be used for fees.
     */
    function setFeeToken(address feeToken) external {
        _flashFeeTokenPerAccount[msg.sender] = feeToken;
        emit FeeToken(msg.sender, feeToken);
    }

    /**
     * @notice Sets the fee for a specific NFT.
     * @param token Address of the ERC721 token contract.
     * @param tokenId ID of the NFT.
     * @param fee The fee amount in the specified feeToken.
     */
    function setFee(address token, uint256 tokenId, uint256 fee) external {
        _feePerToken[msg.sender][token][tokenId] = fee;
        emit Fee(msg.sender, token, tokenId, fee);
    }

    /**
     * @notice Checks if a specific NFT is available for flash loan.
     * @param account The address of the potential lender.
     * @param token Address of the ERC721 token contract.
     * @param tokenId ID of the NFT.
     * @return hasToken if the NFT is available for flash loan, false otherwise.
     */
    function _availableForFlashLoan(
        address account,
        address token,
        uint256 tokenId
    )
        internal
        view
        returns (bool hasToken)
    {
        try IERC721(token).ownerOf(tokenId) returns (address holder) {
            hasToken = holder == address(account);
        } catch {
            hasToken = false;
        }
    }

    /**
     * @notice Retrieves the token used for collecting flash loan fees for a specific account.
     * @param account The address of the lender.
     * @return Address of the ERC20 token used for fees.
     */
    function _flashFeeToken(address account) internal view returns (address) {
        return _flashFeeTokenPerAccount[account];
    }

    /**
     * @notice Retrieves the borrower fee for a specific NFT.
     * @param account The address of the lender.
     * @param token Address of the ERC721 token contract.
     * @param tokenId ID of the NFT.
     * @return fee amount for the specified NFT.
     */
    function _tokenOwnerFee(
        address account,
        address token,
        uint256 tokenId
    )
        internal
        view
        returns (uint256 fee)
    {
        fee = _feePerToken[account][token][tokenId];
    }
    /**
     * @notice Retrieves the borrower fee for a specific NFT.
     * @param account The address of the lender.
     * @param token Address of the ERC721 token contract.
     * @param tokenId ID of the NFT.
     * @return total Fee amount for the specified NFT.
     */

    function _flashFee(
        address account,
        address token,
        uint256 tokenId
    )
        internal
        view
        returns (uint256 total)
    {
        uint256 tokenOwnerFee = _tokenOwnerFee(account, token, tokenId);
        total = tokenOwnerFee + calcDevFee(tokenOwnerFee, FEE_PERCENTAGE);
    }

    /**
     * @notice Executes a flash loan by lending an NFT and collecting a fee.
     *
     * @param account Address of the lender.
     * @param borrower Address of the borrower implementing IERC3156FlashBorrower.
     * @param token Address of the ERC721 token contract.
     * @param tokenId ID of the NFT.
     * @param data Arbitrary data provided by the borrower.
     * @return True if the flash loan was successful, false otherwise.
     *
     * @dev this is using ERC6682 and modulekit executorManger to lend the token out
     */
    function _flashLoan(
        address account,
        IERC3156FlashBorrower borrower,
        address token,
        uint256 tokenId,
        bytes memory data
    )
        internal
        returns (bool)
    {
        (IExecutorManager manager, bytes memory borrowData) =
            abi.decode(data, (IExecutorManager, bytes));

        // Fee that borrower has to pay to account
        uint256 tokenBorrowerFee = _tokenOwnerFee(account, token, tokenId);
        uint256 feeDev = calcDevFee(tokenBorrowerFee, FEE_PERCENTAGE);

        if (!_availableForFlashLoan(account, token, tokenId)) revert FlashLoan_TokenNotAvailable();
        if (tokenBorrowerFee == 0) revert FlashLoan_TokenNotAvailable();
        if (_flashFeeToken(account) == address(0)) revert FlashLoan_TokenNotAvailable();

        // transfering NFT to borrower
        ExecutorAction memory sendToken = ERC721ModuleKit.transferFromAction({
            token: IERC721(token),
            from: account,
            to: address(borrower),
            tokenId: tokenId
        });
        manager.exec(account, sendToken);

        // ERC3156 compliant callback
        bool success = borrower.onFlashLoan(
            account, token, tokenId, tokenBorrowerFee + feeDev, borrowData
        ) == keccak256("ERC3156FlashBorrower.onFlashLoan");
        if (!success) revert FlashLoan_CallbackFailed();

        // ensure that borrower sent token back to lender
        if (!_availableForFlashLoan(account, token, tokenId)) {
            revert FlashLoan_TokenNotTransferedBack();
        }

        // assume that borrower has set allowance to fee token
        // lender can now transfer the fee on behalf of the borrower
        ExecutorAction[] memory feeCollectionActions = new ExecutorAction[](2);

        feeCollectionActions[0] = ERC20ModuleKit.transferFromAction({
            token: IERC20(_flashFeeToken(account)),
            to: account,
            from: address(borrower),
            amount: tokenBorrowerFee
        });

        feeCollectionActions[1] = ERC20ModuleKit.transferFromAction({
            token: IERC20(_flashFeeToken(account)),
            to: FEE_RECIPIENT,
            from: address(borrower),
            amount: feeDev
        });
        manager.exec(account, feeCollectionActions);

        emit FlashLoan(account, token, tokenId, tokenBorrowerFee);
        return true;
    }

    /**
     * @dev Handles various flash loan related functions based on method signature.
     * Implements IFallbackMethod's handle method.
     *
     * This slices out the function signature from the original calldata, and calls the adequate function
     */
    function handle(
        address account,
        address sender,
        uint256 value,
        bytes calldata data
    )
        external
        override
        returns (bytes memory result)
    {
        if (data.length < 4) revert();
        bytes4 functionSig = bytes4(data[:4]);

        if (functionSig == IERC6682.availableForFlashLoan.selector) {
            (address token, uint256 tokenId) = abi.decode(data[4:], (address, uint256));
            result = abi.encode(_availableForFlashLoan(account, token, tokenId));
        } else if (functionSig == IERC6682.flashFee.selector) {
            (address token, uint256 tokenId) = abi.decode(data[4:], (address, uint256));
            result = abi.encode(_flashFee(account, token, tokenId));
        } else if (functionSig == IERC6682.flashFeeToken.selector) {
            result = abi.encode(_flashFeeToken(account));
        } else if (functionSig == IERC3156FlashLender.flashLoan.selector) {
            (
                IERC3156FlashBorrower borrower,
                address token,
                uint256 tokenId,
                bytes memory flashloanData
            ) = abi.decode(data[4:], (IERC3156FlashBorrower, address, uint256, bytes));
            return abi.encode(_flashLoan(account, borrower, token, tokenId, flashloanData));
        } else if (functionSig == IERC3156FlashBorrower.onFlashLoan.selector) {
            (
                address lender,
                address token,
                uint256 tokenId,
                uint256 fee,
                bytes memory tokenGatedAction
            ) = abi.decode(data[4:], (address, address, uint256, uint256, bytes));
            return abi.encode(_onFlashLoan(account, lender, token, tokenId, fee, tokenGatedAction));
        }
    }

    function _onFlashLoan(
        address borrowerAccount,
        address lender,
        address token,
        uint256 tokenId,
        uint256 fee,
        bytes memory _callbackParams
    )
        internal
        returns (bytes32)
    {
        CallbackParams memory callbackParams = abi.decode(_callbackParams, (CallbackParams));
        // ---- execute token gated action here
        callbackParams.managerForBorrower.exec(borrowerAccount, callbackParams.actions);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function supportsInterface(bytes4 interfaceID) external view override returns (bool) { }

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
