// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ExecutorBase } from "modulekit/modulekit/ExecutorBase.sol";
import { IExecutorManager, ExecutorAction, ModuleExecLib } from "modulekit/modulekit/interfaces/IExecutor.sol";

enum RevocationType {
    ERC20,
    ERC721_TOKEN_ID,
    ERC721_ALL
}

struct TokenRevocation {
    address payable token;
    address spender;
    uint256 tokenId;
    RevocationType revocationType;
}

struct Schedule {
    uint16 frequency; // in days
    uint48 lastExecuted;
}

contract RevokeAllowances is ExecutorBase {
    using ModuleExecLib for IExecutorManager;

    mapping(address account => address relayer) public relayers;
    mapping(address account => Schedule schedule) public schedules;

    event RevokeExecuted(address indexed account);

    error OnlyRelayer();
    error ScheduleNotDue(address account);

    function executeRevoke(
        IExecutorManager manager,
        address account,
        TokenRevocation[] calldata revocations
    )
        external
        onlyRelayer(account)
    {
        Schedule storage schedule = schedules[account];
        if (!_scheduleIsDue(schedule)) {
            revert ScheduleNotDue(account);
        }
        schedule.lastExecuted = uint48(block.timestamp);

        uint256 revocationsLength = revocations.length;
        ExecutorAction[] memory revokeActions = new ExecutorAction[](
            revocationsLength
        );

        for (uint256 i; i < revocationsLength;) {
            bytes memory data;
            if (revocations[i].revocationType == RevocationType.ERC20) {
                data =
                    abi.encodeWithSignature("approve(address,uint256)", revocations[i].spender, 0);
            } else if (revocations[i].revocationType == RevocationType.ERC721_TOKEN_ID) {
                data = abi.encodeWithSignature(
                    "approve(address,uint256)", address(0), revocations[i].tokenId
                );
            } else if (revocations[i].revocationType == RevocationType.ERC721_ALL) {
                data = abi.encodeWithSignature(
                    "setApprovalForAll(address,bool)", revocations[i].spender, false
                );
            }
            ExecutorAction memory revokeAction =
                ExecutorAction({ to: revocations[i].token, data: data, value: 0 });
            revokeActions[i] = revokeAction;
            unchecked {
                i++;
            }
        }

        manager.exec(account, revokeActions);

        emit RevokeExecuted(account);
    }

    function setRelayer(address relayer) external {
        relayers[msg.sender] = relayer;
    }

    function setFrequency(uint16 frequency) external {
        schedules[msg.sender].frequency = frequency;
    }

    function _scheduleIsDue(Schedule storage schedule) internal view returns (bool) {
        return block.timestamp > schedule.lastExecuted + schedule.frequency * 1 days;
    }

    modifier onlyRelayer(address account) {
        if (msg.sender != relayers[account]) revert OnlyRelayer();
        _;
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
