// SPDX-License-Identifier: MIT 
pragma solidity 0.8.19;

contract Guard{
    bool private lock;
    modifier locked{
        require(!lock, "Wait for unlock");
        lock = true;
        _;
        lock = false;
    }

    
}