// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IMemeswapLock} from "./interfaces/IMemeswapLock.sol";
import {IMemeswapToken} from "./interfaces/IMemeswapToken.sol";
import {IMemeswapFactory} from "./interfaces/IMemeswapFactory.sol";
import {IMemeswapTokenFactory} from "./interfaces/IMemeswapTokenFactory.sol";
import {IMemeswapPair} from "./interfaces/IMemeswapPair.sol";
import {IInterpolFactory} from "./interfaces/IInterpolFactory.sol";
import {IInterpolLock} from "./interfaces/IInterpolLock.sol";

/// @title MemeswapVault
/// @author Memeswap
/// @notice This contract is for staking and renting liquidity for MemeswapToken contracts.
/// @dev Vault contracts are deployed separately and announced on MemeswapTokenFactory.
contract MemeswapVault is ReentrancyGuard, Ownable {
    struct Queue {
        address user;
        uint256 amount;
    }

    struct Rent {
        address user;
        address token;
        uint256 amount;
        uint256 duration;
        uint256 endDate;
    }

    uint256 public immutable SCALE = 1e18;
    uint256 public immutable PARAMS_SCALE = 100;
    uint256 public minAPR = 10;
    uint256 public maxAPR = 200;
    uint256 public duration = 7 days;
    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public rewardAmount;
    uint256 public totalSupply;
    uint256 public rentedSupply;
    address public immutable weth;
    address public immutable factory;
    address public interpolFactory;
    uint256 public fee = 25;
    uint256 public valhallaFee = 5;
    uint256 public chadBar = 10;
    uint256 public queueFirst;
    uint256 public queueLast;
    uint256 public totalInQueue;
    uint256 public constant minAmount = 0.0001 ether;
    mapping(address => uint256) userRewardPerToken;
    mapping(address => uint256) rewards;
    mapping(address => uint256) public balances;
    mapping(address => Rent) public rents;
    mapping(uint256 => Queue) public queue;
    mapping(address => uint256) public userTotalQueue;
    mapping(address => uint256) public toWithdraw;
    mapping(address => uint256) public valhallaDate;
    mapping(address => address) public interpolLocks;

    error ZERO_AMOUNT();
    error ZERO_ADDRESS();
    error FORBIDDEN();
    error VAULT_DRY();
    error WRONG_AMOUNT();
    error OUT_OF_RANGE();
    error ENQUEUE_TOO_SOON();
    error WRONG_DURATION();
    error NOT_WHITELISTED();
    error TRANSACTION_FAILED();
    error NOT_ALLOWED();

    /// @notice Emitted when a user stakes an amount of ETH
    /// @param user The user who staked
    /// @param amount The amount staked
    event Staked(address indexed user, uint256 amount);

    /// @notice Emitted when a user withdraws an amount
    /// @param user The user who withdrew
    /// @param amount The amount withdrawn
    event Withdrawn(address indexed user, uint256 amount);

    /// @notice Emitted when a rental is created
    /// @param pair The pair involved in the rental
    /// @param amount The amount rented
    /// @param duration The duration for which the liquidity is rented
    event RentalCreated(address indexed pair, uint256 amount, uint256 duration);

    /// @notice Emitted when a reward is added
    /// @param reward The amount of the reward
    event RewardAdded(uint256 reward);

    /// @notice Emitted when a reward is paid to a user
    /// @param user The user who received the reward
    /// @param reward The amount of the reward
    event RewardPaid(address indexed user, uint256 reward);

    /// @notice Emitted when a user enqueues an amount
    /// @param user The user who enqueued
    /// @param amount The amount enqueued
    event Enqueued(address indexed user, uint256 amount);

    /// @notice Emitted when an amount is earned
    /// @param user The user who earned the amount
    /// @param amount The amount earned
    event Earned(address indexed user, uint256 amount);

    /// @notice Emitted when a pair is sent to Valhalla
    /// @param token The token associated with the pair
    /// @param pair The pair sent to Valhalla
    event Valhalla(address indexed token, address indexed pair);

    /// @notice Emitted when Order 666 is executed for a pair
    /// @param token The token associated with the pair
    /// @param pair The pair on which Order 666 was executed
    event Order666(address indexed token, address indexed pair);

    /// @notice Emitted when a user is dequeued
    /// @param user The user who was dequeued
    /// @param amount The amount dequeued
    event Dequeued(address indexed user, uint256 amount);

    /// @notice Emitted when vault parameters are updated
    /// @param maxAPR The maximum APR
    /// @param minAPR The minimum APR
    /// @param fee The fee percentage
    /// @param duration The staking duration
    event ParamsUpdated(
        uint256 maxAPR,
        uint256 minAPR,
        uint256 fee,
        uint256 duration
    );

    /// @notice Emitted when the InterpolFactory is updated
    /// @param interpolFactory The new InterpolFactory value
    event InterpolFactorySet(address interpolFactory);

    /// @notice Emitted when an Interpol lock is created
    /// @param pair The pair address
    /// @param lock The lock address
    /// @param amount The amount locked
    event Locked(address indexed pair, address indexed lock, uint256 amount);

    /// @notice Emitted when the Chad Bar is updated
    /// @param bar The new Chad Bar value
    event ChadBarUpdated(uint256 bar);

    /// @notice Emitted when the Valhalla fee is updated
    /// @param fee The new Valhalla fee
    event ValhallaFeeUpdated(uint256 fee);

    /// @notice Constructor to initialize the MemeswapVault contract
    /// @dev The WETH token should be whitelisted on the MemeswapFactory
    /// @param _factory The address of the MemeswapFactory
    /// @param _weth The address of the WETH token
    constructor(
        address _factory,
        address _weth,
        address _interpolFactory
    ) Ownable(IMemeswapFactory(_factory).tokenFactory()) {
        weth = _weth;
        factory = _factory;
        interpolFactory = _interpolFactory;
        if (!IMemeswapFactory(factory).isWhitelisted(weth)) {
            revert NOT_WHITELISTED();
        }
        IERC20(weth).approve(address(this), type(uint256).max);
    }

    receive() external payable {}

    /// @dev Modifier to update the reward for a specified account
    /// @param _account The address of the account
    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (_account != address(0)) {
            rewards[_account] = earned(_account);
            userRewardPerToken[_account] = rewardPerTokenStored;
        }
        _;
    }

    /// @dev Modifier to trigger specific functions if certain conditions are met
    /// @param _pair The address of the pair
    modifier trigger(address _pair) {
        if (dequeuePossible()) {
            _dequeue();
        }
        if (_pair != address(0) && rents[_pair].user != address(0)) {
            _unlock(_pair);
        }
        _;
    }

    /// @notice Emergency function to dequeue specified number of items
    /// @dev This function is used to dequeue users in case of emergency
    /// @param _count The number of items to dequeue
    function emergencyDequeue(uint256 _count) external {
        for (uint256 i; i < _count; ++i) {
            if (dequeuePossible()) {
                _dequeue();
            }
        }
    }

    /// @notice Emergency function to unlock specified pairs
    /// @dev This function is used to unlock pairs in case of emergency
    /// @param _pair The array of pair addresses to unlock
    function emergencyUnlock(address[] calldata _pair) external {
        for (uint256 i; i < _pair.length; ++i) {
            if (_pair[i] != address(0) && rents[_pair[i]].user != address(0)) {
                _unlock(_pair[i]);
            }
        }
    }

    /// @notice Sets the vault parameters
    /// @param _maxAPR The maximum APR
    /// @param _minAPR The minimum APR
    /// @param _fee The fee percentage
    /// @param _duration Rewards duration
    function setParams(
        uint256 _maxAPR,
        uint256 _minAPR,
        uint256 _fee,
        uint256 _duration
    ) external {
        if (msg.sender != IMemeswapFactory(factory).owner()) revert FORBIDDEN();
        if (_maxAPR < _minAPR) revert OUT_OF_RANGE();
        if (_fee > PARAMS_SCALE) revert OUT_OF_RANGE();
        maxAPR = _maxAPR;
        minAPR = _minAPR;
        fee = _fee;
        duration = _duration;
        emit ParamsUpdated(_maxAPR, _minAPR, _fee, _duration);
    }

    function setInterpolFactory(address _interpolFactory) external {
        if (msg.sender != IMemeswapFactory(factory).owner()) revert FORBIDDEN();
        interpolFactory = _interpolFactory;
        emit InterpolFactorySet(_interpolFactory);
    }

    /// @notice Stakes ETH and updates user balance
    /// @param _pair The pair address
    function stake(
        address _pair
    ) public payable nonReentrant trigger(_pair) updateReward(msg.sender) {
        if (msg.value < minAmount) revert WRONG_AMOUNT();
        totalSupply += msg.value;
        balances[msg.sender] += msg.value;
        IWETH(weth).deposit{value: msg.value}();
        emit Staked(msg.sender, msg.value);
    }

    /// @notice Enqueues an amount of the user's balance for withdrawal
    /// @param _amount The amount to enqueue
    /// @param _pair The pair address
    function enqueue(
        uint256 _amount,
        address _pair
    ) external nonReentrant trigger(_pair) {
        if (_amount < minAmount) revert WRONG_AMOUNT();
        if (_amount > balances[msg.sender] - userTotalQueue[msg.sender]) {
            revert WRONG_AMOUNT();
        }
        queue[queueLast] = Queue(msg.sender, _amount);
        queueLast++;
        userTotalQueue[msg.sender] += _amount;
        totalInQueue += _amount;
        emit Enqueued(msg.sender, _amount);
    }

    /// @notice Rents an amount of liquidity for a specified duration
    /// @param _pair The pair address
    /// @param _token The token address
    /// @param _amount The amount to rent
    /// @param _duration The duration of the rental
    /// @param _user The user initiating the rent
    /// @param _pairToUnlock The pair to unlock
    function rent(
        address _pair,
        address _token,
        uint256 _amount,
        uint256 _duration,
        address _user,
        address _pairToUnlock
    ) external nonReentrant trigger(_pairToUnlock) onlyOwner {
        if (!IMemeswapTokenFactory(owner()).isMemeswapToken(_token)) {
            revert FORBIDDEN();
        }
        if (_amount == 0) revert ZERO_AMOUNT();
        if (!canRent(_amount)) revert VAULT_DRY();
        if (!IMemeswapTokenFactory(owner()).isAllowedDuration(_duration)) {
            revert WRONG_DURATION();
        }
        uint256 price = getPriceForAmount(_amount, _duration);
        uint256 cut = _takeCut(price);
        if (price - cut < duration) revert WRONG_AMOUNT();
        _notifyRewardAmount(price - cut);
        IERC20(weth).transferFrom(address(this), msg.sender, _amount);
        rents[_pair] = Rent(
            _user,
            _token,
            _amount,
            _duration,
            block.timestamp + _duration
        );
        rentedSupply += _amount;
        emit RentalCreated(_pair, _amount, _duration);
    }

    /// @notice Claims the user's accrued reward
    /// @param _pairToUnlock The pair to unlock
    function claim(
        address _pairToUnlock
    ) external nonReentrant trigger(_pairToUnlock) updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward == 0) revert WRONG_AMOUNT();
        rewards[msg.sender] = 0;
        IWETH(weth).withdraw(reward);
        (bool success, ) = msg.sender.call{value: reward}("");
        if (!success) revert TRANSACTION_FAILED();
        emit RewardPaid(msg.sender, reward);
    }

    /// @notice Claims a specific amount of the user's accrued reward
    /// @param _amount The amount to claim
    /// @param _pairToUnlock The pair to unlock
    function claim(
        uint256 _amount,
        address _pairToUnlock
    ) external nonReentrant trigger(_pairToUnlock) updateReward(msg.sender) {
        if (_amount == 0) revert ZERO_AMOUNT();
        uint256 reward = rewards[msg.sender];
        if (reward < _amount) revert WRONG_AMOUNT();
        rewards[msg.sender] -= _amount;
        IWETH(weth).withdraw(_amount);
        (bool success, ) = msg.sender.call{value: _amount}("");
        if (!success) revert TRANSACTION_FAILED();
        emit RewardPaid(msg.sender, _amount);
    }

    /// @notice Gets the total amount enqueued by a user
    /// @param _user The address of the user
    /// @return The total enqueued amount for the user
    function getUserTotalQueue(address _user) external view returns (uint256) {
        return userTotalQueue[_user];
    }

    /// @notice Gets the reward for the current duration
    /// @return The reward amount for the current duration
    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * duration;
    }

    /// @notice Gets the last time reward is applicable
    /// @return The last applicable timestamp for the reward
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /// @notice Gets the reward per token
    /// @return The reward amount per token
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            ((lastTimeRewardApplicable() - lastUpdateTime) *
                rewardRate *
                SCALE) /
            totalSupply;
    }

    /// @notice Gets the reward earned by an account
    /// @param _account The address of the account
    /// @return The earned reward amount for the account
    function earned(address _account) public view returns (uint256) {
        return
            ((balances[_account] *
                (rewardPerToken() - userRewardPerToken[_account])) / SCALE) +
            rewards[_account];
    }

    /// @notice Gets the yearly price based on the current parameters
    /// @return The yearly price for renting liquidity
    function getYearlyPrice() public view returns (uint256) {
        uint256 efficiency = (rentedSupply * PARAMS_SCALE) / totalSupply;
        return ((maxAPR - minAPR) * efficiency) / PARAMS_SCALE + minAPR;
    }

    /// @notice Gets the price for a specified amount of liquidity and duration
    /// @param _amount The amount of liquidity
    /// @param _duration The duration of the rental
    /// @return The price for the specified amount and duration
    function getPriceForAmount(
        uint256 _amount,
        uint256 _duration
    ) public view returns (uint256) {
        return
            (getYearlyPrice() * _amount * _duration) / 365 days / PARAMS_SCALE;
    }

    /// @notice Gets the amount of liquidity for a specified price and duration
    /// @param _price The price of the liquidity
    /// @param _duration The duration of the rental
    /// @return The amount of liquidity for the specified price and duration
    function getAmountForPrice(
        uint256 _price,
        uint256 _duration
    ) public view returns (uint256) {
        return
            (_price * 365 days * PARAMS_SCALE) / (_duration * getYearlyPrice());
    }

    /// @notice Determines if a dequeue is possible
    /// @return Boolean indicating if dequeue is possible
    function dequeuePossible() public view returns (bool) {
        return
            totalSupply - rentedSupply >= queue[queueFirst].amount &&
            (queueFirst != queueLast);
    }

    /// @notice Withdraws the user's dequeued amount
    /// @param amount The amount to withdraw
    function withdraw(uint256 amount) external nonReentrant {
        if (toWithdraw[msg.sender] < amount) revert WRONG_AMOUNT();
        toWithdraw[msg.sender] -= amount;
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert TRANSACTION_FAILED();
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Dequeues the first item in the queue
    function _dequeue() private updateReward(queue[queueFirst].user) {
        uint256 amount = queue[queueFirst].amount;
        address user = queue[queueFirst].user;
        IWETH(weth).withdraw(amount);
        toWithdraw[user] += amount;
        queueFirst++;
        userTotalQueue[user] -= amount;
        totalInQueue -= amount;
        totalSupply -= amount;
        balances[user] -= amount;
        emit Dequeued(user, amount);
    }

    /// @notice Takes a cut from the total price
    /// @param _price The total price
    /// @return cut amount
    function _takeCut(uint256 _price) private returns (uint256 cut) {
        cut = (_price * fee) / PARAMS_SCALE;
        IERC20(weth).transfer(IMemeswapFactory(factory).feeTo(), cut);
        emit Earned(IMemeswapFactory(factory).feeTo(), cut);
    }

    /// @notice Unlocks a pair if certain conditions are met
    /// @param _pair The pair address
    function _unlock(address _pair) private {
        if (rents[_pair].token != address(0)) {
            if (chad(_pair)) {
                _goToValhalla(_pair);
            } else if (rents[_pair].endDate < block.timestamp) {
                _executeOrder666(_pair);
            }
        }
    }

    /// @notice Sets the Chad Bar value
    /// @param _bar The new Chad Bar value
    function setChadBar(uint256 _bar) external {
        if (msg.sender != IMemeswapFactory(factory).owner()) revert FORBIDDEN();
        if (_bar >= PARAMS_SCALE || _bar < 2) revert OUT_OF_RANGE();
        chadBar = _bar;
        emit ChadBarUpdated(_bar);
    }

    /// @notice Determines if a pair qualifies as Chad
    /// @param _pair The pair address
    /// @return Boolean indicating if the pair is a Chad
    function chad(address _pair) public view returns (bool) {
        uint256 amount = rents[_pair].amount;
        bool tokenIsZero = IMemeswapPair(_pair).token0() != weth;
        (uint256 reserve0, uint256 reserve1, ) = IMemeswapPair(_pair)
            .getReserves();
        uint256 reserve = tokenIsZero ? reserve1 : reserve0;
        return reserve > amount * chadBar;
    }

    /// @notice Sends a pair to Valhalla if certain conditions are met
    /// @param _pair The pair address
    function valhalla(address _pair) external {
        if (msg.sender != factory) revert FORBIDDEN();
        if (rents[_pair].token != address(0) && chad(_pair)) {
            _goToValhalla(_pair);
        }
    }

    /// @notice Sets the Valhalla fee value
    /// @param _fee The new Valhalla fee value
    function setValhallaFee(uint256 _fee) external {
        if (msg.sender != IMemeswapFactory(factory).owner()) revert FORBIDDEN();
        if (_fee > 20) revert OUT_OF_RANGE();
        valhallaFee = _fee;
        emit ValhallaFeeUpdated(_fee);
    }

    /// @notice Sends a pair to Valhalla
    /// @dev Extracts liquidity for vault and collector
    /// @dev Distributes WETH to the collector and vault, ensuring vault gets rented amount back
    /// @dev Burns returned memeswap tokens
    /// @dev Sends remaining lp to zero address
    /// @param _pair The pair address
    function _goToValhalla(address _pair) private {
        uint256 amount = rents[_pair].amount;
        address lock = IMemeswapFactory(factory).lock();
        uint256 lp = IMemeswapLock(lock).unlock(_pair);
        uint256 lpToDissolve = _lpForAmount(_pair, amount);
        uint256 lpForCollector = ((lp - lpToDissolve) * valhallaFee) / 100;
        uint256 lpToBurn = lp - lpToDissolve - lpForCollector;
        IMemeswapPair(_pair).transfer(_pair, lpToDissolve + lpForCollector);
        (uint256 amount0, uint256 amount1) = IMemeswapPair(_pair).burn(
            address(this)
        );
        if (IMemeswapPair(_pair).token0() == weth) {
            uint256 wethFee = (amount0 - amount);
            IERC20(IMemeswapPair(_pair).token0()).transfer(
                IMemeswapFactory(factory).feeTo(),
                wethFee
            );
            IMemeswapToken(IMemeswapPair(_pair).token1()).burn(amount1);
            valhallaDate[IMemeswapPair(_pair).token1()] = block.timestamp;
        } else {
            uint256 wethFee = (amount1 - amount);
            IERC20(IMemeswapPair(_pair).token1()).transfer(
                IMemeswapFactory(factory).feeTo(),
                wethFee
            );
            IMemeswapToken(IMemeswapPair(_pair).token0()).burn(amount0);
            valhallaDate[IMemeswapPair(_pair).token0()] = block.timestamp;
        }
        emit Valhalla(rents[_pair].token, _pair);
        if (interpolFactory != address(0) && lpToBurn > 0) {
            _callInterpol(_pair, lpToBurn);
        } else {
            IMemeswapPair(_pair).transfer(address(0), lpToBurn);
        }
        rentedSupply -= amount;
        delete rents[_pair];
    }

    function _callInterpol(address _pair, uint256 _amount) private {
        try
            IInterpolFactory(interpolFactory).createLocker(
                address(this),
                IMemeswapFactory(factory).feeTo(),
                false
            )
        returns (address payable lock) {
            IMemeswapPair(_pair).approve(lock, _amount);
            IInterpolLock(lock).depositAndLock(
                _pair,
                _amount,
                type(uint256).max
            );
            IInterpolLock(lock).transferOwnership(
                IMemeswapFactory(factory).owner()
            );
            interpolLocks[_pair] = lock;
            emit Locked(_pair, lock, _amount);
        } catch {
            IMemeswapPair(_pair).transfer(address(0), _amount);
        }
    }

    /// @notice Gets the LP tokens for a specified amount
    /// @param _pair The pair address
    /// @param _amount The amount of liquidity
    /// @return The amount of LP tokens for the specified liquidity
    function _lpForAmount(
        address _pair,
        uint256 _amount
    ) private view returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) = IMemeswapPair(_pair)
            .getReserves();
        bool tokenIsZero = IMemeswapPair(_pair).token0() != weth;
        uint256 lpSupply = IMemeswapPair(_pair).totalSupply();
        uint256 reserve = tokenIsZero ? reserve1 : reserve0;
        return (_amount * lpSupply) / reserve; // +1?
    }

    /// @notice Executes Order 666 on a pair
    /// @dev Extracts liquidity and announces the rest as reward
    /// @param _pair The pair address
    function _executeOrder666(address _pair) private {
        uint256 amount = rents[_pair].amount;
        address lock = IMemeswapFactory(factory).lock();
        uint256 lp = IMemeswapLock(lock).unlock(_pair);
        IMemeswapPair(_pair).transfer(_pair, lp);
        (uint256 amount0, uint256 amount1) = IMemeswapPair(_pair).burn(
            address(this)
        );
        if (IMemeswapPair(_pair).token0() == weth) {
            IMemeswapToken(IMemeswapPair(_pair).token1()).burn(amount1);
            if (amount0 > amount) {
                _notifyRewardAmount(amount0 - amount);
            }
        } else {
            IMemeswapToken(IMemeswapPair(_pair).token0()).burn(amount0);
            if (amount1 > amount) {
                _notifyRewardAmount(amount1 - amount);
            }
        }
        rentedSupply -= amount;
        emit Order666(rents[_pair].token, _pair);
        delete rents[_pair];
    }

    /// @notice Notifies about a reward amount update
    /// @param _reward The reward amount
    function _notifyRewardAmount(
        uint256 _reward
    ) private updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = _reward / duration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (_reward + leftover) / duration;
        }
        rewardAmount += _reward;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;
        emit RewardAdded(_reward);
    }

    /// @notice Determines if a specified amount can be rented
    /// @param _amount The amount to rent
    /// @return Boolean indicating if the amount can be rented
    function canRent(uint256 _amount) public view returns (bool) {
        return totalSupply - rentedSupply - totalInQueue >= _amount;
    }

    /// @notice Gets the maximum amount of liquidity rentable
    /// @return The maximum amount of liquidity rentable
    function getMaxRentable() public view returns (uint256) {
        return totalSupply - rentedSupply - totalInQueue;
    }

    function renounceOwnership() public view override onlyOwner {
        revert NOT_ALLOWED();
    }
}
