// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {MemeswapFarmToken} from "./MemeswapFarmToken.sol";
import {IMemeswapFactory} from "./interfaces/IMemeswapFactory.sol";
import {IMemeswapTokenFactory} from "./interfaces/IMemeswapTokenFactory.sol";
import {IMemeswapPair} from "./interfaces/IMemeswapPair.sol";
import {IMemeswapFarmFactory} from "./interfaces/IMemeswapFarmFactory.sol";
import {IMemeswapVault} from "./interfaces/IMemeswapVault.sol";
import {FixedPoint} from "./libraries/FixedPoint.sol";
import {MemeswapOracleLibrary} from "./libraries/MemeswapOracleLibrary.sol";

contract MemeswapFarm is ReentrancyGuard, Ownable {
    using FixedPoint for *;

    uint256 public buffer;
    uint256 public constant SCALE = 1e18;
    uint256 public duration;
    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public rewardAmount;
    uint256 public totalSupply;
    address[] public allPairs;
    address public immutable rewardToken;
    address public immutable farmToken;
    IMemeswapVault public immutable vault;
    IMemeswapFactory public immutable factory;
    IMemeswapTokenFactory public immutable tokenFactory;
    IMemeswapFarmFactory public immutable farmFactory;
    mapping(address => uint256) userRewardPerToken;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public balances;
    mapping(address user => mapping(address token => uint256)) public stakedTokens;
    mapping(address => Price) public prices;
    mapping(address => uint256) public stakeDates;
    mapping(address => PairInfo) public pairInfos;

    struct Price {
        uint256 price0CumulativeLast;
        uint256 price1CumulativeLast;
        uint32 blockTimestampLast;
        FixedPoint.uq112x112 price0Average;
        FixedPoint.uq112x112 price1Average;
    }

    struct PairInfo {
        address token;
        bool tokenIsZero;
    }

    error ZERO_AMOUNT();
    error FORBIDDEN();
    error NOT_STAKABLE();
    error NOT_PAIR();
    error NOT_MEMESWAP_TOKEN();
    error ALREADY_ADDED();
    error WRONG_LENGTH();
    error NOT_ALLOWED();

    event Staked(address indexed user, address indexed token, uint256 amount, uint256 value);
    event Exit(address indexed user, uint256 value);
    event Removed(address indexed user, address indexed token, uint256 amount);
    event PairAdded(address indexed pair, address indexed token);
    event RewardAdded(uint256 reward);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(address _rewardToken, address _factory, address[] memory _pairs, uint256 _duration)
        Ownable(msg.sender)
    {
        duration = _duration;
        rewardToken = _rewardToken;
        factory = IMemeswapFactory(_factory);
        tokenFactory = IMemeswapTokenFactory(factory.tokenFactory());
        vault = IMemeswapVault(tokenFactory.vault());
        farmToken = address(new MemeswapFarmToken());
        farmFactory = IMemeswapFarmFactory(msg.sender);
        buffer = farmFactory.buffer();
        for (uint256 i; i < _pairs.length; ++i) {
            _addPair(_pairs[i]);
        }
    }

    /// @dev Modifier to update the reward for a specified account
    /// @param _account The address of the account
    modifier updateReward(address _account) {
        _updateReward(_account);
        _;
    }

    modifier observe(address _pair) {
        _observe(_pair);
        _;
    }

    function stake(address[] memory _pairs, uint256[] memory _amounts) public {
        if (_pairs.length != _amounts.length) revert WRONG_LENGTH();
        for (uint256 i; i < _pairs.length; ++i) {
            stake(_pairs[i], _amounts[i]);
        }
    }

    function stake(address _pair, uint256 _amount) public nonReentrant updateReward(msg.sender) observe(_pair) {
        PairInfo memory p = pairInfos[_pair];
        if (stakeDates[p.token] > block.timestamp) revert NOT_STAKABLE();
        uint256 value = consult(_pair, _amount);
        if (value == 0) revert ZERO_AMOUNT();
        totalSupply += value;
        balances[msg.sender] += value;
        stakedTokens[msg.sender][p.token] += _amount;
        IERC20(p.token).transferFrom(msg.sender, address(this), _amount);
        MemeswapFarmToken(farmToken).mint(msg.sender, value);
        emit Staked(msg.sender, p.token, _amount, value);
    }

    /// @notice Claims the user's accrued reward
    function claim() external nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward == 0) revert ZERO_AMOUNT();
        rewards[msg.sender] = 0;
        IERC20(rewardToken).transfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward);
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
        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * SCALE) / totalSupply;
    }

    /// @notice Gets the reward earned by an account
    /// @param _account The address of the account
    /// @return The earned reward amount for the account
    function earned(address _account) public view returns (uint256) {
        return ((balances[_account] * (rewardPerToken() - userRewardPerToken[_account])) / SCALE) + rewards[_account];
    }

    function exit() external nonReentrant updateReward(msg.sender) {
        uint256 balance = balances[msg.sender];
        if (balance == 0) revert ZERO_AMOUNT();
        totalSupply -= balance;
        balances[msg.sender] = 0;
        _removeTokens();
        MemeswapFarmToken(farmToken).burn(msg.sender, balance);
        emit Exit(msg.sender, balance);
    }

    /// @notice Notifies about a reward amount update
    /// @param _reward The reward amount
    function notifyRewardAmount(uint256 _reward) public updateReward(address(0)) onlyOwner {
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

    function _observe(address _pair) private {
        IMemeswapPair pair = IMemeswapPair(_pair);
        address token = pairInfos[_pair].token;
        Price storage price = prices[token];
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
            MemeswapOracleLibrary.currentCumulativePrices(address(pair));
        uint32 elapsed = blockTimestamp - price.blockTimestampLast;
        if (elapsed >= buffer) {
            price.price0Average =
                FixedPoint.uq112x112(uint224((price0Cumulative - price.price0CumulativeLast) / elapsed));
            price.price1Average =
                FixedPoint.uq112x112(uint224((price1Cumulative - price.price1CumulativeLast) / elapsed));
            price.price0CumulativeLast = price0Cumulative;
            price.price1CumulativeLast = price1Cumulative;
            price.blockTimestampLast = blockTimestamp;
        }
    }

    function _updateReward(address _account) private {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (_account != address(0)) {
            rewards[_account] = earned(_account);
            userRewardPerToken[_account] = rewardPerTokenStored;
        }
    }

    function _addPair(address _pair) private {
        if (!factory.isPair(_pair)) revert NOT_PAIR();
        if (pairInfos[_pair].token != address(0)) revert ALREADY_ADDED();
        (address token, bool tokenIsZero) = _getTokenForPair(_pair);
        if (farmFactory.needValhalla()) {
            uint256 vDate = vault.valhallaDate(token);
            if (vDate == 0) {
                if (!farmFactory.isPartnerToken(_pair, token)) {
                    revert FORBIDDEN();
                }
            }
        }
        PairInfo memory p = PairInfo(token, tokenIsZero);
        allPairs.push(_pair);
        pairInfos[_pair] = p;
        stakeDates[token] = block.timestamp + buffer;
        (,, uint32 timestamp) = IMemeswapPair(_pair).getReserves();
        prices[p.token] = Price(
            IMemeswapPair(_pair).price0CumulativeLast(),
            IMemeswapPair(_pair).price1CumulativeLast(),
            timestamp,
            FixedPoint.uq112x112(0),
            FixedPoint.uq112x112(0)
        );
        emit PairAdded(_pair, token);
    }

    function consult(address _pair, uint256 _amount) public view returns (uint256) {
        PairInfo memory p = pairInfos[_pair];
        Price memory price = prices[p.token];
        if (p.tokenIsZero) {
            return price.price0Average.mul(_amount).decode144();
        } else {
            return price.price1Average.mul(_amount).decode144();
        }
    }

    function _getTokenForPair(address _pair) private view returns (address, bool) {
        IMemeswapPair pair = IMemeswapPair(_pair);
        if (tokenFactory.isMemeswapToken(pair.token0()) || farmFactory.isPartnerToken(_pair, pair.token0())) {
            return (pair.token0(), true);
        } else if (tokenFactory.isMemeswapToken(pair.token1()) || farmFactory.isPartnerToken(_pair, pair.token1())) {
            return (pair.token1(), false);
        }
        revert NOT_MEMESWAP_TOKEN();
    }

    function _removeTokens() private {
        for (uint256 i; i < allPairs.length; ++i) {
            _removeToken(pairInfos[allPairs[i]].token);
        }
    }

    function _removeToken(address _token) private {
        uint256 amount = stakedTokens[msg.sender][_token];
        stakedTokens[msg.sender][_token] = 0;
        if (amount > 0) IERC20(_token).transfer(msg.sender, amount);
        emit Removed(msg.sender, _token, amount);
    }

    function renounceOwnership() public view override onlyOwner {
        revert NOT_ALLOWED();
    }
}
