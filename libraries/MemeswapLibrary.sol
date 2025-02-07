// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMemeswapFactory} from "../interfaces/IMemeswapFactory.sol";
import {IMemeswapPair} from "../interfaces/IMemeswapPair.sol";

/// @title MemeswapLibrary
/// @notice Library for Memeswap functions
/// @dev Contains helper functions for Memeswap pairs
library MemeswapLibrary {
    error IDENTICAL_ADDRESSES();
    error ZERO_ADDRESS();
    error INSUFFICIENT_AMOUNT();
    error INSUFFICIENT_LIQUIDITY();
    error INSUFFICIENT_INPUT_AMOUNT();
    error INSUFFICIENT_OUTPUT_AMOUNT();
    error INVALID_PATH();
    error INVALID_PAIR();
    error TRANSFER_FAILED();

    /// @notice Sorts two token addresses in ascending order
    /// @param _tokenA Address of the first token
    /// @param _tokenB Address of the second token
    /// @return token0 The smaller address of the two
    /// @return token1 The larger address of the two
    function sortTokens(
        address _tokenA,
        address _tokenB
    ) internal pure returns (address token0, address token1) {
        if (_tokenA == _tokenB) revert IDENTICAL_ADDRESSES();
        (token0, token1) = _tokenA < _tokenB
            ? (_tokenA, _tokenB)
            : (_tokenB, _tokenA);
        if (token0 == address(0)) revert ZERO_ADDRESS();
    }

    /// @notice Calculates the pair address for two tokens
    /// @param _factory Address of the factory contract
    /// @param _tokenA Address of the first token
    /// @param _tokenB Address of the second token
    /// @return pair Address of the pair contract
    function pairFor(
        address _factory,
        address _tokenA,
        address _tokenB
    ) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(_tokenA, _tokenB);
        bytes
            memory bytecode = hex"c8656f6279247b61cd17cb22c21cd36ea5b61058c7041c2b9c26debdca62c8c7";
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), _factory, salt, bytecode)
        );
        return address(uint160(uint256(hash)));
    }

    /// @notice Fetches and sorts the reserves for a pair
    /// @param _factory Address of the factory contract
    /// @param _tokenA Address of the first token
    /// @param _tokenB Address of the second token
    /// @return reserveA Reserve of the first token
    /// @return reserveB Reserve of the second token
    function getReserves(
        address _factory,
        address _tokenA,
        address _tokenB
    ) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, ) = sortTokens(_tokenA, _tokenB);
        (uint256 reserve0, uint256 reserve1, ) = IMemeswapPair(
            pairFor(_factory, _tokenA, _tokenB)
        ).getReserves();
        (reserveA, reserveB) = _tokenA == token0
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
    }

    /// @notice Given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    /// @param _amountA Amount of the first token
    /// @param _reserveA Reserve of the first token
    /// @param _reserveB Reserve of the second token
    /// @return amountB Equivalent amount of the second token
    function quote(
        uint256 _amountA,
        uint256 _reserveA,
        uint256 _reserveB
    ) internal pure returns (uint256 amountB) {
        if (_amountA == 0) revert INSUFFICIENT_AMOUNT();
        if (_reserveA == 0 || _reserveB == 0) revert INSUFFICIENT_LIQUIDITY();
        amountB = (_amountA * _reserveB) / _reserveA;
    }

    /// @notice Given an input amount of an asset, returns the maximum output amount of the other asset
    /// @param _amountIn Input amount of the first token
    /// @param _reserveIn Reserve of the input token
    /// @param _reserveOut Reserve of the output token
    /// @return amountOut Maximum output amount of the second token
    function getAmountOut(
        uint256 _amountIn,
        uint256 _reserveIn,
        uint256 _reserveOut,
        uint256 _fee
    ) internal pure returns (uint256 amountOut) {
        if (_amountIn == 0) revert INSUFFICIENT_INPUT_AMOUNT();
        if (_reserveIn == 0 || _reserveOut == 0) {
            revert INSUFFICIENT_LIQUIDITY();
        }
        uint256 amountInWithFee = _amountIn * (1000 - _fee);
        uint256 numerator = amountInWithFee * _reserveOut;
        uint256 denominator = (_reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @notice Given an output amount of an asset, returns the required input amount of the other asset.
    /// @param _amountOut Output amount of the second token
    /// @param _reserveIn Reserve of the input token
    /// @param _reserveOut Reserve of the output token
    /// @return amountIn Required input amount of the first token
    function getAmountIn(
        uint256 _amountOut,
        uint256 _reserveIn,
        uint256 _reserveOut,
        uint256 _fee
    ) internal pure returns (uint256 amountIn) {
        if (_amountOut == 0) revert INSUFFICIENT_OUTPUT_AMOUNT();
        if (_reserveIn == 0 || _reserveOut == 0) {
            revert INSUFFICIENT_LIQUIDITY();
        }
        uint256 numerator = _reserveIn * _amountOut * 1000;
        uint256 denominator = (_reserveOut - _amountOut) * (1000 - _fee);
        amountIn = (numerator / denominator) + 1;
    }

    /// @notice Perform chained getAmountOut calculations on any number of pairs
    /// @param _factory Address of the factory contract
    /// @param _amountIn Input amount of the first token
    /// @param _path Array of token addresses
    /// @return amounts Array of output amounts at each step
    function getAmountsOut(
        address _factory,
        uint256 _amountIn,
        address[] memory _path
    ) internal view returns (uint256[] memory amounts) {
        if (_path.length < 2) revert INVALID_PATH();
        amounts = new uint256[](_path.length);
        amounts[0] = _amountIn;
        for (uint256 i; i < _path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(
                _factory,
                _path[i],
                _path[i + 1]
            );
            address pair = IMemeswapFactory(_factory).getPair(
                _path[i],
                _path[i + 1]
            );
            uint256 fee = IMemeswapPair(pair).getFee();
            amounts[i + 1] = getAmountOut(
                amounts[i],
                reserveIn,
                reserveOut,
                fee
            );
        }
    }

    /// @notice Perform chained getAmountIn calculations on any number of pairs
    /// @param _factory Address of the factory contract
    /// @param _amountOut Output amount of the last token
    /// @param _path Array of token addresses
    /// @return amounts Array of input amounts at each step
    function getAmountsIn(
        address _factory,
        uint256 _amountOut,
        address[] memory _path
    ) internal view returns (uint256[] memory amounts) {
        if (_path.length < 2) revert INVALID_PATH();
        amounts = new uint256[](_path.length);
        amounts[amounts.length - 1] = _amountOut;
        for (uint256 i = _path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(
                _factory,
                _path[i - 1],
                _path[i]
            );
            address pair = IMemeswapFactory(_factory).getPair(
                _path[i - 1],
                _path[i]
            );
            uint256 fee = IMemeswapPair(pair).getFee();
            amounts[i - 1] = getAmountIn(
                amounts[i],
                reserveIn,
                reserveOut,
                fee
            );
        }
    }

    /// @notice Safely approves tokens for transfer
    /// @param _token Address of the token
    /// @param _to Address to approve
    /// @param _value Amount of tokens to approve
    function safeApprove(address _token, address _to, uint256 _value) internal {
        (bool success, bytes memory data) = _token.call(
            abi.encodeWithSelector(0x095ea7b3, _to, _value)
        );
        if (
            !success || (data.length > 0 && abi.decode(data, (bool)) == false)
        ) {
            revert TRANSFER_FAILED();
        }
    }

    /// @notice Safely transfers tokens
    /// @param _token Address of the token
    /// @param _to Address to transfer to
    /// @param _value Amount of tokens to transfer
    function safeTransfer(
        address _token,
        address _to,
        uint256 _value
    ) internal {
        (bool success, bytes memory data) = _token.call(
            abi.encodeWithSelector(0xa9059cbb, _to, _value)
        );
        if (
            !success || (data.length > 0 && abi.decode(data, (bool)) == false)
        ) {
            revert TRANSFER_FAILED();
        }
    }

    /// @notice Safely transfers tokens from one address to another
    /// @param _token Address of the token
    /// @param _from Address to transfer from
    /// @param _to Address to transfer to
    /// @param _value Amount of tokens to transfer
    function safeTransferFrom(
        address _token,
        address _from,
        address _to,
        uint256 _value
    ) internal {
        (bool success, bytes memory data) = _token.call(
            abi.encodeWithSelector(0x23b872dd, _from, _to, _value)
        );
        if (
            !success || (data.length > 0 && abi.decode(data, (bool)) == false)
        ) {
            revert TRANSFER_FAILED();
        }
    }

    /// @notice Safely transfers Ether
    /// @param _to Address to transfer to
    /// @param _value Amount of Ether to transfer
    function safeTransferETH(address _to, uint256 _value) internal {
        (bool success, ) = _to.call{value: _value}(new bytes(0));
        if (!success) revert TRANSFER_FAILED();
    }
}
