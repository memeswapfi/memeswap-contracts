// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IMemeswapFactory} from "./interfaces/IMemeswapFactory.sol";
import {IMemeswapTokenFactory} from "./interfaces/IMemeswapTokenFactory.sol";
import {IMemeswapPair} from "./interfaces/IMemeswapPair.sol";

// @title MemeswapLock
// @author Memeswap
// @notice Locks LP tokens for a specified duration.
contract MemeswapLock {
    struct Lock {
        address locker;
        uint256 amount;
        uint256 lockDuration;
        uint256 unlockDate;
    }

    address public immutable factory;
    mapping(address lp => Lock) public locks;

    /// @notice Emitted when LP tokens are locked.
    /// @param user The address of the user locking the LP tokens.
    /// @param lp The address of the LP token.
    /// @param amount The amount of LP tokens locked.
    /// @param duration The duration of the lock.
    /// @param unlockDate The date when the tokens can be unlocked.
    event Locked(address indexed user, address indexed lp, uint256 amount, uint256 duration, uint256 unlockDate);

    /// @notice Emitted when LP tokens are unlocked.
    /// @param user The address of the user unlocking the LP tokens.
    /// @param lp The address of the LP token.
    /// @param amount The amount of LP tokens unlocked.
    event Unlocked(address indexed user, address indexed lp, uint256 amount);

    error FORBIDDEN();
    error NOT_MEMESWAP_LP();
    error INVALID_DURATION();

    /// @notice Constructor that initializes the contract.
    /// @dev Sets the factory address as the contract deployer.
    constructor() {
        factory = msg.sender;
    }

    /// @notice Locks the specified amount of LP tokens.
    /// @param _locker The address of the user locking the tokens.
    /// @param _amount The amount of LP tokens to lock.
    function lock(address _pair, address _locker, uint256 _duration, uint256 _amount) external {
        address tokenFactory = IMemeswapFactory(factory).tokenFactory();
        if (!IMemeswapFactory(factory).isPair(_pair)) revert NOT_MEMESWAP_LP();
        if (msg.sender != tokenFactory) revert FORBIDDEN();
        locks[_pair].lockDuration = _duration;
        locks[_pair].locker = _locker;
        locks[_pair].amount = _amount;
        uint256 unlocksAt = block.timestamp + _duration;
        locks[_pair].unlockDate = unlocksAt;
        emit Locked(_locker, _pair, _amount, _duration, unlocksAt);
    }

    /// @notice Unlocks the LP tokens if the lock duration has passed.
    /// @param _lp The address of the LP token.
    /// @return amount The amount of LP tokens unlocked.
    function unlock(address _lp) external returns (uint256 amount) {
        address tokenFactory = IMemeswapFactory(factory).tokenFactory();
        if (!IMemeswapFactory(factory).isPair(_lp)) revert NOT_MEMESWAP_LP();
        if (!(IMemeswapTokenFactory(tokenFactory).vault() == msg.sender)) {
            revert FORBIDDEN();
        }
        amount = locks[_lp].amount;
        IERC20(_lp).transfer(locks[_lp].locker, amount);
        delete locks[_lp];
        emit Unlocked(msg.sender, _lp, amount);
    }

    /// @notice Gets the locker address for the specified LP token.
    /// @param _lp The address of the LP token.
    /// @return The address of the locker.
    function getLocker(address _lp) external view returns (address) {
        return locks[_lp].locker;
    }

    /// @notice Gets the locked amount for the specified LP token.
    /// @param _lp The address of the LP token.
    /// @return The amount of LP tokens locked.
    function getLockAmount(address _lp) external view returns (uint256) {
        return locks[_lp].amount;
    }

    /// @notice Gets the unlock date for the specified LP token.
    /// @param _lp The address of the LP token.
    /// @return The unlock date.
    function getUnlockDate(address _lp) external view returns (uint256) {
        return locks[_lp].unlockDate;
    }
}
