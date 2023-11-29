// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;

abstract contract FallbackBase {
    error ERC2771Unauthorized();

    modifier onlySmartAccount() {
        _onlySmartAccount();
        _;
    }

    function _onlySmartAccount() private view {
        if (_msgSender() != msg.sender) {
            revert ERC2771Unauthorized();
        }
    }

    function _msgSender() internal view virtual returns (address sender) {
        assembly {
            sender := shr(96, calldataload(sub(calldatasize(), 20)))
        }
    }
}
