// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ILendingPool} from './ILendingPool.sol';

import {IBaseRouter} from "../interfaces/IRouter.sol";

import "hardhat/console.sol";

/**
 * @title RouterDAI
 * Routers are designated for underlying/supplyToken vaults
 * @author Advias
 * @title Logic to bridge or use Anchor Vault
 * underlying/wrapped
 * Swap DAI to UST/aUST
 */
contract BaseRouter is IBaseRouter {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IPoolAddressesProvider private addressesProvider;

    address public addressesProvider;

    address public lendingPool;
    address public aggregator;

    IERC20 private _token;
    uint256 private tokenDecimals;
    IERC20 private _underlying;
    uint256 private underlyingDecimals;

    constructor(
        address underlying, // asset that gets sent in to router
        address token,
        address aggregator_
    ) {
        _token = IERC20(token);
        _underlying = IERC20(underlying);
        aggregator = aggregator_;
    }

    function setLendingPool(address lendingPool_) {
        lendingPool = lendingPool_;
    }

    modifier onlyPoolAdmin() {
        require(msg.sender == addressesProvider.getPoolAdmin());
        _;
    }

    modifier onlyPool() {
        require(msg.sender == addressesProvider.getPool());
        _;
    }

    modifier onlyAggregator() {
        require(msg.sender == aggregator);
        _;
    }

    function getAggregator(address aggregator_) external onlyPoolAdmin {
        aggregator = aggregator_;
    }


    /**
     * @dev Deposits underlying to a protocol
     * @param asset Asset to transfer in
     * @param _amount Amount to transfer in
     * @param _minAmountOut Min amount our on swap
     * @param to Address to send wrapped to
     */
    function deposit(address asset, uint256 _amount, uint256 _minAmountOut, address to) public override onlyAggregator returns (uint256) {
        _underlying.safeTransferFrom(msg.sender, address(this), _amount);
        ILendingPool(lendingPool).deposit(
            asset
            _amount
            aggregator
            0
        );
        return 0;
    }

    /**
     * @dev Deposits wrapped to Anchor or Vault and returns underlying to `to`
     * @param _amount Amount underlying to transfer in
     * @param to Address to send underlying to, usually avasToken or user ir account
     * @param _outAsset Asset to have anchor swap to
     * 
     * note: for aggregation routers, redeem will for loop all wrapped tokens, redeem, and swap is needed
     */
    function redeem(address asset, uint256 _amount, address to, address _outAsset) public override onlyAggregator returns (uint256) {
        _token.safeTransferFrom(msg.sender, address(this), _amount.rayDiv(getExchangeRate()));
        uint256 finalRedeemed = ILendingPool(lendingPool).withdraw(
            asset,
            _amount,
            to
        );
        return finalRedeemed;
    }

    function getExchangeRate() internal view returns (uint256) {
        return ILendingPool(lendingPool).getReserveNormalizedIncome(underlying());
    }

    /**
     * @dev Return underlying asset balance
     * - We run this here in case a protocol has unmatched decimals between their receipt token and underlying
     * - As well as in case balanceOf does not return balance, but the scaled instead
     * @param account Amount scaled to transfer in
     */
    function getBalance(address account) public override returns (uint256) {
        return _token.balanceOf(account);
    }

    function underlying() public override returns (uint256) {
        return address(_underlying);
    }

    function token() public override returns (uint256) {
        return address(_token);
    }


}
