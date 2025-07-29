// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Engine} from "../src/Engine.sol";
import {MockVRFSystem} from "./mocks/MockVRFSystem.sol";

contract EngineTest is Test {
    Engine public engine;
    MockVRFSystem public mockVRF;
    address public owner;
    address public user1;
    address public user2;
    uint public betAmount = 0.5 ether;
    uint8 public constant FEE = 3;

    function setUp() public {
        owner = makeAddr("OWNER");
        user1 = makeAddr("USER1");
        user2 = makeAddr("USER2");

        deal(user1, 10 ether);
        deal(user2, 10 ether);

        vm.startPrank(owner);
        mockVRF = new MockVRFSystem();
        engine = new Engine(FEE, address(mockVRF));
        vm.stopPrank();
    }

    modifier createMatch() {
        vm.startPrank(user1);
        engine.createMatch{value: betAmount}();
        vm.stopPrank();
        _;
    }

    function testCanCreateMatch() public {
        vm.startPrank(user1);
        uint256 matchId = engine.createMatch{value: betAmount}();
        vm.stopPrank();

        Engine.Match memory gameMatch = engine.getMatch(matchId);
        assertEq(gameMatch.amount, betAmount);
        assertEq(gameMatch.player1, user1);
    }

    function testJoinMatch() public {
        vm.startPrank(user1);
        uint256 matchId = engine.createMatch{value: betAmount}();
        vm.stopPrank();

        vm.startPrank(user2);
        engine.joinMatch{value: betAmount}(matchId);
        vm.stopPrank();

        (address player1, address player2, , uint amount, , Engine.MatchStatus status) = engine.matches(matchId);
        
        assertEq(player1, user1);
        assertEq(player2, user2);
        assertEq(amount, betAmount);
        assertEq(uint(status), uint(Engine.MatchStatus.ACTIVE)); 
    }

    function testCancelMatch() public {
        vm.startPrank(user1);
        uint256 matchId = engine.createMatch{value: betAmount}();
        vm.stopPrank();

        (address player1Before, , , uint amountBefore, , Engine.MatchStatus statusBefore) = engine.matches(matchId);

        assertEq(player1Before, user1);
        assertEq(amountBefore, betAmount);
        assertEq(uint(statusBefore), uint(Engine.MatchStatus.WAITING)); 

        vm.startPrank(user1);
        engine.cancelMatch(matchId);
        vm.stopPrank();

        (, , , , , Engine.MatchStatus statusAfter) = engine.matches(matchId);

        assertEq(uint(statusAfter), uint(Engine.MatchStatus.CANCELLED));
    }

}
