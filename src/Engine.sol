// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Engine {
    event MatchCreated(
        address indexed creator,
        uint256 indexed amount,
        uint256 indexed matchId,
        uint256 deadline
    );
    event MatchFinished(uint256 indexed matchId, address winner);

    /* -------------------------------------------------------------------------- */
    /*                                     TYPES                                  */
    /* -------------------------------------------------------------------------- */
    struct Match {
        address player1;
        address player2;
        address winner;
        uint256 id;
        uint256 amount;
        uint256 deadline;
        bool isFinished;
    }

    /* -------------------------------------------------------------------------- */
    /*                                STATE VARIABLES                             */
    /* -------------------------------------------------------------------------- */
    uint256 public totalFlips;

    uint256 public feeCollected;
    address public feeRecipient;

    Match[] internal activeMatches;

    uint256 public constant FEE = 3;

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */
    constructor(address _owner) {
        feeRecipient = _owner;
    }

    /* -------------------------------------------------------------------------- */
    /*                                    MATCHES                                 */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice  Creates a new match
     * @dev     Match is created by player 1
     * @param   amount  Amount of ETH to be wagered in the match
     * @param   duration  Duration of match, after which if not joined by another player, the match will expire
     * @return  uint256  Id of the match
     */
    function createMatch(
        uint256 amount,
        uint256 duration
    ) public payable returns (uint256) {
        require(msg.value >= amount, "Invalid amount");
        require(duration >= 5 minutes, "Duration must be more than 5 minutes");

        uint256 deadline = block.timestamp + duration;
        uint256 matchId = activeMatches.length;
        activeMatches.push(
            Match(
                msg.sender,
                address(0),
                address(0),
                matchId,
                amount,
                deadline,
                false
            )
        );

        emit MatchCreated(msg.sender, amount, matchId, deadline);
        return matchId;
    }

    function joinMatch(uint256 _id) public payable {
        require(_id < activeMatches.length, "Match does not exist!");

        Match storage m = activeMatches[_id];

        require(msg.sender != m.player1, "Cannot join your own match!");
        require(!m.isFinished, "Match is already finished!");
        require(block.timestamp <= m.deadline, "Match expired");
        require(msg.value == m.amount, "Invalid entry");

        startMatch(_id);
    }

    function startMatch(uint256 _id) internal {
        Match storage m = activeMatches[_id];

        m.player2 = msg.sender;

        // temporary: convert to vrf randomness
        uint256 result = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.prevrandao,
                    m.player1,
                    m.player2
                )
            )
        ) % 2;

        address winner = result == 0 ? m.player1 : m.player2;
        m.winner = winner;
        m.isFinished = true;

        uint256 totalPot = m.amount * 2;
        uint256 fee = (totalPot * FEE) / 100;
        uint256 finalPayout = totalPot - fee;

        feeCollected += fee;
        (bool sent, ) = winner.call{value: finalPayout}("");
        require(sent, "Failed to send winnings");

        emit MatchFinished(_id, winner);
    }

    function cancelMatch(uint256 _id) public {
        Match storage m = activeMatches[_id];
        address p1 = m.player1;
        uint256 deadline = m.deadline;

        require(p1 == msg.sender, "Not the creator");
        require(deadline < block.timestamp, "Already expired");

        (bool sent, ) = p1.call{value: m.amount}("");
        require(sent, "Failed to refund");

        m.isFinished = true;
    }

    function claimFee() external {
        require(msg.sender == feeRecipient, "Cannot claim");

        uint256 amount = feeCollected;
        feeCollected = 0;

        (bool sent, ) = feeRecipient.call{value: amount}("");
        require(sent, "Failed to send winnings");
    }
}
