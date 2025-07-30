// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Engine} from "../src/Engine.sol";
import {MockVRFSystem} from "./mocks/MockVRFSystem.sol";
import {Errors} from "../src/utils/Errors.sol";

contract EngineTest is Test {
    Engine public engine;
    MockVRFSystem public mockVRF;
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    uint public betAmount = 0.5 ether;
    uint8 public constant FEE = 3;

    function setUp() public {
        owner = makeAddr("OWNER");
        user1 = makeAddr("USER1");
        user2 = makeAddr("USER2");
        user3 = makeAddr("USER3");

        deal(user1, 10 ether);
        deal(user2, 10 ether);
        deal(user3, 10 ether);
        deal(owner, 10 ether);

        vm.startPrank(owner);
        mockVRF = new MockVRFSystem();
        engine = new Engine(FEE, address(mockVRF));
        vm.stopPrank();
    }

    function testConstructorWithZeroVRFAddress() public {
        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        new Engine(FEE, address(0));
    }
    
    function testConstructorWithExcessiveFee() public {
        vm.expectRevert(bytes(Errors.MAX_FEE_EXCEEDED));
        new Engine(4, address(mockVRF)); 
    }

    function testCreateMatchBelowMinimumBet() public {
        vm.startPrank(user1);
        vm.expectRevert(bytes(Errors.MINIMUM_BET_EXCEEDED));
        engine.createMatch{value: 0.00005 ether}();
        vm.stopPrank();
    }

    function testCreateMatchEmitsEvent() public {
        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true);
        emit Engine.MatchCreated(user1, betAmount, 0);
        engine.createMatch{value: betAmount}();
        vm.stopPrank();
    }

    function testMultipleMatchCreation() public {
        vm.startPrank(user1);
        uint256 matchId1 = engine.createMatch{value: betAmount}();
        uint256 matchId2 = engine.createMatch{value: betAmount * 2}();
        vm.stopPrank();

        assertEq(matchId1, 0);
        assertEq(matchId2, 1);
        assertEq(engine.nextMatchId(), 2);
    }

    function testJoinOwnMatch() public {
        vm.startPrank(user1);
        uint256 matchId = engine.createMatch{value: betAmount}();
        
        vm.expectRevert(bytes(Errors.CANNOT_JOIN_OWN_MATCH));
        engine.joinMatch{value: betAmount}(matchId);
        vm.stopPrank();
    }

    function testJoinWithIncorrectAmount() public {
        vm.startPrank(user1);
        uint256 matchId = engine.createMatch{value: betAmount}();
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert(bytes(Errors.INVALID_ENTRY));
        engine.joinMatch{value: betAmount * 2}(matchId);
        vm.stopPrank();
    }

    function testJoinNonExistentMatch() public {
        vm.startPrank(user2);
        vm.expectRevert(bytes(Errors.MATCH_NOT_EXIST));
        engine.joinMatch{value: betAmount}(999);
        vm.stopPrank();
    }

    function testJoinCancelledMatch() public {
        vm.startPrank(user1);
        uint256 matchId = engine.createMatch{value: betAmount}();
        engine.cancelMatch(matchId);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert(bytes(Errors.MATCH_NOT_AVAILABLE));
        engine.joinMatch{value: betAmount}(matchId);
        vm.stopPrank();
    }

    function testJoinMatchEmitsEvents() public {
        vm.startPrank(user1);
        uint256 matchId = engine.createMatch{value: betAmount}();
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectEmit(true, true, false, true);
        emit Engine.MatchJoined(matchId, user2);
        vm.expectEmit(true, true, false, true);
        emit Engine.RandomnessRequested(matchId, 1); 
        engine.joinMatch{value: betAmount}(matchId);
        vm.stopPrank();
    }

    function testRandomNumberCallbackFromInvalidCaller() public {
        vm.expectRevert(bytes(Errors.INVALID_VRF_CALLER));
        engine.randomNumberCallback(0, 12345);
    }

    function testCompleteMatchFlow() public {
        vm.startPrank(user1);
        uint256 matchId = engine.createMatch{value: betAmount}();
        vm.stopPrank();

        vm.startPrank(user2);
        engine.joinMatch{value: betAmount}(matchId);
        vm.stopPrank();

        uint256 balanceBefore1 = user1.balance;
        uint256 balanceBefore2 = user2.balance;

        vm.startPrank(address(mockVRF));
        vm.expectEmit(true, true, false, true);
        emit Engine.MatchFinished(matchId, user2, uint(keccak256(abi.encodePacked(uint(0), uint(0)))));
        engine.randomNumberCallback(0, 0);

        Engine.Match memory finalMatch = engine.getMatch(matchId);
        assertEq(finalMatch.winner, user2);
        assertEq(uint(finalMatch.status), uint(Engine.MatchStatus.FINISHED));

        uint256 totalPot = betAmount * 2;
        uint256 appFee = (totalPot * FEE) / 100;
        uint256 expectedPayout = totalPot - appFee;

        assertEq(user1.balance, balanceBefore1);
        assertEq(user2.balance, balanceBefore2 + expectedPayout); 
        assertEq(engine.feeCollected(), appFee);
    }

    function testCancelActiveMatch() public {
        vm.startPrank(user1);
        uint256 matchId = engine.createMatch{value: betAmount}();
        vm.stopPrank();

        vm.startPrank(user2);
        engine.joinMatch{value: betAmount}(matchId);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert(bytes(Errors.CANNOT_CANCEL_ACTIVE));
        engine.cancelMatch(matchId);
        vm.stopPrank();
    }

    function testCancelMatchByNonCreator() public {
        vm.startPrank(user1);
        uint256 matchId = engine.createMatch{value: betAmount}();
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert(bytes(Errors.ONLY_CREATOR_CAN_CANCEL));
        engine.cancelMatch(matchId);
        vm.stopPrank();
    }

    function testCancelMatchRefund() public {
        vm.startPrank(user1);
        uint256 balanceBefore = user1.balance;
        uint256 matchId = engine.createMatch{value: betAmount}();
        
        vm.expectEmit(true, false, false, true);
        emit Engine.MatchCancelled(matchId);
        engine.cancelMatch(matchId);
        
        assertEq(user1.balance, balanceBefore); 
        vm.stopPrank();
    }

    // === STATISTICS TESTS ===
    function testPlayerStatistics() public {
        vm.startPrank(user1);
        uint256 matchId = engine.createMatch{value: betAmount}();
        vm.stopPrank();

        vm.startPrank(user2);
        engine.joinMatch{value: betAmount}(matchId);
        vm.stopPrank();

        vm.startPrank(address(mockVRF));
        engine.randomNumberCallback(0, 0); 
        vm.stopPrank();

        assertEq(engine.playerWins(user2), 1);
        assertEq(engine.playerLosses(user2), 0);
        assertEq(engine.playerWins(user1), 0);
        assertEq(engine.playerLosses(user1), 1);
        assertEq(engine.totalFlips(), 1);
    }

    // === FEE CLAIMING TESTS ===
    function testClaimFeeByNonOwner() public {
        vm.startPrank(user1);
        vm.expectRevert("UNAUTHORIZED");
        engine.claimFee();
        vm.stopPrank();
    }

    function testClaimFeeWithZeroBalance() public {
        vm.startPrank(owner);
        uint256 balanceBefore = owner.balance;
        engine.claimFee();
        assertEq(owner.balance, balanceBefore);
        assertEq(engine.feeCollected(), 0);
        vm.stopPrank();
    }

    function testClaimFeeAfterMatches() public {
        // Complete a match to generate fees
        vm.startPrank(user1);
        uint256 matchId = engine.createMatch{value: betAmount}();
        vm.stopPrank();

        vm.startPrank(user2);
        engine.joinMatch{value: betAmount}(matchId);
        vm.stopPrank();

        vm.startPrank(address(mockVRF));
        engine.randomNumberCallback(0, 0);
        vm.stopPrank();

        uint256 expectedFee = (betAmount * 2 * FEE) / 100;
        
        vm.startPrank(owner);
        uint256 balanceBefore = owner.balance;
        engine.claimFee();
        
        assertEq(owner.balance, balanceBefore + expectedFee);
        assertEq(engine.feeCollected(), 0);
        vm.stopPrank();
    }

    // === EDGE CASES ===
    function testMatchInvalidStatus() public {
        vm.startPrank(user1);
        engine.createMatch{value: betAmount}();
        vm.stopPrank();

        vm.startPrank(address(mockVRF));
        vm.expectRevert(bytes(Errors.MATCH_NOT_ACTIVE));
        engine.randomNumberCallback(0, 12345); 
        vm.stopPrank();
    }
}