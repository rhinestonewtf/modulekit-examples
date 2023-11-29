// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/interfaces/IERC20.sol";

interface IERC6682 {
    /// @dev The address of the token used to pay flash loan fees.
    function flashFeeToken() external view returns (address);

    /// @dev Whether or not the NFT is available for a flash loan.
    /// @param token The address of the NFT contract.
    /// @param tokenId The ID of the NFT.
    function availableForFlashLoan(address token, uint256 tokenId) external view returns (bool);
}

interface IERC3156FlashBorrower {
    /**
     * @dev Receive a flash loan.
     * @param initiator The initiator of the loan.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param fee The additional amount of tokens to repay.
     * @param data Arbitrary data structure, intended to contain user-defined parameters.
     * @return The keccak256 hash of "ERC3156FlashBorrower.onFlashLoan"
     */
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    )
        external
        returns (bytes memory);
}

interface IERC3156FlashLender {
    /**
     * @dev The amount of currency available to be lent.
     * @param token The loan currency.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token) external view returns (uint256);

    /**
     * @dev The fee to be charged for a given loan.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(address token, uint256 amount) external view returns (uint256);

    /**
     * @dev Initiate a flash loan.
     * @param receiver The receiver of the tokens in the loan, and the receiver of the callback.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param data Arbitrary data structure, intended to contain user-defined parameters.
     */
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    )
        external
        returns (bool);
}

abstract contract SubAccountFlashLoan is IERC3156FlashLender, IERC6682 {
    enum TokenType {
        ERC20,
        ERC721
    }

    function owner() internal view virtual returns (address);
    function maxFlashLoan(address token) external view override returns (uint256) { }

    function flashFee(address token, uint256 amount) external view override returns (uint256) { }

    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    )
        external
        override
        returns (bool)
    {
        address subAccountOwner = owner();
        if (address(receiver) != subAccountOwner) return false;

        TokenType tokenType = abi.decode(data, (TokenType));

        bool repaid;
        if (tokenType == TokenType.ERC20) {
            repaid = _flashLoanERC20(receiver, subAccountOwner, token, amount, data);
        } else if (tokenType == TokenType.ERC721) {
            revert("ERC721 not implemented yet");
        }

        if (!repaid) revert();
    }

    function _flashLoanERC20(
        IERC3156FlashBorrower receiver,
        address subAccountOwner,
        address token,
        uint256 amount,
        bytes calldata data
    )
        private
        returns (bool repaid)
    {
        IERC20(token).transfer(address(receiver), amount);
        receiver.onFlashLoan(subAccountOwner, token, amount, 0, data);
        repaid = IERC20(token).transferFrom(address(receiver), address(this), amount);
    }

    function flashFeeToken() external view override returns (address) { }

    function availableForFlashLoan(
        address token,
        uint256 tokenId
    )
        external
        view
        override
        returns (bool)
    { }
}
