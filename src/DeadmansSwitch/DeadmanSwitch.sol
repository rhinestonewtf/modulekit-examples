// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "modulekit/modulekit/IHook.sol";
import "modulekit/modulekit/IExecutor.sol";
import "modulekit/modulekit/ValidatorBase.sol";

contract DeadmanSwitch is IHook, ICondition, IValidator {
    mapping(address account => uint256 lastAccess) public lastAccess;

    struct DeadmansSwitchParams {
        uint256 timeout;
    }

    function preCheck(address account, ExecutorTransaction calldata, uint256, bytes calldata)
        external
        override
        returns (bytes memory)
    {
        lastAccess[account] = block.timestamp;
    }

    function preCheckRootAccess(
        address account,
        ExecutorTransaction calldata rootAccess,
        uint256 executionType,
        bytes calldata executionMeta
    ) external override returns (bytes memory preCheckData) {}

    function postCheck(address account, bool success, bytes calldata preCheckData) external override {}

    function checkCondition(address account, address, bytes calldata conditions, bytes calldata)
        public
        view
        override
        returns (bool)
    {
        DeadmansSwitchParams memory params = abi.decode(conditions, (DeadmansSwitchParams));
        return block.timestamp + params.timeout >= lastAccess[account];
    }

    function isValidSignature(bytes32 hash, bytes memory signature)
        external
        view
        override
        returns (bytes4 magicValue)
    {
        return 0xFFFFFFFF;
    }

    function validateUserOp(UserOperation calldata userOp, bytes32 userOpHash) external override returns (uint256) {
        address account = userOp.sender;
        if (checkCondition(account, address(0), userOp.signature, userOp.callData)) return 1;
        return 0;
    }

    function supportsInterface(bytes4 interfaceID) external view override returns (bool) {}
}
