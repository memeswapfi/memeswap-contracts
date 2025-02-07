// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMemeswapFactory {
    function owner() external view returns (address);

    function router() external view returns (address);

    function isPair(address pair) external view returns (bool);

    function lock() external view returns (address);

    function feeTo() external view returns (address);

    function serviceFee() external view returns (uint256);

    function tryValhalla() external;

    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);

    function setServiceFee(uint256) external;

    function setFeeTo(address) external;

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);

    function tokenFactory() external view returns (address);

    function isWhitelisted(address token) external view returns (bool);

    function addWhitelisted(address token) external;

    function removeWhitelisted(address token) external;
}
