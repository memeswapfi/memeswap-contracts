// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IMemeswapRouter} from "./interfaces/IMemeswapRouter.sol";
import {IMemeswapTokenFactory} from "./interfaces/IMemeswapTokenFactory.sol";
import {IMemeswapFactory} from "./interfaces/IMemeswapFactory.sol";
import {IMemeswapPair} from "./interfaces/IMemeswapPair.sol";
import {IMemeswapVault} from "./interfaces/IMemeswapVault.sol";
import {IInterpolLock} from "./interfaces/IInterpolLock.sol";
import {IMemeswapBMF} from "./interfaces/IMemeswapBMF.sol";

// @title MemeswapToken
// @author Memeswap
// @notice MemeswapToken contract is an ERC20 token with additional features for swapping and trading.
contract MemeswapToken is ERC20, Ownable {
    uint256 public buyTax;
    uint256 public sellTax;
    uint256 public ownerShare;
    uint256 public immutable buyBackMode;
    address public immutable router;
    bool public swapping;
    uint256 public initializedAt;
    string[] public urls;
    address public immutable factory;
    address public immutable tokenFactory;
    mapping(address => uint256) public lastSwap;
    address public swapPair;

    /// @notice Emitted when tokens are minted
    /// @param to The address receiving the minted tokens
    /// @param amount The amount of tokens minted
    event Mint(address indexed to, uint256 amount);

    /// @notice Emitted when tokens are burned
    /// @param from The address from which the tokens are burned
    /// @param amount The amount of tokens burned
    event Burn(address indexed from, uint256 amount);

    /// @notice Emitted when the owner earns tokens from tax
    /// @param owner The address of the owner
    /// @param amount The amount of tokens earned
    event Earned(address indexed owner, uint256 amount);

    /// @notice Emitted when the URLs are updated
    /// @param urls The updated list of URLs
    event UpdatedURLs(string[] urls);

    /// @notice Emitted when the tax is removed
    event TaxRemoved();

    /// @notice Emitted when tokens are locked in the vault
    /// @param pair The address of the swap pair
    /// @param lock The address of the interpol lock
    /// @param amount The amount of tokens locked
    event Locked(address indexed pair, address indexed lock, uint256 amount);

    /// @notice Emitted when tokens are bribed to BMF
    /// @param amount The amount of tokens bribed
    event Bribed(uint256 amount);

    error FORBIDDEN();
    error NOT_MEMESWAP_PAIR();
    error WRONG_PAIR();
    error INSUFFICIENT_BALANCE();
    error MAX_SWAP_AMOUNT();
    error SWAP_TOO_SOON();
    error TOO_MANY_URLS();
    error WRONG_FEE();
    error TX_FAILED();
    error NOT_ALLOWED();

    /// @notice Constructs the MemeswapToken
    /// @dev Mints the initial total supply to the owner
    /// @param _name Name of the token
    /// @param _symbol Symbol of the token
    /// @param _totalSupply Initial total supply of the token
    /// @param _buyBackMode Buyback mode setting
    /// @param _buyTax Buy tax percentage
    /// @param _sellTax Sell tax percentage
    /// @param _ownerShare Share retained by the owner from tax
    /// @param _router Address of the router
    /// @param _owner Address of the owner
    /// @param _urls Initial list of URLs
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint256 _buyBackMode,
        uint256 _buyTax,
        uint256 _sellTax,
        uint256 _ownerShare,
        address _router,
        address _owner,
        string[] memory _urls
    ) ERC20(_name, _symbol) Ownable(_owner) {
        urls = _urls;
        buyTax = _buyTax;
        sellTax = _sellTax;
        ownerShare = _ownerShare;
        buyBackMode = _buyBackMode;
        router = _router;
        factory = IMemeswapRouter(router).factory();
        tokenFactory = IMemeswapFactory(factory).tokenFactory();
        super._update(address(0), _owner, _totalSupply);
        emit Mint(_owner, _totalSupply);
    }

    /// @dev Modifier to prevent bot activities during swaps
    /// @param _from Address sending the tokens
    /// @param _to Address receiving the tokens
    /// @param _value Amount of tokens
    modifier antibot(address _from, address _to, uint256 _value) {
        if (!notTaxable(_from, _to) && !swapping) {
            if (_value > maxPerSwap()) revert MAX_SWAP_AMOUNT();
            if (_to == swapPair) {
                if (lastSwap[_from] != 0 && lastSwap[_from] + secondsNeeded() > block.timestamp) revert SWAP_TOO_SOON();
                lastSwap[_from] = block.timestamp;
            } else {
                if (lastSwap[_to] != 0 && lastSwap[_to] + secondsNeeded() > block.timestamp) revert SWAP_TOO_SOON();
                lastSwap[_to] = block.timestamp;
            }
        }
        _;
    }

    /// @dev Modifier to enforce fee payment
    modifier takeFee() {
        if (msg.value != IMemeswapFactory(factory).serviceFee()) {
            revert WRONG_FEE();
        }
        (bool success,) = IMemeswapFactory(factory).feeTo().call{value: msg.value}("");
        if (!success) revert TX_FAILED();
        _;
    }

    /// @notice Initialize the token contract with a swap pair
    /// @dev Can only be called once
    /// @dev Can only be called by the owner or the token factory
    /// @dev The swap pair must be a Memeswap pair
    /// @param _pair Address of the swap pair
    function initialize(address _pair) external {
        if (initializedAt != 0) revert FORBIDDEN();
        if (!IMemeswapFactory(factory).isPair(_pair)) {
            revert NOT_MEMESWAP_PAIR();
        }
        if (IMemeswapPair(_pair).token0() != address(this) && IMemeswapPair(_pair).token1() != address(this)) {
            revert WRONG_PAIR();
        }
        if (msg.sender != owner() && msg.sender != tokenFactory) {
            revert FORBIDDEN();
        }
        initializedAt = block.timestamp;
        swapPair = _pair;
    }

    /// @notice Update the URLs associated with the token
    /// @param _urls The new list of URLs
    function updateURLs(string[] memory _urls) external payable onlyOwner takeFee {
        if (_urls.length > 10) revert TOO_MANY_URLS();
        urls = _urls;
        emit UpdatedURLs(_urls);
    }

    /// @notice Remove the buy, sell, and owner share taxes
    function removeTax() external payable onlyOwner takeFee {
        buyTax = 0;
        sellTax = 0;
        ownerShare = 0;
        emit TaxRemoved();
    }

    /// @notice Check if a transaction is taxable
    /// @param _from Address sending the tokens
    /// @param _to Address receiving the tokens
    /// @return bool True if the transaction is not taxable, else false
    function notTaxable(address _from, address _to) public view returns (bool) {
        return _isOwner(_from, _to) || _isProtocol(_from, _to) || _isVault(_to);
    }

    /// @notice Update balances during transactions
    /// @param _from Address sending the tokens
    /// @param _to Address receiving the tokens
    /// @param _value Amount of tokens
    function _update(address _from, address _to, uint256 _value) internal override antibot(_from, _to, _value) {
        bool swapBack = balanceOf(address(this)) > totalSupply() / 1000;
        uint256 amount = totalSupply() / 1000;
        if (swapBack && !swapping && !notTaxable(_from, _to) && _from != swapPair) {
            swapping = true;
            _execute(amount);
            swapping = false;
        }
        bool beTaxed = !swapping;
        if (notTaxable(_from, _to)) {
            beTaxed = false;
        }
        if (beTaxed) {
            uint256 tax = 0;
            if (_to == swapPair && sellTax > 0) {
                tax = (_value * sellTax) / 1000;
            } else if (_from == swapPair && buyTax > 0) {
                tax = (_value * buyTax) / 1000;
            }
            if (tax > 0) {
                uint256 deserved = (tax * ownerShare) / 1000;
                if (deserved > 0) {
                    super._update(_from, owner(), deserved);
                    emit Earned(owner(), deserved);
                }
                if (tax - deserved > 0) {
                    super._update(_from, address(this), tax - deserved);
                }
            }
            _value -= tax;
        }
        super._update(_from, _to, _value);
    }

    /// @notice Execute buyback or liquidity provision
    /// @param _amount Amount of tokens
    function _execute(uint256 _amount) private {
        if (buyBackMode == 0) {
            super._update(address(this), address(0), _amount);
            emit Burn(address(this), _amount);
        } else {
            _bribe(_amount);
        }
    }

    /// @notice Sell tokens and bribe BMF
    /// @param _amount Amount of tokens
    function _bribe(uint256 _amount) private {
        address liquidityToken = IMemeswapPair(swapPair).token0() == address(this)
            ? IMemeswapPair(swapPair).token1()
            : IMemeswapPair(swapPair).token0();
        _swapTokens(liquidityToken, _amount);
        address bmf = IMemeswapTokenFactory(tokenFactory).bmf();
        uint256 balance = ERC20(liquidityToken).balanceOf(address(this));
        if (balance == 0) return;
        ERC20(liquidityToken).approve(bmf, balance);
        IMemeswapBMF(bmf).bribe(address(this), balance);
        emit Bribed(balance);
    }

    /// @notice Swap tokens to liquidity token
    /// @param _liquidityToken Address of liquidity token
    /// @param _amount Amount to be swapped
    function _swapTokens(address _liquidityToken, uint256 _amount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _liquidityToken;
        _approve(address(this), address(router), _amount);
        IMemeswapRouter(router).swapExactTokensForTokens(_amount, 0, path, address(this), block.timestamp);
    }

    /// @notice Burn tokens from the msg.sender's balance
    /// @param _amount Amount of tokens to be burned
    function burn(uint256 _amount) external {
        super._update(msg.sender, address(0), _amount);
        emit Burn(msg.sender, _amount);
    }

    /// @notice Add liquidity to the swap pair
    /// @param _liquidityToken Address of the liquidity token
    /// @param _tokenAmount Amount of original tokens
    /// @param _ethAmount Amount of liquidity token
    function _addLiquidity(address _liquidityToken, uint256 _tokenAmount, uint256 _ethAmount) private {
        _approve(address(this), router, _tokenAmount);
        ERC20(_liquidityToken).approve(router, _ethAmount);
        IMemeswapRouter(router).addLiquidity(
            address(this), _liquidityToken, _tokenAmount, _ethAmount, 0, 0, address(this), block.timestamp
        );
    }

    /// @notice Get the maximum allowed amount per swap
    /// @return uint256 Maximum amount of tokens permitted per swap
    function maxPerSwap() public view returns (uint256) {
        uint256 passed = block.timestamp - initializedAt;
        uint256 percentage = passed > 3600 ? 1000 : (passed * 10) / 36;
        percentage = percentage == 0 ? 1 : percentage;
        return (totalSupply() * percentage) / 1000;
    }

    /// @notice Check if the address is the owner during transaction
    /// @param _from Address sending the tokens
    /// @param _to Address receiving the tokens
    /// @return bool True if either address is the owner
    function _isOwner(address _from, address _to) private view returns (bool) {
        return _from == owner() || _to == owner();
    }

    /// @notice Check if the address is part of the protocol during transaction
    /// @param _from Address sending the tokens
    /// @param _to Address receiving the tokens
    /// @return bool True if either address is part of the protocol
    function _isProtocol(address _from, address _to) private view returns (bool) {
        return _from == tokenFactory || _to == tokenFactory || _to == IMemeswapFactory(factory).feeTo()
            || _from == IMemeswapFactory(factory).feeTo();
    }

    /// @notice Check if the address is the vault during transaction
    /// @param _vault Address to check
    /// @return bool True if the address is the vault
    function _isVault(address _vault) private view returns (bool) {
        return _vault == IMemeswapTokenFactory(tokenFactory).vault();
    }

    /// @notice Get the required wait time for swap based on elapsed time
    /// @return uint256 Required wait time in seconds
    function secondsNeeded() public view returns (uint256) {
        if (block.timestamp - initializedAt > 84600) return 0;
        return 30 - ((block.timestamp - initializedAt) / 2880);
    }

    function renounceOwnership() public view override onlyOwner {
        revert NOT_ALLOWED();
    }
}
