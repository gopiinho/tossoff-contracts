// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Engine} from "../src/Engine.sol";

contract EngineTest is Test {
    Engine public engine;
    address public owner;

    uint8 public constant FEE = 3;
    address public constant VRF = 0xC04ae87CDd258994614f7fFB8506e69B7Fd8CF1D;

    function setUp() public {
        owner = makeAddr("OWNER");

        vm.startPrank(owner);
        engine = new Engine(FEE, VRF);
        vm.stopPrank();
    }
}
