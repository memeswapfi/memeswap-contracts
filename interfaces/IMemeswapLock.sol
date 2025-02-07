// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMemeswapLock {
    function factory() external view returns (address);

    function lock(
        address lp,
        address locker,
        uint256 duration,
        uint256 amount
    ) external;

    function unlock(address lp) external returns (uint256);

    function getLocker(address lp) external view returns (address);

    function getLockAmount(address lp) external view returns (uint256);

    function getUnlockDate(address lp) external view returns (uint256);
}
