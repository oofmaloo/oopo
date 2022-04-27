// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;


import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PercentageMath} from '../libraries/math/PercentageMath.sol';
import {WadRayMath} from '../libraries/math/WadRayMath.sol';


import {IRouter} from "../interfaces/IRouter.sol";
import {IAggregator} from "../interfaces/IAggregator.sol";

import "hardhat/console.sol";

/**
 * @title BaseAggregator
 * Aggregator is the main point of contact on avasTokens
 * The Aggregator contacts the Router, the Router is the main point of contact to outside protocols
 * @author Advias
 */
contract AVAXAggregator is IAggregator {
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
        address[] memory routers
    ) internal {
        addRoutersData(routers);
    }

    function addRoutersData(
        address[] memory routers
    ) public onlyPoolAdmin {
        for (uint256 i = 0; i < routers.length; i++) {
        	address underlying = IRouter(routers[i]).underlying();
            require(underlying != address(0), "Error: Token zero");
			address token = IRouter(routers[i]).token();
            require(token != address(0), "Error: Token zero");
            addRouterData(underlying, routers[i], token);
        }
    }

    /**
     * @dev Adds underlying asset to accept
     * Maybe add a vault to store balances
     **/
    function addRouterData(
        address asset,
        address router,
        address token
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
        address[] memory routers, // router address for above asset
        address underlying // asset that gets sent in to router
    ) {
        _underlying = IERC20(underlying);
        underlyingDecimals = IERC20Metadata(underlying).decimals();
        addressesProvider = IPoolAddressesProvider(_addressesProvider);
        addRoutersData(routers);
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

    function setToken(address token_) external override onlyPoolAdmin {
        token = token_;
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
    function accrueSim() public view override onlyPool returns (uint256, uint256) {
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

        // if no increase, return previous values
        //      this is possible is protocols arent updated before our called block 
        if (routerBalance == _lastUpdatedBalance) {
            return (lastUpdatedBalance, routerBalance);
        }

        //void
        // uint256 _vault = newBalance.sub(lastUpdatedBalance).percentMul(discountRate);
        // redeem(address(_underlying), vault, vault, address(_underlying));

        return (
            routerBalance,
            _lastUpdatedBalance
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

        uint256 routerBalance = getBalance();

        lastUpdatedBalance = routerBalance;

        // if no increase, return previous values
        //      this is possible is protocols arent updated before our called block 
        if (routerBalance == _lastUpdatedBalance) {
            return (lastUpdatedBalance, routerBalance);
        }

        //void
        // uint256 _vault = newBalance.sub(lastUpdatedBalance).percentMul(discountRate);
        // redeem(address(_underlying), _vault, vault, address(_underlying));

        return (
            routerBalance,
            _lastUpdatedBalance
        );

    }

    function getBalance() internal returns (uint256) {
        uint256 totalRoutedBalance;
        uint256[] memory rates = new uint256[](routersDataCount);
        for (uint256 i = 0; i < routersDataCount; i++) {
            RouterData storage routerData = routersData[routersDataList[i]];

            uint256 balance = IRouter(routerData.router).getBalance(address(this));

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

            uint256 balance = IRouter(routerData.router).getBalance(address(this));

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
        // RouterData storage routerData = routersData[asset];
        RouterData storage routerData = routersData[routersDataList[0]];
        require(routerData.active, "Error: Router Platform on");
        // here _amount and amount are using the same decimals
        // _amount assumes it is the DAI decimal count
        // if it is now, we swap and the swap will return the correct amount swapped for adj for decimals
        _underlying.safeTransferFrom(msg.sender, address(this), _amount);

        // decimals will update if swapped
        // any bridge routers will assume fees in their router, not here
        uint256 amountBack = IRouter(routerData.router).deposit(
            routerData.asset,
            _amount,
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
     * @param asset Amount of underlying to redeem
     * @param _amount Address to send underlying to, usually avasToken or user ir account
     * @param to Asset to have anchor swap to
     * 
     * note: for aggregation routers, redeem will for loop all wrapped tokens, redeem, and swap is needed
     */
    function redeem(address asset, uint256 _amount, address to) public override returns (uint256) {
        // RouterData storage routerData = routersData[asset];
        RouterData storage routerData = routersData[routersDataList[0]];
        require(routerData.active, "Error: Router Platform on");

        (bool success,) = routerData.router.delegatecall(
            abi.encodeWithSignature("redeem(address,uint256,address,address)",routerData.asset,_amount,to,address(_underlying))
        );


        uint256 amountBack = IRouter(routerData.router).redeem(
            routerData.asset,
            _amount,
            to,
            address(_underlying)
        );

        lastUpdatedBalance = getBalance();

        return amountBack;
    }

    // function setVault(uint256 vault_) external onlyPoolAdmin {
    //     require(discountRate_ != address(0), Errors.CT_INVALID_MINT_AMOUNT);
    //     vault = vault_;
    // }
}
