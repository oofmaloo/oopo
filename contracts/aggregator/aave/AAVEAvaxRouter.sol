// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;


import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ILendingPool} from './interfaces/ILendingPool.sol';
import {WadRayMath} from '../../libraries/math/WadRayMath.sol';

import {IRouter} from "../../interfaces/IRouter.sol";
import {IPoolAddressesProvider} from "../../interfaces/IPoolAddressesProvider.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "hardhat/console.sol";

/**
 * @title AaveAvaxRouter
 * Routers are designated for underlying/supplyToken vaults
 * @author Advias
 * @title Logic to bridge or use Anchor Vault
 * underlying/wrapped
 * Swap DAI to UST/aUST
 */
contract AAVEAvaxRouter is IRouter, AccessControl {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;

    bytes32 public constant CALLERS = keccak256("CALLERS");

    IPoolAddressesProvider private _addressesProvider;

    address public addressesProvider;

    address public lendingPool;
    address public aggregator;

    IERC20 private _token;
    uint256 private tokenDecimals;
    IERC20 private _underlying;
    uint256 private underlyingDecimals;

    constructor(
        address addressesProvider_,
        address underlying, // asset that gets sent in to router
        address token,
        address lendingPool_
    ) {
        addressesProvider = addressesProvider_;
        _addressesProvider = IPoolAddressesProvider(addressesProvider_);
        _token = IERC20(token);
        _underlying = IERC20(underlying);
        lendingPool = lendingPool_;
        IERC20(underlying).safeIncreaseAllowance(lendingPool_, type(uint256).max);
        _grantRole(CALLERS, address(0));
    }

    function setLendingPool(address lendingPool_) external onlyPoolAdmin {
        lendingPool = lendingPool_;
        IERC20(address(_underlying)).safeIncreaseAllowance(lendingPool_, type(uint256).max);
    }

    modifier onlyPoolAdmin() {
        require(msg.sender == _addressesProvider.getPoolAdmin());
        _;
    }

    modifier onlyPool() {
        require(msg.sender == _addressesProvider.getPool());
        _;
    }

    /**
     * @dev Return if an address can call role based functions
     */
    function getCaller(address caller_) external view returns (bool) {
        return hasRole(CALLERS, caller_);
    }

    /**
     * @dev Set aggregator as caller
     */
    function setCaller(address caller_) external onlyPoolAdmin {
        _grantRole(CALLERS, caller_);
    }

    /**
     * @dev Remove an aggregator
     */
    function removeCaller(address caller_) external onlyPoolAdmin {
        revokeRole(CALLERS, caller_);
    }

    /**
     * @dev Deposits underlying to a protocol
     * @param asset Asset to transfer in
     * @param _amount Amount to transfer in
     * @param _minAmountOut Min amount our on swap
     * @param to Address to send wrapped to
     */
    function deposit(address asset, uint256 _amount, uint256 _minAmountOut, address to) public override onlyRole(CALLERS) returns (uint256) {
        _underlying.safeTransferFrom(msg.sender, address(this), _amount);
        ILendingPool(lendingPool).deposit(
            asset,
            _amount,
            msg.sender,
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
    function redeem(address asset, uint256 _amount, address to, address _outAsset) public override onlyRole(CALLERS) returns (uint256) {
        _token.safeTransferFrom(msg.sender, address(this), _amount);
        // uint256 finalRedeemed = ILendingPool(lendingPool).withdraw(
        //     asset,
        //     _amount,
        //     to
        // );

        (bool success, bytes memory result) = lendingPool.call(
            abi.encodeWithSignature("withdraw(address,uint256,address)",asset,_amount,to)
        );
        uint256 finalRedeemed = abi.decode(result, (uint256));
        console.log("router finalRedeemed", finalRedeemed);
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
    function getBalance(address account) public override view returns (uint256) {
        return _token.balanceOf(account);
    }

    function underlying() public view override returns (address) {
        return address(_underlying);
    }

    function token() public view override returns (address) {
        return address(_token);
    }


}
