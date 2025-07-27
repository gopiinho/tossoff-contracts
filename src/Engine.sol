// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Owned} from "solmate/auth/Owned.sol";
import {IVRFSystem} from "./interfaces/IVRFSystem.sol";

contract Engine is Owned {
    event MatchCreated(
        address indexed creator,
        uint256 indexed amount,
        uint256 indexed matchId
    );
    event MatchFinished(uint256 indexed matchId, address indexed winner);

    /* -------------------------------------------------------------------------- */
    /*                                     TYPES                                  */
    /* -------------------------------------------------------------------------- */
    struct Match {
        address player1;
        address player2;
        address winner;
        uint256 id;
        uint256 amount;
        bool isFinished;
    }

    /* -------------------------------------------------------------------------- */
    /*                                STATE VARIABLES                             */
    /* -------------------------------------------------------------------------- */
    IVRFSystem vrfSystem;

    uint8 public fee;
    uint8 public constant MAX_FEE = 3;

    uint256 public totalFlips;
    uint256 public feeCollected;
    address public feeRecipient;

    Match[] internal activeMatches;

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */
    constructor(uint8 _fee, address _vrfSystem) Owned(msg.sender) {
        fee = _fee;
        vrfSystem = IVRFSystem(_vrfSystem);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    MATCHES                                 */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice  Creates a new match
     * @dev     Match is created by player 1
     * @param   amount  Amount of ETH to be wagered in the match
     * @return  uint256  Id of the match
     */
    function createMatch(uint256 amount) public payable returns (uint256) {
        require(msg.value >= amount, "Invalid amount");

        uint256 matchId = activeMatches.length;
        activeMatches.push(
            Match(msg.sender, address(0), address(0), matchId, amount, false)
        );

        emit MatchCreated(msg.sender, amount, matchId);
        return matchId;
    }

    function joinMatch(uint256 _id) public payable {
        require(_id < activeMatches.length, "Match does not exist!");

        Match storage m = activeMatches[_id];

        require(msg.sender != m.player1, "Cannot join your own match!");
        require(!m.isFinished, "Match is already finished!");
        require(msg.value == m.amount, "Invalid entry");

        startMatch(_id);
    }

    function startMatch(uint256 _id) internal {
        Match storage m = activeMatches[_id];

        m.player2 = msg.sender;

        uint256 randomNumber = vrfSystem.requestRandomNumberWithTraceId(0);
        uint256 rand = randomNumber % 2;

        address winner = rand == 0 ? m.player1 : m.player2;
        m.winner = winner;
        m.isFinished = true;

        uint256 totalPot = m.amount * 2;
        uint256 appFee = (totalPot * fee) / 100;
        uint256 finalPayout = totalPot - appFee;

        feeCollected += appFee;
        (bool sent, ) = winner.call{value: finalPayout}("");
        require(sent, "Failed to send winnings");

        emit MatchFinished(_id, winner);
    }

    function cancelMatch(uint256 _id) public {
        Match storage m = activeMatches[_id];
        address p1 = m.player1;

        require(p1 == msg.sender, "Not the creator");

        (bool sent, ) = p1.call{value: m.amount}("");
        require(sent, "Failed to refund");

        m.isFinished = true;
    }

    function claimFee() external onlyOwner {
        uint256 amount = feeCollected;
        feeCollected = 0;

        (bool sent, ) = owner.call{value: amount}("");
        require(sent, "Failed to send winnings");
    }
}
