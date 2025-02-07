// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMemeswapFarmFactory {
    function isMemeswapFarm(address farm) external view returns (bool);

    function needValhalla() external view returns (bool);

    function isPartnerToken(
        address pair,
        address token
    ) external view returns (bool);

    function getPartnerToken(address pair) external view returns (address);

    function buffer() external view returns (uint256);

    function deployFarm(
        address token,
        address[] memory pairs,
        uint256 amount,
        uint256 duration
    ) external returns (address);
}
