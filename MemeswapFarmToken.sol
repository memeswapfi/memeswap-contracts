// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract MemeswapFarmToken is ERC20, Ownable {
    error NOT_ALLOWED();

    constructor() ERC20("Memeswap Farm Token", "MFT") Ownable(msg.sender) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function renounceOwnership() public view override onlyOwner {
        revert NOT_ALLOWED();
    }
}
