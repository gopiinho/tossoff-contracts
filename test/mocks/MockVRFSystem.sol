// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IVRFSystem} from "../../src/interfaces/IVRFSystem.sol";
import {IVRFSystemCallback} from "../../src/interfaces/IVRFSystemCallback.sol";

contract MockVRFSystem is IVRFSystem {
    uint256 public nextRequestId = 1;
    
    function requestRandomNumberWithTraceId(uint256 traceId) external returns (uint256) {
        uint256 requestId = nextRequestId++;
        
        // IVRFSystemCallback(msg.sender).randomNumberCallback(requestId, 12345); 
        
        return requestId;
    }
}