// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Engine} from "../src/Engine.sol";

contract EngineScript is Script {
    Engine public engine;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        uint8 fee = 3;
        engine = new Engine(fee);
        vm.stopBroadcast();
    }
}
