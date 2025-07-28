// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Owned} from "solmate/auth/Owned.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {IVRFSystem} from "./interfaces/IVRFSystem.sol";
import {IVRFSystemCallback} from "./interfaces/IVRFSystemCallback.sol";

contract Engine is Owned, ReentrancyGuard, IVRFSystemCallback {
    event MatchCreated(
        address indexed creator,
        uint256 indexed amount,
        uint256 indexed matchId
    );
    event MatchJoined(uint256 indexed matchId, address indexed player2);
    event RandomnessRequested(
        uint256 indexed matchId,
        uint256 indexed requestId
    );
    event MatchFinished(
        uint256 indexed matchId,
        address indexed winner,
        uint256 randomNumber
    );
    event MatchCancelled(uint256 indexed matchId, string reason);

    /* -------------------------------------------------------------------------- */
    /*                                     TYPES                                  */
    /* -------------------------------------------------------------------------- */
    enum MatchStatus {
        WAITING,
        ACTIVE,
        FINISHED,
        CANCELLED
    }

    struct Match {
        address player1;
        address player2;
        address winner;
        uint256 amount;
        uint256 createdAt;
        MatchStatus status;
    }

    /* -------------------------------------------------------------------------- */
    /*                                STATE VARIABLES                             */
    /* -------------------------------------------------------------------------- */
    IVRFSystem vrfSystem;

    uint8 public fee;
    uint8 public constant MAX_FEE = 3;

    uint256 public nextMatchId;
    uint256 public totalFlips;
    uint256 public feeCollected;
    address public feeRecipient;

    mapping(uint256 => Match) public matches;
    mapping(uint256 => uint256) public requestIdToMatchId;

    mapping(address => uint256) public playerWins;
    mapping(address => uint256) public playerLosses;

    /* -------------------------------------------------------------------------- */
    /*                                  MODIFIERS                                 */
    /* -------------------------------------------------------------------------- */
    modifier validMatch(uint256 _matchId) {
        require(_matchId < nextMatchId, "Match does not exist");
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */
    constructor(uint8 _fee, address _vrfSystem) Owned(msg.sender) {
        require(fee <= MAX_FEE, "Cannot exceed max fee");
        require(_vrfSystem != address(0), "Invalid VRF address");

        fee = _fee;
        vrfSystem = IVRFSystem(_vrfSystem);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    MATCHES                                 */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice  Creates a new match
     * @dev     Match is created by player 1
     * @return  uint256  Id of the match
     */
    function createMatch() public payable nonReentrant returns (uint256) {
        uint256 matchId = nextMatchId++;

        matches[matchId] = Match({
            player1: msg.sender,
            player2: address(0),
            winner: address(0),
            amount: msg.value,
            status: MatchStatus.WAITING,
            createdAt: block.timestamp
        });

        emit MatchCreated(msg.sender, msg.value, matchId);
        return matchId;
    }

    function joinMatch(uint256 _id) public payable nonReentrant {
        Match storage m = matches[_id];

        require(msg.sender != m.player1, "Cannot join your own match!");
        require(m.status == MatchStatus.WAITING, "Match not available");
        require(msg.value == m.amount, "Invalid entry");

        m.player2 = msg.sender;
        m.status = MatchStatus.ACTIVE;

        emit MatchJoined(_id, msg.sender);
        _startMatch(_id);
    }

    function _startMatch(uint256 _id) internal returns (uint256) {
        uint256 requestId = vrfSystem.requestRandomNumberWithTraceId(_id);
        requestIdToMatchId[requestId] = _id;

        emit RandomnessRequested(_id, requestId);
        return requestId;
    }

    function randomNumberCallback(
        uint256 requestId,
        uint256 randomNumber
    ) external override {
        require(msg.sender == address(vrfSystem), "Only VRF system can call");

        uint256 matchId = requestIdToMatchId[requestId];
        Match storage m = matches[matchId];
        require(m.status == MatchStatus.ACTIVE, "Match not active");

        uint256 finalRandom = uint256(
            keccak256(abi.encodePacked(requestId, randomNumber))
        );
        uint256 coinFlip = finalRandom % 2;

        address winner = coinFlip == 0 ? m.player1 : m.player2;
        address loser = coinFlip == 0 ? m.player2 : m.player1;

        m.winner = winner;
        m.status = MatchStatus.FINISHED;

        playerWins[winner]++;
        playerLosses[loser]++;
        totalFlips++;

        uint256 totalPot = m.amount * 2;
        uint256 appFee = (totalPot * fee) / 100;
        uint256 finalPayout = totalPot - appFee;

        feeCollected += appFee;

        (bool sent, ) = winner.call{value: finalPayout}("");
        require(sent, "Failed to send winnings");

        delete requestIdToMatchId[requestId];

        emit MatchFinished(matchId, winner, finalRandom);
    }

    function cancelMatch(
        uint256 _matchId
    ) external nonReentrant validMatch(_matchId) {
        Match storage m = matches[_matchId];

        require(msg.sender == m.player1, "Only creator can cancel");
        require(m.status == MatchStatus.WAITING, "Cannot cancel active match");

        m.status = MatchStatus.CANCELLED;

        (bool sent, ) = m.player1.call{value: m.amount}("");
        require(sent, "Failed to refund");

        emit MatchCancelled(_matchId, "manual");
    }

    function claimFee() external onlyOwner {
        uint256 amount = feeCollected;
        feeCollected = 0;

        (bool sent, ) = owner.call{value: amount}("");
        require(sent, "Failed to send winnings");
    }
}
