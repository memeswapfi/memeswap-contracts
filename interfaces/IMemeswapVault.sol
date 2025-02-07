// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMemeswapVault {
    struct Rent {
        address user;
        address token;
        uint256 amount;
        uint256 duration;
        uint256 endDate;
    }

    function getPriceForAmount(
        uint256 amount,
        uint256 duration
    ) external view returns (uint256);

    function getAmountForPrice(
        uint256 price,
        uint256 duration
    ) external view returns (uint256);

    function canRent(uint256 amount) external view returns (bool);

    function setChadBar(uint256 bar) external;

    function setValhallaFee(uint256 fee) external;

    function valhalla(address pair) external;

    function rent(
        address pair,
        address token,
        uint256 amount,
        uint256 duration,
        address user,
        address pairToUnlock
    ) external;

    function valhallaDate(address token) external view returns (uint256);

    function interpolLocks(address pair) external view returns (address);

    function rents(address pair) external view returns (Rent memory);
}
