// SPDX-License-Identifier: MITrouter
pragma solidity ^0.8.24;

import {MemeswapLibrary} from "./libraries/MemeswapLibrary.sol";
import {IMemeswapPair} from "./interfaces/IMemeswapPair.sol";
import {IMemeswapFactory} from "./interfaces/IMemeswapFactory.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IWETH} from "./interfaces/IWETH.sol";

/// @title MemeswapRouter
/// @notice This contract is a periphery contract for safely interacting with MemeswapPair contracts.
contract MemeswapRouter {
    address public immutable factory;
    address public immutable WETH;

    error EXPIRED();
    error INSUFFICIENT_A_AMOUNT();
    error INSUFFICIENT_B_AMOUNT();
    error INSUFFICIENT_OUTPUT_AMOUNT();
    error EXCESSIVE_INPUT_AMOUNT();
    error INVALID_PATH();

    /// @notice Initializes the router with the factory and WETH addresses.
    /// @param _factory The address of the MemeswapFactory contract.
    /// @param _WETH The address of the WETH token contract.
    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH);
    }

    /// @dev Ensures that the deadline has not passed.
    /// @param _deadline The timestamp by which the function must be called.
    modifier ensure(uint256 _deadline) {
        if (_deadline < block.timestamp) revert EXPIRED();
        _;
    }

    /// @notice Adds liquidity to a Memeswap pair.
    /// @param _tokenA The address of token A.
    /// @param _tokenB The address of token B.
    /// @param _amountADesired The desired amount of token A.
    /// @param _amountBDesired The desired amount of token B.
    /// @param _amountAMin The minimum amount of token A.
    /// @param _amountBMin The minimum amount of token B.
    /// @param _to The address to receive the liquidity tokens.
    /// @param _deadline The deadline by which the addLiquidity must be completed.
    /// @return amountA The actual amount of token A added.
    /// @return amountB The actual amount of token B added.
    /// @return liquidity The liquidity tokens minted.
    function addLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _amountADesired,
        uint256 _amountBDesired,
        uint256 _amountAMin,
        uint256 _amountBMin,
        address _to,
        uint256 _deadline
    ) public ensure(_deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(_tokenA, _tokenB, _amountADesired, _amountBDesired, _amountAMin, _amountBMin);
        address pair = MemeswapLibrary.pairFor(factory, _tokenA, _tokenB);
        MemeswapLibrary.safeTransferFrom(_tokenA, msg.sender, pair, amountA);
        MemeswapLibrary.safeTransferFrom(_tokenB, msg.sender, pair, amountB);
        liquidity = IMemeswapPair(pair).mint(_to);
    }

    /// @notice Adds liquidity to a Memeswap pair involving ETH.
    /// @param _token The address of the ERC20 token.
    /// @param _amountTokenDesired The desired amount of the ERC20 token.
    /// @param _amountTokenMin The minimum amount of the ERC20 token.
    /// @param _amountETHMin The minimum amount of ETH.
    /// @param _to The address to receive the liquidity tokens.
    /// @param _deadline The deadline by which the addLiquidityETH must be completed.
    /// @return amountToken The actual amount of the ERC20 token added.
    /// @return amountETH The actual amount of ETH added.
    /// @return liquidity The liquidity tokens minted.
    function addLiquidityETH(
        address _token,
        uint256 _amountTokenDesired,
        uint256 _amountTokenMin,
        uint256 _amountETHMin,
        address _to,
        uint256 _deadline
    ) public payable ensure(_deadline) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        (amountToken, amountETH) =
            _addLiquidity(_token, WETH, _amountTokenDesired, msg.value, _amountTokenMin, _amountETHMin);
        address pair = MemeswapLibrary.pairFor(factory, _token, WETH);
        MemeswapLibrary.safeTransferFrom(_token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IMemeswapPair(pair).mint(_to);
        if (msg.value > amountETH) {
            MemeswapLibrary.safeTransferETH(msg.sender, msg.value - amountETH);
        }
    }

    /// @notice Internal function to add liquidity.
    /// @param _tokenA The address of token A.
    /// @param _tokenB The address of token B.
    /// @param _amountADesired The desired amount of token A.
    /// @param _amountBDesired The desired amount of token B.
    /// @param _amountAMin The minimum amount of token A.
    /// @param _amountBMin The minimum amount of token B.
    /// @return amountA The actual amount of token A.
    /// @return amountB The actual amount of token B.
    function _addLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _amountADesired,
        uint256 _amountBDesired,
        uint256 _amountAMin,
        uint256 _amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        if (IMemeswapFactory(factory).getPair(_tokenA, _tokenB) == address(0)) {
            IMemeswapFactory(factory).createPair(_tokenA, _tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = MemeswapLibrary.getReserves(factory, _tokenA, _tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (_amountADesired, _amountBDesired);
        } else {
            uint256 amountBOptimal = MemeswapLibrary.quote(_amountADesired, reserveA, reserveB);
            if (amountBOptimal <= _amountBDesired) {
                if (amountBOptimal < _amountBMin) {
                    revert INSUFFICIENT_B_AMOUNT();
                }
                (amountA, amountB) = (_amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = MemeswapLibrary.quote(_amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= _amountADesired);
                if (amountAOptimal < _amountAMin) {
                    revert INSUFFICIENT_A_AMOUNT();
                }
                (amountA, amountB) = (amountAOptimal, _amountBDesired);
            }
        }
    }

    /// @notice Removes liquidity from a Memeswap pair.
    /// @param _tokenA The address of token A.
    /// @param _tokenB The address of token B.
    /// @param _liquidity The amount of liquidity tokens to remove.
    /// @param _amountAMin The minimum amount of token A.
    /// @param _amountBMin The minimum amount of token B.
    /// @param _to The address to receive the tokens.
    /// @param _deadline The deadline by which the removeLiquidity must be completed.
    /// @return amountA The actual amount of token A.
    /// @return amountB The actual amount of token B.
    function removeLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _liquidity,
        uint256 _amountAMin,
        uint256 _amountBMin,
        address _to,
        uint256 _deadline
    ) public ensure(_deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = MemeswapLibrary.pairFor(factory, _tokenA, _tokenB);
        IMemeswapPair(pair).transferFrom(msg.sender, pair, _liquidity);
        (uint256 amount0, uint256 amount1) = IMemeswapPair(pair).burn(_to);
        (address token0,) = MemeswapLibrary.sortTokens(_tokenA, _tokenB);
        (amountA, amountB) = _tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        if (amountA < _amountAMin) revert INSUFFICIENT_A_AMOUNT();
        if (amountB < _amountBMin) revert INSUFFICIENT_B_AMOUNT();
    }

    /// @notice Removes liquidity from a Memeswap pair with a permit.
    /// @param _tokenA The address of token A.
    /// @param _tokenB The address of token B.
    /// @param _liquidity The amount of liquidity tokens to remove.
    /// @param _amountAMin The minimum amount of token A.
    /// @param _amountBMin The minimum amount of token B.
    /// @param _to The address to receive the tokens.
    /// @param _deadline The deadline by which the removeLiquidity must be completed.
    /// @param _approveMax Whether to approve the maximum amount.
    /// @param _v The signature v value.
    /// @param _r The signature r value.
    /// @param _s The signature s value.
    /// @return amountA The actual amount of token A.
    /// @return amountB The actual amount of token B.
    function removeLiquidityWithPermit(
        address _tokenA,
        address _tokenB,
        uint256 _liquidity,
        uint256 _amountAMin,
        uint256 _amountBMin,
        address _to,
        uint256 _deadline,
        bool _approveMax,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external virtual returns (uint256 amountA, uint256 amountB) {
        address pair = MemeswapLibrary.pairFor(factory, _tokenA, _tokenB);
        uint256 value = _approveMax ? type(uint256).max : _liquidity;
        IMemeswapPair(pair).permit(msg.sender, address(this), value, _deadline, _v, _r, _s);
        (amountA, amountB) = removeLiquidity(_tokenA, _tokenB, _liquidity, _amountAMin, _amountBMin, _to, _deadline);
    }

    /// @notice Removes liquidity involving ETH from a Memeswap pair.
    /// @param _token The address of the ERC20 token.
    /// @param _liquidity The amount of liquidity tokens to remove.
    /// @param _amountTokenMin The minimum amount of the ERC20 token.
    /// @param _amountETHMin The minimum amount of ETH.
    /// @param _to The address to receive the tokens.
    /// @param _deadline The deadline by which the removeLiquidityETH must be completed.
    /// @return amountToken The actual amount of the ERC20 token.
    /// @return amountETH The actual amount of ETH.
    function removeLiquidityETH(
        address _token,
        uint256 _liquidity,
        uint256 _amountTokenMin,
        uint256 _amountETHMin,
        address _to,
        uint256 _deadline
    ) public ensure(_deadline) returns (uint256 amountToken, uint256 amountETH) {
        (amountToken, amountETH) =
            removeLiquidity(_token, WETH, _liquidity, _amountTokenMin, _amountETHMin, address(this), _deadline);
        MemeswapLibrary.safeTransfer(_token, _to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        MemeswapLibrary.safeTransferETH(_to, amountETH);
    }

    /// @notice Removes liquidity involving ETH from a Memeswap pair with a permit.
    /// @param _token The address of the ERC20 token.
    /// @param _liquidity The amount of liquidity tokens to remove.
    /// @param _amountTokenMin The minimum amount of the ERC20 token.
    /// @param _amountETHMin The minimum amount of ETH.
    /// @param _to The address to receive the tokens.
    /// @param _deadline The deadline by which the removeLiquidityETH must be completed.
    /// @param _approveMax Whether to approve the maximum amount.
    /// @param _v The signature v value.
    /// @param _r The signature r value.
    /// @param _s The signature s value.
    /// @return amountToken The actual amount of the ERC20 token.
    /// @return amountETH The actual amount of ETH.
    function removeLiquidityETHWithPermit(
        address _token,
        uint256 _liquidity,
        uint256 _amountTokenMin,
        uint256 _amountETHMin,
        address _to,
        uint256 _deadline,
        bool _approveMax,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external virtual returns (uint256 amountToken, uint256 amountETH) {
        address pair = MemeswapLibrary.pairFor(factory, _token, WETH);
        uint256 value = _approveMax ? type(uint256).max : _liquidity;
        IMemeswapPair(pair).permit(msg.sender, address(this), value, _deadline, _v, _r, _s);
        (amountToken, amountETH) =
            removeLiquidityETH(_token, _liquidity, _amountTokenMin, _amountETHMin, _to, _deadline);
    }

    /// @notice Removes liquidity involving ETH from a Memeswap pair supporting fee-on-transfer tokens.
    /// @param _token The address of the ERC20 token.
    /// @param _liquidity The amount of liquidity tokens to remove.
    /// @param _amountTokenMin The minimum amount of the ERC20 token.
    /// @param _amountETHMin The minimum amount of ETH.
    /// @param _to The address to receive the tokens.
    /// @param _deadline The deadline by which the removeLiquidityETH must be completed.
    /// @return amountETH The actual amount of ETH.
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address _token,
        uint256 _liquidity,
        uint256 _amountTokenMin,
        uint256 _amountETHMin,
        address _to,
        uint256 _deadline
    ) public ensure(_deadline) returns (uint256 amountETH) {
        (, amountETH) =
            removeLiquidity(_token, WETH, _liquidity, _amountTokenMin, _amountETHMin, address(this), _deadline);
        MemeswapLibrary.safeTransfer(_token, _to, IERC20(_token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        MemeswapLibrary.safeTransferETH(_to, amountETH);
    }

    /// @notice Removes liquidity involving ETH from a Memeswap pair with a permit, supporting fee-on-transfer tokens.
    /// @param _token The address of the ERC20 token.
    /// @param _liquidity The amount of liquidity tokens to remove.
    /// @param _amountTokenMin The minimum amount of the ERC20 token.
    /// @param _amountETHMin The minimum amount of ETH.
    /// @param _to The address to receive the tokens.
    /// @param _deadline The deadline by which the removeLiquidityETH must be completed.
    /// @param _approveMax Whether to approve the maximum amount.
    /// @param _v The signature v value.
    /// @param _r The signature r value.
    /// @param _s The signature s value.
    /// @return amountETH The actual amount of ETH.
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address _token,
        uint256 _liquidity,
        uint256 _amountTokenMin,
        uint256 _amountETHMin,
        address _to,
        uint256 _deadline,
        bool _approveMax,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external virtual returns (uint256 amountETH) {
        address pair = MemeswapLibrary.pairFor(factory, _token, WETH);
        uint256 value = _approveMax ? type(uint256).max : _liquidity;
        IMemeswapPair(pair).permit(msg.sender, address(this), value, _deadline, _v, _r, _s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            _token, _liquidity, _amountTokenMin, _amountETHMin, _to, _deadline
        );
    }

    /// @notice Internal function to swap tokens.
    /// @param _amounts The amounts to swap.
    /// @param _path The path of token addresses.
    /// @param _to The address to receive the output tokens.
    function _swap(uint256[] memory _amounts, address[] memory _path, address _to) internal {
        for (uint256 i; i < _path.length - 1; i++) {
            (address input, address output) = (_path[i], _path[i + 1]);
            (address token0,) = MemeswapLibrary.sortTokens(input, output);
            uint256 amountOut = _amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < _path.length - 2 ? MemeswapLibrary.pairFor(factory, output, _path[i + 2]) : _to;
            IMemeswapPair(MemeswapLibrary.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    /// @notice Swaps an exact amount of input tokens for as many output tokens as possible.
    /// @param _amountIn The amount of input tokens.
    /// @param _amountOutMin The minimum amount of output tokens.
    /// @param _path The path of token addresses.
    /// @param _to The address to receive the output tokens.
    /// @param _deadline The deadline by which the swap must be completed.
    /// @return amounts The amounts of each token swapped.
    function swapExactTokensForTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] calldata _path,
        address _to,
        uint256 _deadline
    ) external ensure(_deadline) returns (uint256[] memory amounts) {
        amounts = MemeswapLibrary.getAmountsOut(factory, _amountIn, _path);
        if (_amountOutMin > amounts[amounts.length - 1]) {
            revert INSUFFICIENT_OUTPUT_AMOUNT();
        }
        MemeswapLibrary.safeTransferFrom(
            _path[0], msg.sender, MemeswapLibrary.pairFor(factory, _path[0], _path[1]), amounts[0]
        );
        _swap(amounts, _path, _to);
    }

    /// @notice Swaps tokens to receive an exact amount of output tokens.
    /// @param _amountOut The exact amount of output tokens.
    /// @param _amountInMax The maximum amount of input tokens.
    /// @param _path The path of token addresses.
    /// @param _to The address to receive the output tokens.
    /// @param _deadline The deadline by which the swap must be completed.
    /// @return amounts The amounts of each token swapped.
    function swapTokensForExactTokens(
        uint256 _amountOut,
        uint256 _amountInMax,
        address[] calldata _path,
        address _to,
        uint256 _deadline
    ) external ensure(_deadline) returns (uint256[] memory amounts) {
        amounts = MemeswapLibrary.getAmountsIn(factory, _amountOut, _path);
        if (amounts[0] > _amountInMax) revert EXCESSIVE_INPUT_AMOUNT();
        MemeswapLibrary.safeTransferFrom(
            _path[0], msg.sender, MemeswapLibrary.pairFor(factory, _path[0], _path[1]), amounts[0]
        );
        _swap(amounts, _path, _to);
    }

    /// @notice Swaps an exact amount of ETH for as many output tokens as possible.
    /// @param _amountOutMin The minimum amount of output tokens.
    /// @param _path The path of token addresses.
    /// @param _to The address to receive the output tokens.
    /// @param _deadline The deadline by which the swap must be completed.
    /// @return amounts The amounts of each token swapped.
    function swapExactETHForTokens(uint256 _amountOutMin, address[] calldata _path, address _to, uint256 _deadline)
        external
        payable
        ensure(_deadline)
        returns (uint256[] memory amounts)
    {
        if (_path[0] != WETH) revert INVALID_PATH();
        amounts = MemeswapLibrary.getAmountsOut(factory, msg.value, _path);
        if (amounts[amounts.length - 1] < _amountOutMin) {
            revert INSUFFICIENT_OUTPUT_AMOUNT();
        }
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(MemeswapLibrary.pairFor(factory, _path[0], _path[1]), amounts[0]));
        _swap(amounts, _path, _to);
    }

    /// @notice Swaps tokens to receive an exact amount of ETH.
    /// @param _amountOut The exact amount of ETH.
    /// @param _amountInMax The maximum amount of input tokens.
    /// @param _path The path of token addresses.
    /// @param _to The address to receive the ETH.
    /// @param _deadline The deadline by which the swap must be completed.
    /// @return amounts The amounts of each token swapped.
    function swapTokensForExactETH(
        uint256 _amountOut,
        uint256 _amountInMax,
        address[] calldata _path,
        address _to,
        uint256 _deadline
    ) external ensure(_deadline) returns (uint256[] memory amounts) {
        if (_path[_path.length - 1] != WETH) revert INVALID_PATH();
        amounts = MemeswapLibrary.getAmountsIn(factory, _amountOut, _path);
        if (amounts[0] > _amountInMax) revert EXCESSIVE_INPUT_AMOUNT();
        MemeswapLibrary.safeTransferFrom(
            _path[0], msg.sender, MemeswapLibrary.pairFor(factory, _path[0], _path[1]), amounts[0]
        );
        _swap(amounts, _path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        MemeswapLibrary.safeTransferETH(_to, amounts[amounts.length - 1]);
    }

    /// @notice Swaps an exact amount of tokens for as much ETH as possible.
    /// @param _amountIn The amount of input tokens.
    /// @param _amountOutMin The minimum amount of ETH.
    /// @param _path The path of token addresses.
    /// @param _to The address to receive the ETH.
    /// @param _deadline The deadline by which the swap must be completed.
    /// @return amounts The amounts of each token swapped.
    function swapExactTokensForETH(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] calldata _path,
        address _to,
        uint256 _deadline
    ) external ensure(_deadline) returns (uint256[] memory amounts) {
        if (_path[_path.length - 1] != WETH) revert INVALID_PATH();
        amounts = MemeswapLibrary.getAmountsOut(factory, _amountIn, _path);
        if (amounts[amounts.length - 1] < _amountOutMin) {
            revert INSUFFICIENT_OUTPUT_AMOUNT();
        }
        MemeswapLibrary.safeTransferFrom(
            _path[0], msg.sender, MemeswapLibrary.pairFor(factory, _path[0], _path[1]), amounts[0]
        );
        _swap(amounts, _path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        MemeswapLibrary.safeTransferETH(_to, amounts[amounts.length - 1]);
    }

    /// @notice Swaps an exact amount of ETH to receive a specific amount of tokens.
    /// @param _amountOut The exact amount of tokens.
    /// @param _path The path of token addresses.
    /// @param _to The address to receive the output tokens.
    /// @param _deadline The deadline by which the swap must be completed.
    /// @return amounts The amounts of each token swapped.
    function swapETHForExactTokens(uint256 _amountOut, address[] calldata _path, address _to, uint256 _deadline)
        external
        payable
        ensure(_deadline)
        returns (uint256[] memory amounts)
    {
        if (_path[0] != WETH) revert INVALID_PATH();
        amounts = MemeswapLibrary.getAmountsIn(factory, _amountOut, _path);
        if (amounts[0] > msg.value) revert EXCESSIVE_INPUT_AMOUNT();
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(MemeswapLibrary.pairFor(factory, _path[0], _path[1]), amounts[0]));
        _swap(amounts, _path, _to);
        if (msg.value > amounts[0]) {
            MemeswapLibrary.safeTransferETH(msg.sender, msg.value - amounts[0]);
        }
    }

    /// @notice Internal function to swap tokens supporting fee-on-transfer tokens.
    /// @param _path The path of token addresses.
    /// @param _to The address to receive the output tokens.
    function _swapSupportingFeeOnTransferTokens(address[] memory _path, address _to) internal {
        for (uint256 i; i < _path.length - 1; i++) {
            (address input, address output) = (_path[i], _path[i + 1]);
            (address token0,) = MemeswapLibrary.sortTokens(input, output);
            IMemeswapPair pair = IMemeswapPair(MemeswapLibrary.pairFor(factory, input, output));
            uint256 amountInput;
            uint256 amountOutput;
            {
                uint256 fee = pair.getFee();
                (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) =
                    input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
                amountInput = IERC20(input).balanceOf(address(pair)) - reserveInput;
                amountOutput = MemeswapLibrary.getAmountOut(amountInput, reserveInput, reserveOutput, fee);
            }
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
            address to = i < _path.length - 2 ? MemeswapLibrary.pairFor(factory, output, _path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    /// @notice Swaps an exact amount of input tokens for as many output tokens as possible, supporting fee-on-transfer tokens.
    /// @param _amountIn The exact amount of input tokens.
    /// @param _amountOutMin The minimum amount of output tokens.
    /// @param _path The path of token addresses.
    /// @param _to The address to receive the output tokens.
    /// @param _deadline The deadline by which the swap must be completed.
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] calldata _path,
        address _to,
        uint256 _deadline
    ) external ensure(_deadline) {
        MemeswapLibrary.safeTransferFrom(
            _path[0], msg.sender, MemeswapLibrary.pairFor(factory, _path[0], _path[1]), _amountIn
        );
        uint256 balanceBefore = IERC20(_path[_path.length - 1]).balanceOf(_to);
        _swapSupportingFeeOnTransferTokens(_path, _to);
        if (IERC20(_path[_path.length - 1]).balanceOf(_to) - balanceBefore < _amountOutMin) {
            revert INSUFFICIENT_OUTPUT_AMOUNT();
        }
    }

    /// @notice Swaps an exact amount of ETH for as many output tokens as possible, supporting fee-on-transfer tokens.
    /// @param _amountOutMin The minimum amount of output tokens.
    /// @param _path The path of token addresses.
    /// @param _to The address to receive the output tokens.
    /// @param _deadline The deadline by which the swap must be completed.
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 _amountOutMin,
        address[] calldata _path,
        address _to,
        uint256 _deadline
    ) external payable ensure(_deadline) {
        if (_path[0] != WETH) revert INVALID_PATH();
        uint256 amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(MemeswapLibrary.pairFor(factory, _path[0], _path[1]), amountIn));
        uint256 balanceBefore = IERC20(_path[_path.length - 1]).balanceOf(_to);
        _swapSupportingFeeOnTransferTokens(_path, _to);
        if (IERC20(_path[_path.length - 1]).balanceOf(_to) - balanceBefore < _amountOutMin) {
            revert INSUFFICIENT_OUTPUT_AMOUNT();
        }
    }

    /// @notice Swaps an exact amount of input tokens for as much ETH as possible, supporting fee-on-transfer tokens.
    /// @param _amountIn The exact amount of input tokens.
    /// @param _amountOutMin The minimum amount of ETH.
    /// @param _path The path of token addresses.
    /// @param _to The address to receive the ETH.
    /// @param _deadline The deadline by which the swap must be completed.
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] calldata _path,
        address _to,
        uint256 _deadline
    ) external ensure(_deadline) {
        if (_path[_path.length - 1] != WETH) revert INVALID_PATH();
        MemeswapLibrary.safeTransferFrom(
            _path[0], msg.sender, MemeswapLibrary.pairFor(factory, _path[0], _path[1]), _amountIn
        );
        _swapSupportingFeeOnTransferTokens(_path, address(this));
        uint256 amountOut = IERC20(WETH).balanceOf(address(this));
        if (amountOut < _amountOutMin) revert INSUFFICIENT_OUTPUT_AMOUNT();
        IWETH(WETH).withdraw(amountOut);
        MemeswapLibrary.safeTransferETH(_to, amountOut);
    }

    /// @notice Returns the quoted amount of token B given token A.
    /// @param _amountA The amount of token A.
    /// @param _reserveA The reserve of token A.
    /// @param _reserveB The reserve of token B.
    /// @return amountB The quoted amount of token B.
    function quote(uint256 _amountA, uint256 _reserveA, uint256 _reserveB) public pure returns (uint256 amountB) {
        return MemeswapLibrary.quote(_amountA, _reserveA, _reserveB);
    }

    /// @notice Returns the amounts of each token for a swap given an input amount and path.
    /// @param _amountIn The input amount.
    /// @param _path The path of token addresses.
    /// @return amounts The amounts of each token in the swap.
    function getAmountsOut(uint256 _amountIn, address[] memory _path) public view returns (uint256[] memory amounts) {
        return MemeswapLibrary.getAmountsOut(factory, _amountIn, _path);
    }

    /// @notice Returns the amounts of each token for a swap given an output amount and path.
    /// @param _amountOut The output amount.
    /// @param _path The path of token addresses.
    /// @return amounts The amounts of each token in the swap.
    function getAmountsIn(uint256 _amountOut, address[] memory _path) public view returns (uint256[] memory amounts) {
        return MemeswapLibrary.getAmountsIn(factory, _amountOut, _path);
    }
}
