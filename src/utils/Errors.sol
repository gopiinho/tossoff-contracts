// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library Errors {
    string public constant NOT_OWNER               = "Not Owner";
    string public constant ZERO_ADDRESS            = "Zero Address";
    string public constant INVALID_VRF_CALLER      = "Only VRF system can call";
    string public constant INVALID_ENTRY           = "Invalid entry";
    string public constant MATCH_NOT_EXIST         = "Match does not exist";
    string public constant MATCH_NOT_AVAILABLE     = "Match not available";
    string public constant MATCH_NOT_ACTIVE        = "Match not active";
    string public constant CANNOT_JOIN_OWN_MATCH   = "Cannot join your own match!";
    string public constant CANNOT_CANCEL_ACTIVE    = "Cannot cancel active match";
    string public constant ONLY_CREATOR_CAN_CANCEL = "Only creator can cancel";
    string public constant FAILED_TO_SEND_WINNINGS = "Failed to send winnings";
    string public constant FAILED_TO_REFUND        = "Failed to refund";
    string public constant MAX_FEE_EXCEEDED        = "Cannot exceed max fee";
    string public constant MINIMUM_BET_EXCEEDED    = "Cannot bet less than 0.0001 ETH";
}
