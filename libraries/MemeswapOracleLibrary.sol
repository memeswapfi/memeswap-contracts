// SPDX-License-Identifier: CC-BY-4.0
pragma solidity ^0.8.24;

import "../interfaces/IMemeswapPair.sol";
import "./FixedPoint.sol";

library MemeswapOracleLibrary {
    using FixedPoint for *;

    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2 ** 32);
    }

    function currentCumulativePrices(address pair)
        internal
        view
        returns (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp)
    {
        blockTimestamp = currentBlockTimestamp();
        price0Cumulative = IMemeswapPair(pair).price0CumulativeLast();
        price1Cumulative = IMemeswapPair(pair).price1CumulativeLast();
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IMemeswapPair(pair).getReserves();
        if (blockTimestampLast != blockTimestamp) {
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;
            price0Cumulative += uint256(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
            price1Cumulative += uint256(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsed;
        }
    }
}
