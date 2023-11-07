// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import "forge-std/console2.sol";

contract MainnetTest is Test {
    uint256 mainnetFork;

    function setUp() public virtual {
        string memory mainnetUrl = vm.envString("MAINNET_RPC_URL");
        console2.log("mainnetUrl", mainnetUrl);
        mainnetFork = vm.createFork(mainnetUrl);
        vm.selectFork(mainnetFork);
        vm.rollFork(17_824_671);
    }
}
