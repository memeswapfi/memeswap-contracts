// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {MemeswapPair} from "./MemeswapPair.sol";
import {MemeswapLock} from "./MemeswapLock.sol";
import {IMemeswapLock} from "./interfaces/IMemeswapLock.sol";
import {IMemeswapToken} from "./interfaces/IMemeswapToken.sol";
import {IMemeswapTokenFactory} from "./interfaces/IMemeswapTokenFactory.sol";
import {IMemeswapVault} from "./interfaces/IMemeswapVault.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IWETH} from "./interfaces/IWETH.sol";

/// @title MemeswapFactory
/// @author Memeswap
/// @notice MemeswapPair factory based on UniswapV2Factory.
contract MemeswapFactory is Ownable {
    address public feeTo;
    address[] public allPairs;
    bool private initialized;
    mapping(address => mapping(address => address)) public getPair;
    mapping(address => bool) public isPair;
    mapping(address => bool) public isWhitelisted;
    IMemeswapLock public immutable lock;
    IMemeswapTokenFactory public tokenFactory;
    uint256 public serviceFee;
    uint256 private constant maxFee = 0.1 ether;

    /// @notice Event emitted when a new pair is created.
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    /// @notice Event emitted when a token is whitelisted.
    event Whitelisted(address indexed token);

    /// @notice Event emitted when a token is unwhitelisted.
    event Unwhitelisted(address indexed token);

    error INITIALIZED();
    error NOT_INITIALIZED();
    error PAIR_EXISTS();
    error IDENTICAL();
    error ZERO_ADDRESS();
    error NOT_WHITELISTED();
    error ALREADY_WHITELISTED();
    error NOT_MEMESWAP_PAIR();
    error FEE_TOO_HIGH();
    error NOT_ALLOWED();

    /// @notice Constructor to initialize the factory.
    /// @dev Deploys a new MemeswapLock contract.
    /// @param _collector Address to collect the fees.
    /// @param _fee Initial service fee.
    constructor(address _collector, uint256 _fee) Ownable(msg.sender) {
        feeTo = _collector;
        serviceFee = _fee;
        MemeswapLock lock_contract = new MemeswapLock();
        lock = IMemeswapLock(address(lock_contract));
    }

    /// @notice Initialize the factory with a token factory address and a WETH address.
    /// @param _tokenFactory Address of the token factory.
    /// @param _weth Address of the WETH token.
    function initialize(address _tokenFactory, address _weth) external onlyOwner {
        if (initialized) revert INITIALIZED();
        tokenFactory = IMemeswapTokenFactory(_tokenFactory);
        isWhitelisted[_weth] = true;
        emit Whitelisted(_weth);
        initialized = true;
    }

    /// @notice Set the fee collection address.
    /// @param _feeTo Address to collect the fees.
    function setFeeTo(address _feeTo) external onlyOwner {
        feeTo = _feeTo;
    }

    /// @notice Set the service fee.
    /// @param _fee Service fee to be set.
    function setServiceFee(uint256 _fee) external onlyOwner {
        if (_fee > maxFee) revert FEE_TOO_HIGH();
        serviceFee = _fee;
    }

    /// @notice Add a token to the whitelist.
    /// @param _token Address of the token to be whitelisted.
    function addWhitelisted(address _token) external onlyOwner {
        if (isWhitelisted[_token]) revert ALREADY_WHITELISTED();
        isWhitelisted[_token] = true;
        emit Whitelisted(_token);
    }

    /// @notice Remove a token from the whitelist.
    /// @param _token Address of the token to be unwhitelisted.
    function removeWhitelisted(address _token) external onlyOwner {
        if (!isWhitelisted[_token]) revert NOT_WHITELISTED();
        isWhitelisted[_token] = false;
        emit Unwhitelisted(_token);
    }

    /// @notice Create a pair of tokens.
    /// @dev One of the tokens must be whitelisted.
    /// @param _tokenA Address of the first token.
    /// @param _tokenB Address of the second token.
    /// @return _pair Address of the created pair.
    function createPair(address _tokenA, address _tokenB) external returns (address _pair) {
        if (!initialized) revert NOT_INITIALIZED();
        if (_tokenA == _tokenB) revert IDENTICAL();
        if (!isWhitelisted[_tokenA] && !isWhitelisted[_tokenB]) {
            revert NOT_WHITELISTED();
        }
        (address token0, address token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
        if (token0 == address(0) || token1 == address(0)) revert ZERO_ADDRESS();
        if (getPair[token0][token1] != address(0)) revert PAIR_EXISTS();
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        _pair = address(new MemeswapPair{salt: salt}());
        MemeswapPair(_pair).initialize(token0, token1);
        getPair[token0][token1] = _pair;
        getPair[token1][token0] = _pair;
        isPair[_pair] = true;
        allPairs.push(_pair);
        emit PairCreated(token0, token1, _pair, allPairs.length);
    }

    /// @notice Attempt to call valhalla on the vault.
    /// @dev Only Memeswap pairs can call this function.
    function tryValhalla() external {
        if (!isPair[msg.sender]) revert NOT_MEMESWAP_PAIR();
        address vault = IMemeswapTokenFactory(tokenFactory).vault();
        IMemeswapVault(vault).valhalla(msg.sender);
    }

    /// @notice Get the total number of pairs created.
    /// @return Number of pairs created.
    function allPairsLength() public view returns (uint256) {
        return allPairs.length;
    }

    function renounceOwnership() public view override onlyOwner {
        revert NOT_ALLOWED();
    }
}
