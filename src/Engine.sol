// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Engine {
    uint256 public totalFlips;

    struct Match {
        address player1;
        address player2;
        address winner;
        uint256 id;
        uint256 amount;
        uint256 deadline;
        bool isStarted;
        bool isFinished;
    }

    Match[] internal activeGames;

    function createMatch(uint256 amount, uint256 duration) public payable returns (uint256) {
        require(msg.value >= amount, "Invalid amount");
        require(duration >= 5 minutes, "Duration must be more than 5 minutes");

        uint256 deadline = block.timestamp + duration;
        uint256 matchId = activeGames.length;
        activeGames.push(Match(msg.sender, address(0), address(0), matchId, amount, deadline, false, false));

        return matchId;
    }

    function joinMatch(uint256 _id) public payable {
        require(_id < activeGames.length, "Match does not exist!");

        Match storage m = activeGames[_id];

        require(m.isFinished == false, "Match is already finished!");
        require(block.timestamp <= m.deadline, "Match expired");
        require(msg.value == m.amount, "Invalid entry");

        startMatch(_id);
    }

    function startMatch(uint256 _id) public payable {}

    function cancelMatch(uint256 _id) public {
        Match storage m = activeGames[_id];
        address p1 = m.player1;
        uint256 deadline = m.deadline;

        require(p1 == msg.sender, "Not the creator");
        require(deadline < block.timestamp, "Already expired");

        (bool sent,) = p1.call{value: m.amount}("");
        require(sent, "Failed to refund");

        m.isFinished = true;
    }
}
