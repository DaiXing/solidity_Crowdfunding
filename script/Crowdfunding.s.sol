// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
// import {Counter} from "../src/Counter.sol";
import {
    // ProjectState,
    // ProjectInfoContract,
    ProjectFactoryContract
} from "../src/Crowdfunding.sol";

contract CrownfundingScript is Script {
    ProjectFactoryContract public factory;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        factory = new ProjectFactoryContract();

        vm.stopBroadcast();
    }
}
