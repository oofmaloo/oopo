// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PercentageMath} from '../math/PercentageMath.sol';


import {IBaseRouter} from "../interfaces/IBaseRouter.sol";
import "hardhat/console.sol";

/**
 * @title BaseAggregator
 * Aggregator is the main point of contact on avasTokens
 * The Aggregator contacts the Router, the Router is the main point of contact to outside protocols
 * @author Advias
 */
contract BaseAggregator is IBaseAggregator {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    IPoolAddressesProvider private addressesProvider;

    address public token;
    uint256 private vault;

    IERC20 private _underlying;
    uint256 private underlyingDecimals;

    uint256 private lastUpdatedBalance;

    uint256 constant PERCENTAGE_FACTOR = 1e4;

    struct RouterData {
    	address router;
    	address asset;
    	address token;
    	uint256 assetDecimals;
    	uint256 tokenDecimals;
        uint256 discountRate;
    	bool active;
    }

	uint256 internal routersDataCount;
    mapping(uint256 => address) public routersDataList;
    mapping(address => RouterData) public routersData;

    function _addRoutersData(
        address[] memory assets, 
        address[] memory routers,
    ) internal {
        addPlatformTokens(assets, routers);
    }

    function addRoutersData(
        address[] memory assets, 
        address[] memory routers,
    ) public override onlyPoolAdmin {
        for (uint256 i = 0; i < routers.length; i++) {
        	address underlying = IRouter(routers[i]).underlying();
			address token = IRouter(routers[i]).token();
            require(assets[i] == underlying, "Error: Token zero");
            require(token != address(0), "Error: Token zero");
            addPlatformToken(assets[i], routers[i], tokens[i]);
        }
    }

    /**
     * @dev Adds underlying asset to accept
     **/
    function addRouterData(
        address asset,
        address router,
        address token,
        address vault_
    ) public onlyPoolAdmin {
        RouterData storage routerData = routersData[router];
        uint256 assetDecimals = IERC20Metadata(asset).decimals();
        uint256 tokenDecimals = IERC20Metadata(token).decimals();
        routerData.asset = asset;
        routerData.assetDecimals = assetDecimals;
        routerData.token = token;
        routerData.tokenDecimals = tokenDecimals;
        routerData.router = router;
        routerData.active = true;
        vault = vault_;
        addRouterDataToListInternal(router);
        IERC20(asset).safeIncreaseAllowance(address(router), type(uint256).max);
        IERC20(token).safeIncreaseAllowance(address(router), type(uint256).max);
    }

    function addRouterDataToListInternal(address router) internal {
        uint256 _routersDataCount = routersDataCount;
        bool routerAlreadyAdded = false;
        for (uint256 i = 0; i < _routersDataCount; i++)
            if (routersDataList[i] == router) {
                routerAlreadyAdded = true;
            }
        if (!routerAlreadyAdded) {
            routersDataList[routersDataCount] = router;
            routersDataCount = _routersDataCount + 1;
        }
    }

    constructor(
        address _addressesProvider,
        address[] memory assets, // asset of aggregated router
        address[] memory routers, // router address for above asset
        address underlying, // asset that gets sent in to router
        address token_
    ) {
        _underlying = IERC20(underlying);
        underlyingDecimals = IERC20Metadata(underlying).decimals();
        addressesProvider = IPoolAddressesProvider(_addressesProvider);
        addPlatformTokens(assets, routers, tokens);
        lastUpdatedTimestamp = block.timestamp;
        token = token_;
    }

    modifier onlyPoolAdmin() {
        require(msg.sender == addressesProvider.getPoolAdmin());
        _;
    }

    modifier onlyToken() {
        require(msg.sender == token);
        _;
    }

    modifier onlyPool() {
        require(msg.sender == addressesProvider.getPool());
        _;
    }

    function _underlyingAsset() public view override returns (address) {
        return address(_underlying);
    }

    function _token() public view override returns (address) {
        return token;
    }

    /**
     * @dev Simulation - not accurate - way to get balance without tx query
     */
    function accrueSim() public override onlyPool returns (uint256, uint256) {
        // if there are no router deposits
        //      exchange rate doens't require increasing
        //      interest rate is required for debt interest rate
        if (lastUpdatedBalance == 0) {
            return (0, 0);
        }

        // see how much router accrued
        uint256 _lastUpdatedBalance = lastUpdatedBalance;
        // get updated routed balance
        uint256 routerBalance = getBalance();

        // if no increase, return previous values
        //      this is possible is protocols arent updated before our called block 
        if (routerBalance == _lastUpdatedBalance) {
            return (lastUpdatedBalance, routerBalance);
        }

        //void
        uint256 _vault = newBalance.sub(lastUpdatedBalance).percentMul(discountRate);
        // redeem(address(_underlying), vault, vault, address(_underlying));

        return (
            newBalance.sub(vault),
            lastUpdatedBalance
        );
    }

    /**
     * @dev Get accurate balance of tokens and update state
     */
    function accrue() public override onlyPool returns (uint256, uint256) {
        // if there are no router deposits
        //      exchange rate doens't require increasing
        //      interest rate is required for debt interest rate
        if (lastUpdatedBalance == 0) {
            return (0, 0);
        }

        // see how much router accrued
        uint256 _lastUpdatedBalance = lastUpdatedBalance;
        // get updated routed balance

        uint256 routerBalance = getBalanceSim();

        lastUpdatedBalance = routerBalance;

        // if no increase, return previous values
        //      this is possible is protocols arent updated before our called block 
        if (routerBalance == _lastUpdatedBalance) {
            return (lastUpdatedBalance, routerBalance);
        }

        //void
        uint256 _vault = newBalance.sub(lastUpdatedBalance).percentMul(discountRate);
        redeem(address(_underlying), _vault, vault, address(_underlying));

        return (
            newBalance,
            lastUpdatedBalance
        );

    }

    function getBalance() internal returns (uint256) {
        uint256 totalRoutedBalance;
        uint256[] memory rates = new uint256[](routersDataCount);
        for (uint256 i = 0; i < routersDataCount; i++) {
            RouterData storage routerData = routersData[routersDataList[i]];

            uint256 balance = IBaseRouter(routerData.router).getBalance(address(this));

            if (routerData.assetDecimals != underlyingDecimals) {
                uint256 difference;
                if (routerData.assetDecimals > underlyingDecimals) {
                    difference = routerData.assetDecimals.sub(underlyingDecimals);
                    totalRoutedBalance += balance.div(10**difference);
                } else {
                    difference = underlyingDecimals.sub(routerData.assetDecimals);
                    totalRoutedBalance += balance.mul(10**difference);
                }
            } else {
                totalRoutedBalance += balance;
            }
        }
        return totalRoutedBalance;
    }

    function getBalanceSim() internal view returns (uint256) {
        uint256 totalRoutedBalance;
        uint256[] memory rates = new uint256[](routersDataCount);
        for (uint256 i = 0; i < routersDataCount; i++) {
            RouterData storage routerData = routersData[routersDataList[i]];

            uint256 balance = IBaseRouter(routerData.router).getBalance(address(this));

            if (routerData.assetDecimals != underlyingDecimals) {
                uint256 difference;
                if (routerData.assetDecimals > underlyingDecimals) {
                    difference = routerData.assetDecimals.sub(underlyingDecimals);
                    totalRoutedBalance += balance.div(10**difference);
                } else {
                    difference = underlyingDecimals.sub(routerData.assetDecimals);
                    totalRoutedBalance += balance.mul(10**difference);
                }
            } else {
                totalRoutedBalance += balance;
            }
        }
        return totalRoutedBalance;
    }


    /**
     * @dev Deposits underlying to Anchor or Vault and returns wrapped to `to`
     * @param asset Asset to transfer in
     * @param _amount Amount to transfer in
     * @param _minAmountOut Min amount our on swap
     * @param to Address to send wrapped to
     */
    function deposit(address asset, uint256 _amount, uint256 _minAmountOut, address to) public override returns (uint256) {
        RouterData storage routerData = routersData[asset];
        require(routerData.active, "Error: Router Platform on");
        // here _amount and amount are using the same decimals
        // _amount assumes it is the DAI decimal count
        // if it is now, we swap and the swap will return the correct amount swapped for adj for decimals
        _underlying.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 amount = _amount;

        // decimals will update if swapped
        // any bridge routers will assume fees in their router, not here
        uint256 amountBack = IBaseRouter(routerData.router).deposit(
            routerData.asset,
            amount,
            _minAmountOut,
            address(this)
        );

        uint256 _lastUpdatedBalance = lastUpdatedBalance;
        lastUpdatedBalance = getBalance();
        amountBack = lastUpdatedBalance.sub(_lastUpdatedBalance);

        return amountBack;
    }

   
    /**
     * @dev Deposits wrapped to Anchor or Vault and returns underlying to `to`
     * @param _amount Amount of underlying to redeem
     * @param to Address to send underlying to, usually avasToken or user ir account
     * @param _outAsset Asset to have anchor swap to
     * 
     * note: for aggregation routers, redeem will for loop all wrapped tokens, redeem, and swap is needed
     */
    function redeem(address asset, uint256 _amount, address to, address _outAsset) public override returns (uint256) {
        RouterData storage routerData = routersData[asset];
        require(routerData.active, "Error: Router Platform on");

        IBaseRouter(routerData.router).redeem(
            routerData.asset,
            amount.mul(10**routerData.decimals).div(10**underlyingDecimals),
            to,
            address(_underlying)
        );

        lastUpdatedBalance = getBalance();

        return amountBack;
    }

    function setVault(uint256 vault_) external onlyPoolAdmin {
        require(discountRate_ != address(0), Errors.CT_INVALID_MINT_AMOUNT);
        vault = vault_;
    }

    // 0 is zero
    function setDiscountRate(uint256 discountRate_) external onlyPoolAdmin {
        require(discountRate_ <= 5e3, Errors.CT_INVALID_MINT_AMOUNT);
        discountRate = discountRate_;
    }

}
