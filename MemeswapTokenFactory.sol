// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MemeswapLibrary} from "./libraries/MemeswapLibrary.sol";
import {MemeswapToken} from "./MemeswapToken.sol";
import {IMemeswapVault} from "./interfaces/IMemeswapVault.sol";
import {IMemeswapFactory} from "./interfaces/IMemeswapFactory.sol";
import {IMemeswapRouter} from "./interfaces/IMemeswapRouter.sol";
import {IMemeswapLock} from "./interfaces/IMemeswapLock.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IWETH} from "./interfaces/IWETH.sol";

// @title MemeswapTokenFactory
// @author Memeswap
// @notice This contract is for creating MemeswapToken contracts, and renting liquidity for them.
// @dev Vault contracts are deployed separately and added to this contract by team.
contract MemeswapTokenFactory is Ownable {
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

    address public immutable router;
    address public immutable factory;
    address public bmf;
    uint256 public maxTax;
    mapping(address => bool) public isMemeswapToken;
    mapping(address token => address deployer) public deployers;
    address public vault;
    bool public initialized;
    uint256 public minLiquidity;
    uint256 public maxLiquidity;
    uint256[] public allowedDurations = [1 days];

    /// @notice Emitted when a new Memeswap token is deployed.
    /// @param deployer Address of the deployer.
    /// @param token Address of the deployed Memeswap token.
    /// @param totalSupply Total supply of the deployed token.
    /// @param buybackMode The buyback mode of the token.
    /// @param buyTax The buy tax for the token.
    /// @param sellTax The sell tax for the token.
    /// @param ownersCut The owner's cut from taxes.
    /// @param urls Array of URLs for the token.
    event Deployed(
        address indexed deployer,
        address indexed token,
        uint256 totalSupply,
        uint256 buybackMode,
        uint256 buyTax,
        uint256 sellTax,
        uint256 ownersCut,
        string[] urls
    );

    /// @notice Emitted when a new token launch is performed.
    /// @param deployer Address of the deployer.
    /// @param token Address of the deployed Memeswap token.
    /// @param liquidityToken Address of the liquidity token.
    /// @param totalSupply Total supply of the deployed token.
    /// @param fee Fee for the launch.
    /// @param amount Amount of liquidity provided.
    event NewLaunch(
        address indexed deployer,
        address indexed token,
        address indexed liquidityToken,
        uint256 totalSupply,
        uint256 fee,
        uint256 amount
    );

    /// @notice Emitted when the maximum tax is updated.
    /// @param maxTax New maximum tax.
    event MaxTaxUpdated(uint256 maxTax);

    /// @notice Emitted when the BMF address is set.
    /// @param bmf Address of the BMF.
    event BMFSet(address bmf);

    error FORBIDDEN();
    error INVALID_BUYBACK_MODE();
    error INVALID_SUPPLY();
    error TOO_MANY_URLS();
    error WRONG_TAXES();
    error WRONG_FEE();
    error VAULT_DRY();
    error SLIPPAGE();
    error ALREADY_INITIALIZED();
    error NOT_INITIALIZED();
    error LIQUIDITY_TOO_LOW();
    error LIQUIDITY_TOO_HIGH();
    error BMF_NOT_SET();
    error NOT_ALLOWED();

    /// @notice Constructor to initialize the MemeswapTokenFactory.
    /// @param _router Address of the Memeswap router.
    /// @param _factory Address of the Memeswap factory.
    constructor(address _router, address _factory, address _bmf) Ownable(msg.sender) {
        router = _router;
        factory = _factory;
        bmf = _bmf;
        maxTax = 200;
        minLiquidity = 0.5 ether;
        maxLiquidity = 0.7 ether;
    }

    /// @notice Initialize the factory with the vault address.
    /// @param _vault Address of the vault.
    function initialize(address _vault) external onlyOwner {
        if (initialized) revert ALREADY_INITIALIZED();
        initialized = true;
        vault = _vault;
    }

    /// @notice Set allowed durations for locks.
    /// @param _durations Array of allowed durations in seconds.
    function setAllowedDurations(uint256[] memory _durations) external onlyOwner {
        allowedDurations = _durations;
    }

    /// @notice Get all allowed durations.
    /// @return Array of allowed durations in seconds.
    function getAllowedDurations() public view returns (uint256[] memory) {
        return allowedDurations;
    }

    /// @notice Check if a duration is allowed.
    /// @param _duration Duration to check.
    /// @return True if the duration is allowed, false otherwise.
    function isAllowedDuration(uint256 _duration) public view returns (bool) {
        for (uint256 i; i < allowedDurations.length; ++i) {
            if (allowedDurations[i] == _duration) {
                return true;
            }
        }
        return false;
    }

    /// @notice Set the range for the liquidity.
    /// @param _min Minimum liquidity.
    /// @param _max Maximum liquidity.
    function setLiquidityRange(uint256 _min, uint256 _max) external onlyOwner {
        minLiquidity = _min;
        maxLiquidity = _max;
    }

    /// @notice Set the maximum tax value.
    /// @param _maxTax New maximum tax value.
    function setMaxTax(uint256 _maxTax) external onlyOwner {
        if (_maxTax > 999) revert FORBIDDEN();
        maxTax = _maxTax;
        emit MaxTaxUpdated(_maxTax);
    }

    function setBMF(address _bmf) external onlyOwner {
        bmf = _bmf;
        emit BMFSet(_bmf);
    }

    /// @notice Launch a new Memeswap token.
    /// @param _params Launch parameters.
    /// @return token Address of the deployed token.
    /// @return liquidity Amount of liquidity provided.
    function launch(LaunchParams calldata _params) external payable returns (address token, uint256 liquidity) {
        if (!initialized) revert NOT_INITIALIZED();
        if (msg.value < _params.buyAmount) revert WRONG_FEE();
        uint256 price = msg.value - _params.buyAmount;
        if (price <= 0) revert WRONG_FEE();
        token = _deploy(_params.name, _params.symbol, _params.totalSupply, _params.taxes, _params.urls, address(this));
        address weth = IMemeswapRouter(router).WETH();
        uint256 amount = IMemeswapVault(vault).getAmountForPrice(price, _params.duration);
        if (!isAllowedDuration(_params.duration)) revert FORBIDDEN();
        if (amount < _params.minAmount) revert SLIPPAGE();
        if (amount < minLiquidity) revert LIQUIDITY_TOO_LOW();
        if (amount > maxLiquidity) revert LIQUIDITY_TOO_HIGH();
        if (!IMemeswapVault(vault).canRent(amount)) revert VAULT_DRY();
        IWETH(payable(weth)).deposit{value: price}();
        IERC20(weth).transfer(vault, price);
        IERC20(token).approve(router, _params.totalSupply);
        IERC20(weth).approve(router, amount);
        IMemeswapVault(vault).rent(
            MemeswapLibrary.pairFor(factory, token, weth),
            token,
            amount,
            _params.duration,
            msg.sender,
            _params.pairToUnlock
        );
        (,, liquidity) = IMemeswapRouter(router).addLiquidity(
            token, weth, _params.totalSupply, amount, 0, 0, address(this), block.timestamp + 100
        );
        address pair = MemeswapLibrary.pairFor(factory, token, weth);
        address lock = IMemeswapFactory(factory).lock();
        MemeswapToken(token).initialize(pair);
        IERC20(pair).transfer(lock, liquidity);
        IMemeswapLock(lock).lock(pair, vault, _params.duration, liquidity);
        MemeswapToken(token).transferOwnership(msg.sender);
        emit NewLaunch(msg.sender, token, weth, _params.totalSupply, msg.value, amount);
        if (_params.buyAmount > 0) _swap(token, msg.sender, _params.buyAmount);
    }

    /// @notice Swap a specified amount of tokens.
    /// @param _token Address of the token to be swapped.
    /// @param _owner Address of the owner.
    /// @param _amount Amount to be swapped.
    function _swap(address _token, address _owner, uint256 _amount) internal {
        address[] memory path = new address[](2);
        path[0] = IMemeswapRouter(router).WETH();
        path[1] = _token;
        IMemeswapRouter(router).swapExactETHForTokens{value: _amount}(0, path, _owner, block.timestamp + 100);
    }

    /// @notice Deploys a new MemeswapToken contract.
    /// @dev Taxes should be an array of 4 values: buy tax, sell tax, transfer tax, and owner's cut.
    /// @dev URLs should be an array of 10 values. Used for metadata purposes only.
    /// @param _name Name of the token.
    /// @param _symbol Symbol of the token.
    /// @param _totalSupply Total supply of the token.
    /// @param _taxes Array of taxes in 1/1000 scale.
    /// @param _urls Array of URLs for the token.
    /// @param _to Address to which the token should be deployed.
    /// @return token Address of the deployed token.
    function _deploy(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint256[] calldata _taxes,
        string[] memory _urls,
        address _to
    ) private returns (address token) {
        if (_urls.length > 10) revert TOO_MANY_URLS();
        if (_taxes.length != 4) revert WRONG_TAXES();
        if (_taxes[0] > 1) revert INVALID_BUYBACK_MODE();
        if (_taxes[0] == 1 && bmf == address(0)) revert BMF_NOT_SET();
        if (_taxes[1] > maxTax || _taxes[2] > maxTax || _taxes[3] > 1000) {
            revert FORBIDDEN();
        }
        if (_totalSupply == 0) revert INVALID_SUPPLY();
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, block.chainid));
        token = address(
            (new MemeswapToken){salt: salt}(
                _name, _symbol, _totalSupply, _taxes[0], _taxes[1], _taxes[2], _taxes[3], router, _to, _urls
            )
        );
        isMemeswapToken[token] = true;
        deployers[token] = msg.sender;
        emit Deployed(msg.sender, token, _totalSupply, _taxes[0], _taxes[1], _taxes[2], _taxes[3], _urls);
    }

    function renounceOwnership() public view override onlyOwner {
        revert NOT_ALLOWED();
    }
}
