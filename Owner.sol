// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract Owner{
    address private owner;
    
    constructor(){
        owner = msg.sender;
        emit OwnerSet(address(0), owner);
    }

    event OwnerSet(address indexed oldOwner, address indexed newOwner);

    modifier isOwner {
        require(owner == msg.sender, "You don't have this permission");
        _;
    }

    function changeOwner(address newOwner) public isOwner {
        emit OwnerSet(owner, newOwner);
        owner = newOwner;
    }
    function getOwner() external view returns(address){
        return owner;
    }
}