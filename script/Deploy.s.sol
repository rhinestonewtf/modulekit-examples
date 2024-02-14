// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { OwnableValidator } from "src/ownable-validator/OwnableValidator.sol";
import { WebAuthnValidator } from "src/webauthn-validator/WebAuthnValidator.sol";
import { ExtensibleFallbackHandler } from "modulekit/core/ExtensibleFallbackHandler.sol";
import { FlashloanCallback } from "src/coldstorage-subaccount/FlashloanCallback.sol";
import { FlashloanLender } from "src/coldstorage-subaccount/FlashloanLender.sol";
import { ColdStorageHook } from "src/coldstorage-subaccount/ColdStorageHook.sol";
import { MultiFactor } from "src/mfa/MultiFactor.sol";

/**
 * @title Deploy
 * @author @kopy-kat
 */
contract DeployScript is Script {
    function run() public {
        bytes32 salt = bytes32(uint256(0));

        vm.startBroadcast(vm.envUint("PK"));

        // Deploy Modules
        OwnableValidator ownableValidator = new OwnableValidator{ salt: salt }();
        WebAuthnValidator webAuthnValidator = new WebAuthnValidator{ salt: salt }();
        ExtensibleFallbackHandler fallbackHandler = new ExtensibleFallbackHandler{ salt: salt }();
        FlashloanCallback flashloanCallback =
            new FlashloanCallback{ salt: salt }(address(fallbackHandler));
        FlashloanLender flashloanLender =
            new FlashloanLender{ salt: salt }(address(fallbackHandler));
        ColdStorageHook coldStorageHook = new ColdStorageHook{ salt: salt }();
        MultiFactor multiFactor = new MultiFactor{ salt: salt }();

        vm.stopBroadcast();
    }
}
