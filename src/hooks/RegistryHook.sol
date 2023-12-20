// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "../ColdStorage_7579/HookBase.sol";

interface IERC7484 {
    function check(address module, address attester) external view returns (uint256 attestedAt);
    function checkN(
        address module,
        address[] memory attesters,
        uint256 threshold
    )
        external
        view
        returns (uint256[] memory attestedAtArray);
}

contract RegistryHook is HookBase {
    IERC7484 immutable _registry;

    mapping(address account => address attester) public attesterOf;

    constructor(address registry) {
        _registry = IERC7484(registry);
    }

    function onInstall(bytes calldata data) external override {
        (address attester) = abi.decode(data, (address));
        attesterOf[msg.sender] = attester;
    }

    function onUninstall(bytes calldata) external override {
        attesterOf[msg.sender] = address(0);
    }

    function setAttester(address attester) external {
        attesterOf[msg.sender] = attester;
    }

    function onPostCheck(bytes calldata hookData)
        internal
        virtual
        override
        returns (bool success)
    { }

    function onExecute(
        address msgSender,
        address target,
        uint256 value,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    { }

    function onExecuteBatch(
        address msgSender,
        IExecution.Execution[] calldata
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    { }

    function onExecuteFromModule(
        address executorModule,
        address target,
        uint256 value,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        address attester = attesterOf[msg.sender];
        _registry.check(executorModule, attester);
    }

    function onExecuteBatchFromModule(
        address executorModule,
        IExecution.Execution[] memory
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        address attester = attesterOf[msg.sender];
        _registry.check(executorModule, attester);
    }

    function onExecuteDelegateCall(
        address msgSender,
        address target,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    { }

    function onExecuteDelegateCallFromModule(
        address executorModule,
        address target,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        address attester = attesterOf[msg.sender];
        _registry.check(executorModule, attester);
    }

    function onEnableExecutor(
        address msgSender,
        address executorModule,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        address attester = attesterOf[msg.sender];
        _registry.check(executorModule, attester);
    }

    function onDisableExecutor(
        address msgSender,
        address executor,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    { }

    function onEnableValidator(
        address msgSender,
        address validatorModule,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        address attester = attesterOf[msg.sender];
        _registry.check(validatorModule, attester);
    }

    function onDisableValidator(
        address msgSender,
        address validator,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    { }

    function onDisableHook(
        address msgSender,
        address hookModule,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    { }

    function onEnableHook(
        address msgSender,
        address hookModule,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        address attester = attesterOf[msg.sender];
        _registry.check(hookModule, attester);
    }
}
