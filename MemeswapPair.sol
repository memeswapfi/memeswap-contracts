// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MemeswapPairBase} from "./MemeswapPairBase.sol";
import {Math} from "./libraries/Math.sol";
import {UQ112x112} from "./libraries/UQ112x112.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IMemeswapFactory} from "./interfaces/IMemeswapFactory.sol";
import {IMemeswapTokenFactory} from "./interfaces/IMemeswapTokenFactory.sol";
import {IMemeswapToken} from "./interfaces/IMemeswapToken.sol";
import {IMemeswapVault} from "./interfaces/IMemeswapVault.sol";

/// @title MemeswapPair
/// @author Memeswap
/// @notice MemeswapPair based on UniswapV2Pair.
contract MemeswapPair is MemeswapPairBase {
    using UQ112x112 for uint224;

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));
    address public immutable factory;
    address public token0;
    address public token1;
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 private locked = 0;
    uint256 private kLast;

    /// @notice Emitted when liquidity is minted.
    /// @param sender Address that minted the liquidity.
    /// @param amount0 Amount of token0 minted.
    /// @param amount1 Amount of token1 minted.
    /// @param to Address where liquidity is sent.
    event Mint(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);

    /// @notice Emitted when liquidity is burned.
    /// @param sender Address that burned the liquidity.
    /// @param amount0 Amount of token0 burned.
    /// @param amount1 Amount of token1 burned.
    /// @param to Address where burned amounts are sent.
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);

    /// @notice Emitted when a swap occurs.
    /// @param sender Address that initiated the swap.
    /// @param amount0In Amount of token0 sent in.
    /// @param amount1In Amount of token1 sent in.
    /// @param amount0Out Amount of token0 sent out.
    /// @param amount1Out Amount of token1 sent out.
    /// @param to Address where output tokens are sent.
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    // @notice Emitted when a referral is made.
    // @param Referral code.
    event Referral(bytes indexed data, uint256 amount);

    /// @notice Emitted when the reserves are synchronized.
    /// @param reserve0 New reserve of token0.
    /// @param reserve1 New reserve of token1.
    event Sync(uint112 reserve0, uint112 reserve1);

    error OVERFLOW();
    error TRANSFER_FAILED();
    error INSUFFICIENT_LIQUIDITY();
    error INSUFFICIENT_OUTPUT_AMOUNT();
    error INSUFFICIENT_INPUT_AMOUNT();
    error K();
    error LOCKED();
    error FORBIDDEN();

    /// @notice Initializes the pair with the MemeswapFactory.
    /// @dev The MemeswapFactory is set as the deployer of the pair.
    /// @dev The MemeswapLock is set to the lock of the MemeswapFactory.
    /// @dev The pair is approved to spend an infinite amount of tokens.
    constructor() {
        factory = msg.sender;
    }

    /// @dev Throws if the pair is locked.
    modifier lock() {
        if (locked != 0) revert LOCKED();
        locked = 1;
        _;
        locked = 0;
    }

    /// @dev Triggers valhalla if possible.
    modifier valhalla() {
        _;
        IMemeswapFactory(factory).tryValhalla();
    }

    /// @notice Initializes the pair with token0 and token1.
    /// @param _token0 Address of the first token.
    /// @param _token1 Address of the second token.
    function initialize(address _token0, address _token1) external {
        if (msg.sender != factory) revert FORBIDDEN();
        token0 = _token0;
        token1 = _token1;
    }

    /// @notice Mints liquidity to the specified address.
    /// @dev Forbidden during challenge for Memeswap tokens.
    /// @param _to Address where the liquidity tokens are sent.
    /// @return liquidity Amount of liquidity minted.
    function mint(address _to) external lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;
        _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(IMemeswapFactory(factory).feeTo(), MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min((amount0 * _totalSupply) / _reserve0, (amount1 * _totalSupply) / _reserve1);
        }
        if (liquidity == 0) revert INSUFFICIENT_LIQUIDITY();
        bool token0isMeme = _isMemeToken(token0);
        bool token1isMeme = _isMemeToken(token1);
        if (token0isMeme || token1isMeme) {
            IMemeswapTokenFactory tokenFactory = IMemeswapTokenFactory(IMemeswapFactory(factory).tokenFactory());
            IMemeswapVault vault = IMemeswapVault(tokenFactory.vault());
            if (vault.rents(address(this)).token != address(0) && _to != address(tokenFactory)) revert FORBIDDEN();
        }
        _mint(_to, liquidity);
        _update(balance0, balance1, _reserve0, _reserve1);
        kLast = uint256(reserve0) * reserve1;
        emit Mint(msg.sender, amount0, amount1, _to);
    }

    /// @notice Burns liquidity tokens and sends the underlying assets to the specified address.
    /// @param _to Address where the underlying assets are sent.
    /// @return amount0 Amount of token0 received.
    /// @return amount1 Amount of token1 received.
    function burn(address _to) public lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        address _token0 = token0;
        address _token1 = token1;
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];
        _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply;
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        if (amount0 == 0 || amount1 == 0) revert INSUFFICIENT_LIQUIDITY();
        _burn(address(this), liquidity);
        _safeTransfer(_token0, _to, amount0);
        _safeTransfer(_token1, _to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        _update(balance0, balance1, _reserve0, _reserve1);
        kLast = uint256(reserve0) * reserve1;
        emit Burn(msg.sender, amount0, amount1, _to);
    }

    /// @notice Swaps tokens.
    /// @param _amount0Out Amount of token0 to be sent out.
    /// @param _amount1Out Amount of token1 to be sent out.
    /// @param _to Address where swapped tokens are sent.
    /// @param _data Arbitrary data to be passed to the onSwap callback.
    function swap(uint256 _amount0Out, uint256 _amount1Out, address _to, bytes calldata _data) external valhalla lock {
        if (_amount0Out == 0 && _amount1Out == 0) {
            revert INSUFFICIENT_OUTPUT_AMOUNT();
        }
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        if (_amount0Out > _reserve0 || _amount1Out > _reserve1) {
            revert INSUFFICIENT_LIQUIDITY();
        }
        uint256 balance0;
        uint256 balance1;
        {
            address _token0 = token0;
            address _token1 = token1;
            if (_amount0Out > 0) _safeTransfer(_token0, _to, _amount0Out);
            if (_amount1Out > 0) _safeTransfer(_token1, _to, _amount1Out);
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - _amount0Out ? balance0 - (_reserve0 - _amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - _amount1Out ? balance1 - (_reserve1 - _amount1Out) : 0;
        if (amount0In == 0 && amount1In == 0) {
            revert INSUFFICIENT_INPUT_AMOUNT();
        }
        {
            uint256 fee = getFee();
            uint256 balance0_ = balance0 * 1000 - amount0In * fee;
            uint256 balance1_ = balance1 * 1000 - amount1In * fee;
            if (balance0_ * balance1_ < uint256(_reserve0) * _reserve1 * 1000 ** 2) revert K();
        }
        if (_isRental()) {
            if (_amount0Out > 0 && _isMemeToken(token1)) {
                _safeTransfer(token0, IMemeswapFactory(factory).feeTo(), _amount0Out / 100);
                balance0 -= _amount0Out / 100;
                if (_data.length > 0) emit Referral(_data, _amount0Out / 100);
            } else if (_amount0Out > 0 && _isMemeToken(token0)) {
                _safeTransfer(token1, IMemeswapFactory(factory).feeTo(), amount1In / 100);
                balance1 -= amount1In / 100;
                if (_data.length > 0) emit Referral(_data, amount1In / 100);
            } else if (_amount1Out > 0 && _isMemeToken(token1)) {
                _safeTransfer(token0, IMemeswapFactory(factory).feeTo(), amount0In / 100);
                balance0 -= amount0In / 100;
                if (_data.length > 0) emit Referral(_data, amount0In / 100);
            } else if (_amount1Out > 0 && _isMemeToken(token0)) {
                _safeTransfer(token1, IMemeswapFactory(factory).feeTo(), _amount1Out / 100);
                balance1 -= _amount1Out / 100;
                if (_data.length > 0) emit Referral(_data, _amount1Out / 100);
            }
        }
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, _amount0Out, _amount1Out, _to);
    }

    function getFee() public view returns (uint256) {
        return _isRental() ? 10 : 3;
    }

    function _isRental() private view returns (bool) {
        IMemeswapTokenFactory tokenFactory = IMemeswapTokenFactory(IMemeswapFactory(factory).tokenFactory());
        IMemeswapVault vault = IMemeswapVault(tokenFactory.vault());
        return vault.rents(address(this)).token != address(0);
    }

    /// @notice Skims the tokens and sends them to the specified address.
    /// @param _to Address where skimmed tokens are sent.
    function skim(address _to) external lock {
        address _token0 = token0;
        address _token1 = token1;
        _safeTransfer(_token0, _to, IERC20(_token0).balanceOf(address(this)) - reserve0);
        _safeTransfer(_token1, _to, IERC20(_token1).balanceOf(address(this)) - reserve1);
    }

    /// @notice Synchronizes the reserves with the actual token balances.
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }

    /// @notice Transfers tokens safely to a specified address.
    /// @param _token Address of the token to be transferred.
    /// @param _to Address where the tokens are sent.
    /// @param _value Amount of tokens to be transferred.
    function _safeTransfer(address _token, address _to, uint256 _value) private {
        (bool success, bytes memory data) = _token.call(abi.encodeWithSelector(SELECTOR, _to, _value));
        if (!success || (data.length > 0 && abi.decode(data, (bool)) == false)) {
            revert TRANSFER_FAILED();
        }
    }

    /// @notice Updates the reserves with new balances.
    /// @param _balance0 New balance of token0.
    /// @param _balance1 New balance of token1.
    /// @param _reserve0 Current reserve of token0.
    /// @param _reserve1 Current reserve of token1.
    function _update(uint256 _balance0, uint256 _balance1, uint112 _reserve0, uint112 _reserve1) private {
        if (_balance0 > type(uint112).max || _balance1 > type(uint112).max) {
            revert OVERFLOW();
        }
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            price0CumulativeLast += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(_balance0);
        reserve1 = uint112(_balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    /// @notice Mints fees based on the current reserves and kLast.
    /// @param _reserve0 Current reserve of token0.
    /// @param _reserve1 Current reserve of token1.
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private {
        uint256 _kLast = kLast;
        if (_kLast != 0) {
            uint256 rootK = Math.sqrt(uint256(_reserve0) * _reserve1);
            uint256 rootKLast = Math.sqrt(_kLast);
            if (rootK > rootKLast) {
                uint256 numerator = totalSupply * (rootK - rootKLast);
                uint256 denominator = rootK * (5) + rootKLast;
                uint256 liquidity = numerator / denominator;
                if (liquidity > 0) {
                    _mint(IMemeswapFactory(factory).feeTo(), liquidity);
                }
            }
        }
    }

    function collectFees() external {
        if (msg.sender != IMemeswapFactory(factory).feeTo()) revert FORBIDDEN();
        _mintFee(reserve0, reserve1);
    }

    function getFees() external view returns (uint256) {
        uint256 _kLast = kLast;
        if (_kLast != 0) {
            uint256 rootK = Math.sqrt(uint256(reserve0) * reserve1);
            uint256 rootKLast = Math.sqrt(_kLast);
            if (rootK > rootKLast) {
                bool isMeme = _isMemeToken(token0) || _isMemeToken(token1);
                uint256 numerator = totalSupply * (rootK - rootKLast);
                uint256 denominator = isMeme ? rootK + rootKLast : rootK * (5) + rootKLast;
                uint256 liquidity = numerator / denominator;
                if (liquidity > 0) {
                    return liquidity;
                }
            }
        }
        return 0;
    }

    /// @notice Returns the current reserves.
    /// @return _reserve0 Current reserve of token0.
    /// @return _reserve1 Current reserve of token1.
    /// @return _blockTimestampLast Last block timestamp of the sync.
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /// @notice Checks if a token is a MemeToken.
    /// @param _token Address of the token.
    /// @return True if the token is a MemeToken, else false.
    function _isMemeToken(address _token) private view returns (bool) {
        return IMemeswapTokenFactory(IMemeswapFactory(factory).tokenFactory()).isMemeswapToken(_token);
    }
}
