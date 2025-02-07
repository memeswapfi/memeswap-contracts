// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Math
/// @notice Library for mathematical functions
library Math {
    /// @notice Returns the largest of two numbers
    /// @param _x The first number
    /// @param _y The second number
    /// @return z The larger of the two numbers
    function min(uint256 _x, uint256 _y) internal pure returns (uint256 z) {
        z = _x < _y ? _x : _y;
    }

    /// @notice Returns the smallest of two numbers
    /// @dev Babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    /// @param _y The number to take the square root of
    /// @return z The square root of the number
    function sqrt(uint256 _y) internal pure returns (uint256 z) {
        if (_y > 3) {
            z = _y;
            uint256 x = _y / 2 + 1;
            while (x < z) {
                z = x;
                x = (_y / x + x) / 2;
            }
        } else if (_y != 0) {
            z = 1;
        }
    }
}
