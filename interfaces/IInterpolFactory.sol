// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IInterpolFactory {
    event NewLocker(address indexed owner, address locker);

    function createLocker(address _owner, address _referral, bool _unlocked) external returns (address payable);
}
