// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct LaunchParams {
    string name;
    string symbol;
    uint256 totalSupply;
    uint256[] taxes;
    string[] urls;
    uint256 duration;
    uint256 minAmount;
    uint256 buyAmount;
    address pairToUnlock;
}

interface IMemeswapTokenFactory {
    function owner() external view returns (address);

    function factory() external view returns (address);

    function router() external view returns (address);

    function bmf() external view returns (address);

    function isMemeswapToken(address token) external view returns (bool);

    function getAllowedDurations() external view returns (uint256[] memory);

    function isAllowedDuration(uint256) external view returns (bool);

    function setAllowedDurations(uint256[] memory) external;

    function vault() external view returns (address);

    function launch(
        LaunchParams calldata _params
    ) external payable returns (address token, uint256 liquidity);
}
