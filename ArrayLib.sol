// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

library ArrayAddressLib {
    function indexOf(address[] storage arr, address x) internal view returns (bool) {
        for (uint i = 0; i < arr.length; i++) {
            if (arr[i] == x) {
                return true;
            }
        }
        return false;
    }
}