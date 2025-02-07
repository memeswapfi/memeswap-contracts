// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IInterpolLock {
    function setOperator(address operator) external;

    function setTreasury(address treasury) external;

    function depositAndLock(
        address lpToken,
        uint256 amountOrId,
        uint256 expiration
    ) external;

    function transferOwnership(address newOwner) external;
}
