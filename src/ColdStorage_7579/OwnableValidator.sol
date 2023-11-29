import { IValidator, IERC4337 } from "erc7579/interfaces/IModule.sol";

import { SignatureCheckerLib } from "solady/src/utils/SignatureCheckerLib.sol";

contract OwnableValidator is IValidator {
    mapping(address subAccout => address) public owners;

    function onInstall(bytes calldata data) external override {
        address owner = abi.decode(data, (address));
        owners[msg.sender] = owner;
    }

    function onUninstall(bytes calldata data) external override { }

    function validateUserOp(
        IERC4337.UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    )
        external
        override
        returns (uint256)
    {
        bytes calldata signature = userOp.signature;

        bool isValid =
            SignatureCheckerLib.isValidSignatureNow(owners[userOp.sender], userOpHash, signature);
        if (isValid) {
            return 1;
        }
    }

    function isValidSignatureWithSender(
        address sender,
        bytes32 hash,
        bytes calldata data
    )
        external
        view
        override
        returns (bytes4)
    { }
}
