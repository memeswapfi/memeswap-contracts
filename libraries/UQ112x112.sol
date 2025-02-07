// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library UQ112x112 {
    uint224 constant Q112 = 2 ** 112;

    /// @notice Encodes a uint112 as a UQ112x112
    /// @param y The uint112 to encode
    /// @return z The encoded UQ112x112
    function encode(uint112 y) internal pure returns (uint224 z) {
        z = uint224(y) * Q112;
    }

    /// @notice Divides a UQ112x112 by a uint112, returning a UQ112x112
    /// @param x The UQ112x112 to divide
    /// @param y The uint112 to divide by
    /// @return z The result of the division
    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}
