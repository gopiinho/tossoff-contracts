// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned}              from "solmate/auth/Owned.sol";
import {ReentrancyGuard}    from "solmate/utils/ReentrancyGuard.sol";
import {IVRFSystem}         from "./interfaces/IVRFSystem.sol";
import {IVRFSystemCallback} from "./interfaces/IVRFSystemCallback.sol";

contract Engine is Owned, ReentrancyGuard, IVRFSystemCallback {
    event MatchCreated        (address indexed creator, uint indexed amount, uint indexed matchId);
    event MatchFinished       (uint indexed matchId, address indexed winner, uint randomNumber);
    event RandomnessRequested (uint indexed matchId, uint indexed requestId);
    event MatchJoined         (uint indexed matchId, address indexed player2);
    event MatchCancelled      (uint indexed matchId);

    /* -------------------------------------------------------------------------- */
    /*                                     TYPES                                  */
    /* -------------------------------------------------------------------------- */
    enum MatchStatus {WAITING, ACTIVE, FINISHED, CANCELLED}

    struct Match {
        address     player1; 
        address     player2; 
        address     winner; 
        uint        amount;
        uint        createdAt;
        MatchStatus status;
    }

    /* -------------------------------------------------------------------------- */
    /*                                STATE VARIABLES                             */
    /* -------------------------------------------------------------------------- */
    IVRFSystem vrfSystem;

    uint8 public fee;
    uint8 public constant MAX_FEE = 3;

    uint    public nextMatchId;
    uint    public totalFlips;
    uint    public feeCollected;
    address public feeRecipient;

    mapping(uint => Match)   public matches;
    mapping(uint => uint)    public requestIdToMatchId;

    mapping(address => uint) public playerWins;
    mapping(address => uint) public playerLosses;

    /* -------------------------------------------------------------------------- */
    /*                                  MODIFIERS                                 */
    /* -------------------------------------------------------------------------- */
    modifier validMatch(uint _matchId) {
        require(_matchId < nextMatchId, "Match does not exist");
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */
    constructor(uint8 _fee, address _vrfSystem) Owned(msg.sender) {
        require(_vrfSystem != address(0), "Invalid VRF address");
        require(fee <= MAX_FEE,           "Cannot exceed max fee");

        fee       = _fee;
        vrfSystem = IVRFSystem(_vrfSystem);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    MATCHES                                 */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice  Creates a new match
     * @dev     Match is created by player 1
     * @return  uint  Id of the match
     */
    function createMatch() public payable nonReentrant returns (uint) {
        uint matchId = nextMatchId++;

        matches[matchId] = Match({
            player1:   msg.sender,
            player2:   address(0),
            winner:    address(0),
            amount:    msg.value,
            status:    MatchStatus.WAITING,
            createdAt: block.timestamp
        });

        emit   MatchCreated(msg.sender, msg.value, matchId);
        return matchId;
    }

    function joinMatch(uint _id) public payable nonReentrant {
        Match storage m = matches[_id];

        require(msg.sender != m.player1,           "Cannot join your own match!");
        require(m.status   == MatchStatus.WAITING, "Match not available");
        require(msg.value  == m.amount,            "Invalid entry");

        m.player2 = msg.sender;
        m.status  = MatchStatus.ACTIVE;

        emit MatchJoined(_id, msg.sender);
        _startMatch(_id);
    }

    function _startMatch(uint _id) internal returns (uint) {
        uint requestId = vrfSystem.requestRandomNumberWithTraceId(_id);
        requestIdToMatchId[requestId] = _id;

        emit RandomnessRequested(_id, requestId);
        return requestId;
    }

    function randomNumberCallback(
        uint requestId,
        uint randomNumber
    ) external override {
        require(msg.sender == address(vrfSystem), "Only VRF system can call");

        uint matchId = requestIdToMatchId[requestId];
        Match storage m = matches[matchId];
        require(m.status == MatchStatus.ACTIVE, "Match not active");

        uint finalRandom = uint(
            keccak256(abi.encodePacked(requestId, randomNumber))
        );
        uint coinFlip = finalRandom % 2;

        address winner = coinFlip == 0 ? m.player1 : m.player2;
        address loser = coinFlip == 0 ? m.player2 : m.player1;

        m.winner = winner;
        m.status = MatchStatus.FINISHED;

        playerWins[winner]++;
        playerLosses[loser]++;
        totalFlips++;

        uint totalPot = m.amount * 2;
        uint appFee = (totalPot * fee) / 100;
        uint finalPayout = totalPot - appFee;

        feeCollected += appFee;

        (bool sent, ) = winner.call{value: finalPayout}("");
        require(sent, "Failed to send winnings");

        delete requestIdToMatchId[requestId];

        emit MatchFinished(matchId, winner, finalRandom);
    }

    function cancelMatch(
        uint _matchId
    ) external nonReentrant validMatch(_matchId) {
        Match storage m = matches[_matchId];

        require(msg.sender == m.player1,           "Only creator can cancel");
        require(m.status   == MatchStatus.WAITING, "Cannot cancel active match");

        m.status = MatchStatus.CANCELLED;

        (bool sent, ) = m.player1.call{value: m.amount}("");
        require(sent, "Failed to refund");

        emit MatchCancelled(_matchId);
    }

    function claimFee() external onlyOwner {
        uint amount  = feeCollected;
        feeCollected = 0;

        (bool sent, ) = owner.call{value: amount}("");
        require(sent, "Failed to send winnings");
    }
}
