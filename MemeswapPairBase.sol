// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMemeswapPairBase} from "./interfaces/IMemeswapPairBase.sol";

contract MemeswapPairBase is IMemeswapPairBase {
    string public constant name = "Memeswap LP Token";
    string public constant symbol = "MLP";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;

    error EXPIRED();
    error INVALID_SIGNATURE();
    error INSUFFICIENT_BALANCE();
    error INSUFFICIENT_ALLOWANCE();

    /// @dev Initializes the contract by setting up the DOMAIN_SEPARATOR
    constructor() {
        uint256 chainId = block.chainid;
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    /// @notice Mints new tokens
    /// @param _to The address to which the minted tokens will be sent
    /// @param _value The amount of tokens to be minted
    /// @dev Only callable by internal functions
    function _mint(address _to, uint256 _value) internal {
        totalSupply = totalSupply + _value;
        balanceOf[_to] = balanceOf[_to] + _value;
        emit Transfer(address(0), _to, _value);
    }

    /// @notice Burns tokens from a given address
    /// @param _from The address from which the tokens will be burned
    /// @param _value The amount of tokens to be burned
    /// @dev Only callable by internal functions
    /// @dev Reverts with INSUFFICIENT_BALANCE if the balance is insufficient
    function _burn(address _from, uint256 _value) internal {
        if (balanceOf[_from] < _value) revert INSUFFICIENT_BALANCE();
        balanceOf[_from] = balanceOf[_from] - _value;
        totalSupply = totalSupply - _value;
        emit Transfer(_from, address(0), _value);
    }

    /// @notice Approves a spender to spend a certain amount of tokens
    /// @param _owner The owner of the tokens
    /// @param _spender The address allowed to spend the tokens
    /// @param _value The amount of tokens they are allowed to spend
    /// @dev Only callable by internal functions
    function _approve(address _owner, address _spender, uint256 _value) internal {
        allowance[_owner][_spender] = _value;
        emit Approval(_owner, _spender, _value);
    }

    /// @notice Transfers tokens from one address to another
    /// @param _from The address from which the tokens will be transferred
    /// @param _to The address to which the tokens will be transferred
    /// @param _value The amount of tokens to be transferred
    /// @dev Only callable by internal functions
    function _transfer(address _from, address _to, uint256 _value) private {
        balanceOf[_from] = balanceOf[_from] - _value;
        balanceOf[_to] = balanceOf[_to] + _value;
        emit Transfer(_from, _to, _value);
    }

    /// @notice Approves a spender to spend a certain amount of tokens
    /// @param _spender The address allowed to spend the tokens
    /// @param _value The amount of tokens they are allowed to spend
    /// @return A boolean indicating success
    function approve(address _spender, uint256 _value) external returns (bool) {
        _approve(msg.sender, _spender, _value);
        return true;
    }

    /// @notice Transfers tokens to a specified address
    /// @param _to The address to which the tokens will be transferred
    /// @param _value The amount of tokens to be transferred
    /// @return A boolean indicating success
    function transfer(address _to, uint256 _value) external returns (bool) {
        _transfer(msg.sender, _to, _value);
        return true;
    }

    /// @notice Transfers tokens from one address to another using an allowance mechanism
    /// @param _from The address from which the tokens will be transferred
    /// @param _to The address to which the tokens will be transferred
    /// @param _value The amount of tokens to be transferred
    /// @return A boolean indicating success
    /// @dev Reverts with INSUFFICIENT_ALLOWANCE if the allowance is insufficient
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool) {
        if (allowance[_from][msg.sender] < _value) {
            revert INSUFFICIENT_ALLOWANCE();
        }
        if (allowance[_from][msg.sender] != type(uint256).max) {
            allowance[_from][msg.sender] = allowance[_from][msg.sender] - _value;
        }
        _transfer(_from, _to, _value);
        return true;
    }

    /// @notice Sets an allowance using a signed permit
    /// @param _owner The owner of the tokens
    /// @param _spender The address allowed to spend the tokens
    /// @param _value The amount of tokens they are allowed to spend
    /// @param _deadline The time until which the permit is valid
    /// @param _v The recovery byte of the signature
    /// @param _r Half of the ECDSA signature pair
    /// @param _s Half of the ECDSA signature pair
    /// @dev Reverts with EXPIRED if the deadline has passed
    /// @dev Reverts with INVALID_SIGNATURE if the signature is invalid
    function permit(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        if (_deadline < block.timestamp) revert EXPIRED();
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, _owner, _spender, _value, nonces[_owner]++, _deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, _v, _r, _s);
        if (recoveredAddress == address(0) || recoveredAddress != _owner) {
            revert INVALID_SIGNATURE();
        }
        _approve(_owner, _spender, _value);
    }
}
