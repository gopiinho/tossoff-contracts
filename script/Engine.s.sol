// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Engine} from "../src/Engine.sol";

contract EngineScript is Script {
    Engine public engine;
    uint8 fee = 3;
    address vrfSystem = 0xBDC8B6eb1840215A22fC1134046f595b7D42C2DE;
    address vrfSystemTestnet = 0xC04ae87CDd258994614f7fFB8506e69B7Fd8CF1D;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        engine = new Engine(fee, vrfSystemTestnet);
        vm.stopBroadcast();
    }
}
