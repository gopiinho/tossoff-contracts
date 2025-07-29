// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Engine} from "../src/Engine.sol";

contract EngineTest is Test {
    Engine public engine;
    address public owner;
    address public user;
    uint256 public betAmount = 0.5 ether;

    uint8 public constant FEE = 3;
    address public constant VRF = 0xC04ae87CDd258994614f7fFB8506e69B7Fd8CF1D;

    function setUp() public {
        owner = makeAddr("OWNER");
        user = makeAddr("USER");

        deal(user, 10 ether);

        vm.startPrank(owner);
        engine = new Engine(FEE, VRF);
        vm.stopPrank();
    }

    modifier createMatch() {
        vm.startPrank(user);
        engine.createMatch{value: betAmount}();
        vm.stopPrank();
        _;
    }

    function testCanCreateMatch() public {
        vm.startPrank(user);
        uint256 matchId = engine.createMatch{value: betAmount}();
        vm.stopPrank();

        Engine.Match memory gameMatch = engine.getMatch(matchId);
        assertEq(gameMatch.amount, betAmount);
        assertEq(gameMatch.player1, user);
    }
}
