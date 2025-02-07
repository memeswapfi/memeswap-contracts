// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MemeswapFarm} from "./MemeswapFarm.sol";
import {IMemeswapTokenFactory} from "./interfaces/IMemeswapTokenFactory.sol";
import {IMemeswapToken} from "./interfaces/IMemeswapToken.sol";
import {IMemeswapFactory} from "./interfaces/IMemeswapFactory.sol";
import {IMemeswapVault} from "./interfaces/IMemeswapVault.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract MemeswapFarmFactory is Ownable {
    struct Partner {
        address pair;
        address token;
    }

    uint256 public maxPairs = 3;
    uint256 public buffer = 30 minutes;
    bool public needValhalla = true;
    uint256 public constant MAX_DURATION = 90 days;
    uint256 public constant MIN_DURATION = 1 days;
    uint256 public constant MIN_BUFFER = 30 minutes;

    IMemeswapTokenFactory public tokenFactory;
    IMemeswapVault public vault;
    address public factory;
    mapping(address => bool) public isMemeswapFarm;
    mapping(address => Partner) public partners;

    event FarmCreated(
        address indexed farm,
        address indexed token,
        uint256 amount,
        uint256 duration
    );
    event PartnerAdded(address indexed pair, address indexed token);

    error NOT_MEMESWAP_TOKEN();
    error VALHALLA_NOT_REACHED();
    error TOO_MANY_PAIRS();
    error NOT_OWNER();
    error INVALID_DURATION();
    error ZERO_AMOUNT();
    error NOT_ALLOWED();
    error OUT_OF_BOUNDS();

    constructor(address _factory) Ownable(msg.sender) {
        factory = _factory;
        tokenFactory = IMemeswapTokenFactory(
            IMemeswapFactory(_factory).tokenFactory()
        );
        vault = IMemeswapVault(tokenFactory.vault());
    }

    function setBuffer(uint256 _buffer) external onlyOwner {
        if (_buffer < MIN_BUFFER) revert OUT_OF_BOUNDS();
        buffer = _buffer;
    }

    function setMaxPairs(uint256 _maxPairs) external onlyOwner {
        maxPairs = _maxPairs;
    }

    function setNeedValhalla(bool _needValhalla) external onlyOwner {
        needValhalla = _needValhalla;
    }

    function addPartnerPair(address _pair, address _token) external onlyOwner {
        partners[_pair] = Partner(_pair, _token);
    }

    function removePartnerPair(address _pair) external onlyOwner {
        delete partners[_pair];
    }

    function getPartnerToken(address _pair) public view returns (address) {
        return partners[_pair].token;
    }

    function isPartnerToken(
        address _pair,
        address _token
    ) public view returns (bool) {
        return partners[_pair].token == _token;
    }

    function deployFarm(
        address _token,
        address[] memory _pairs,
        uint256 _amount,
        uint256 _duration
    ) public returns (address) {
        if (_amount == 0) revert ZERO_AMOUNT();
        if (!tokenFactory.isMemeswapToken(_token)) revert NOT_MEMESWAP_TOKEN();
        if (needValhalla && vault.valhallaDate(_token) == 0) {
            revert VALHALLA_NOT_REACHED();
        }
        if (_pairs.length > maxPairs) revert TOO_MANY_PAIRS();
        if (IMemeswapToken(_token).owner() != msg.sender) revert NOT_OWNER();
        if (_duration < MIN_DURATION || _duration > MAX_DURATION) {
            revert INVALID_DURATION();
        }
        MemeswapFarm farm = new MemeswapFarm(
            _token,
            factory,
            _pairs,
            _duration
        );
        IERC20(_token).transferFrom(msg.sender, address(farm), _amount);
        MemeswapFarm(address(farm)).notifyRewardAmount(_amount);
        isMemeswapFarm[address(farm)] = true;
        emit FarmCreated(address(farm), _token, _amount, _duration);
        return address(farm);
    }

    function renounceOwnership() public view override onlyOwner {
        revert NOT_ALLOWED();
    }
}
