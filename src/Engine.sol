// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned}              from "solmate/auth/Owned.sol";
import {ReentrancyGuard}    from "solmate/utils/ReentrancyGuard.sol";
import {IVRFSystem}         from "./interfaces/IVRFSystem.sol";
import {IVRFSystemCallback} from "./interfaces/IVRFSystemCallback.sol";

contract Engine is Owned, ReentrancyGuard, IVRFSystemCallback {
    error NotOwner();
    error ZeroAddress(); 
    error InvalidVrfCaller();
    error InvalidEntry();
    error MatchNotExist();
    error MatchNotAvailable();
    error MatchNotActive();
    error CannotJoinOwnMatch();
    error CannotCancelMatch();
    error OnlyCreatorCanCancel();
    error FailedToSendWinnings();
    error FailedToRefund();
    error MaxFeeExceeded();
    error MinimumBetExceeded();

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
    uint  public constant MIN_BET = 0.0001 ether;

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
        require(_matchId < nextMatchId, MatchNotExist());
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */
    constructor(uint8 _fee, address _vrfSystem) Owned(msg.sender) {
        require(_vrfSystem != address(0), ZeroAddress());
        require(_fee <= MAX_FEE,          MaxFeeExceeded());

        fee       = _fee;
        vrfSystem = IVRFSystem(_vrfSystem);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    MATCHES                                 */
    /* -------------------------------------------------------------------------- */
    function createMatch() public payable nonReentrant returns (uint) {
        require (msg.value >= MIN_BET, MinimumBetExceeded());
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

    function joinMatch(uint _id) public payable validMatch(_id) nonReentrant {
        Match storage m = matches[_id];

        require(msg.sender != m.player1,           CannotJoinOwnMatch());
        require(m.status   == MatchStatus.WAITING, MatchNotAvailable());
        require(msg.value  == m.amount,            InvalidEntry());

        m.player2 = msg.sender;
        m.status  = MatchStatus.ACTIVE;

        emit MatchJoined(_id, msg.sender);
        _startMatch(_id);
    }

    function _startMatch(uint _id) internal returns (uint) {
        uint requestId                = vrfSystem.requestRandomNumberWithTraceId(_id);
        requestIdToMatchId[requestId] = _id;

        emit RandomnessRequested(_id, requestId);
        return requestId;
    }

    function randomNumberCallback(uint requestId, uint randomNumber) external override {
        require(msg.sender == address(vrfSystem), InvalidVrfCaller());

        uint matchId     = requestIdToMatchId[requestId];
        Match storage m  = matches[matchId];
        require(m.status == MatchStatus.ACTIVE, MatchNotActive());

        uint finalRandom = uint(
            keccak256(abi.encodePacked(requestId, randomNumber))
        );
        uint coinFlip = finalRandom % 2;

        address winner = coinFlip == 0 ? m.player1 : m.player2;
        address loser  = coinFlip == 0 ? m.player2 : m.player1;

        m.winner = winner;
        m.status = MatchStatus.FINISHED;

        unchecked {
            ++playerWins[winner];
            ++playerLosses[loser];
            ++totalFlips;
        }
       
        uint totalPot = m.amount * 2;
        uint appFee   = (totalPot * fee) / 100;

        unchecked {
            feeCollected += appFee;
        }

        (bool sent, ) = winner.call{value: totalPot - appFee}("");
        require(sent, FailedToSendWinnings());

        delete requestIdToMatchId[requestId];
        emit MatchFinished(matchId, winner, finalRandom);
    }

    function cancelMatch(uint _matchId) external nonReentrant validMatch(_matchId) {
        Match storage m = matches[_matchId];

        require(msg.sender == m.player1,           OnlyCreatorCanCancel());
        require(m.status   == MatchStatus.WAITING, CannotCancelMatch());

        m.status = MatchStatus.CANCELLED;

        (bool sent, ) = m.player1.call{value: m.amount}("");
        require(sent, FailedToRefund());

        emit MatchCancelled(_matchId);
    }

     function getMatch(uint _matchId) external view returns (Match memory) {
        return matches[_matchId];
    }

    function claimFee() external onlyOwner {
        uint amount  = feeCollected;
        feeCollected = 0;

        (bool sent, ) = owner.call{value: amount}("");
        require(sent, FailedToSendWinnings());
    }
}