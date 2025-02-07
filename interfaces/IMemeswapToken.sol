// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMemeswapToken {
    function owner() external view returns (address);

    function initialize(address pair) external;

    function maxPerSwap() external view returns (uint256);

    function burn(uint256 amount) external;

    function updateURLs(string[] calldata urls) external;

    function removeTax() external;

    function depositToInterpol() external;
}
