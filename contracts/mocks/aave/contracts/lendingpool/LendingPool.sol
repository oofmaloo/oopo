// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";


import {ILendingPoolAddressesProvider} from '../../interfaces/ILendingPoolAddressesProvider.sol';
import {IAToken} from '../../interfaces/IAToken.sol';
import {ILendingPool} from '../../interfaces/ILendingPool.sol';

import {WadRayMath} from '../libraries/math/WadRayMath.sol';
import {PercentageMath} from '../libraries/math/PercentageMath.sol';
import {MathUtils} from '../libraries/math/MathUtils.sol';

import {MockReserveLogic} from '../libraries/logic/MockReserveLogic.sol';
import {DataTypes} from '../libraries/types/DataTypes.sol';

import {LendingPoolStorage} from './LendingPoolStorage.sol';

import "hardhat/console.sol";

/**
 * @title LendingPool contract
 * @dev Main point of interaction with an Aave protocol's market
 * - Users can:
 *   # Deposit
 *   # Withdraw
 *   # Borrow
 *   # Repay
 *   # Swap their loans between variable and stable rate
 *   # Enable/disable their deposits as collateral rebalance stable rate borrow positions
 *   # Liquidate positions
 *   # Execute Flash Loans
 * - To be covered by a proxy contract, owned by the LendingPoolAddressesProvider of the specific market
 * - All admin functions are callable by the LendingPoolConfigurator contract defined also in the
 *   LendingPoolAddressesProvider
 * @author Aave
 **/
contract LendingPool is ILendingPool, LendingPoolStorage {
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using SafeERC20 for IERC20;

  using MockReserveLogic for DataTypes.ReserveData;

  uint256 public currentLiquidityRate = 0.1 * 1e27;

  constructor(ILendingPoolAddressesProvider provider) {
    _addressesProvider = provider;
    _maxNumberOfReserves = 256;
  }

  /**
   * @dev Deposits an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
   * - E.g. User deposits 100 USDC and gets in return 100 aUSDC
   * @param asset The address of the underlying asset to deposit
   * @param amount The amount to be deposited
   * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
   *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
   *   is a different wallet
   * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
   *   0 if the action is executed directly by the user, without any middle-man
   **/
  function deposit(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint16 referralCode
  ) external override {
    DataTypes.ReserveData storage reserve = _reserves[asset];

    require(amount != 0, "Errors.INVALID_AMOUNT");

    address aToken = reserve.aTokenAddress;

    uint40 lastUpdatedTimestamp = reserve.lastUpdateTimestamp;

    uint256 newLiquidityIndex = reserve.liquidityIndex;
    if (IAToken(aToken).scaledTotalSupply() > 0) {
      uint256 cumulatedLiquidityInterest =
        MathUtils.calculateLinearInterest(currentLiquidityRate, lastUpdatedTimestamp);
      newLiquidityIndex = cumulatedLiquidityInterest.rayMul(reserve.liquidityIndex);
      reserve.liquidityIndex = uint128(newLiquidityIndex);
    }

    IERC20(asset).safeTransferFrom(msg.sender, aToken, amount);

    IAToken(aToken).mint(onBehalfOf, amount, reserve.liquidityIndex);

    reserve.lastUpdateTimestamp = uint40(block.timestamp);

    console.log("pool minted balance now", IERC20(aToken).balanceOf(onBehalfOf));

    emit Deposit(asset, msg.sender, onBehalfOf, amount, referralCode);
  }

  /**
   * @dev Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
   * E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC
   * @param asset The address of the underlying asset to withdraw
   * @param amount The underlying amount to be withdrawn
   *   - Send the value type(uint256).max in order to withdraw the whole aToken balance
   * @param to Address that will receive the underlying, same as msg.sender if the user
   *   wants to receive it on his own wallet, or a different address if the beneficiary is a
   *   different wallet
   * @return The final amount withdrawn
   **/
  function withdraw(
    address asset,
    uint256 amount,
    address to
  ) external override returns (uint256) {
    DataTypes.ReserveData storage reserve = _reserves[asset];

    address aToken = reserve.aTokenAddress;

    uint256 userBalance = IAToken(aToken).balanceOf(msg.sender);

    uint256 amountToWithdraw = amount;

    if (amount == type(uint256).max) {
      amountToWithdraw = userBalance;
    }

    require(amount != 0, "Errors.INVALID_AMOUNT");
    require(amountToWithdraw <= userBalance, "Errors.NOT_ENOUGH_AVAILABLE_USER_BALANCE");

    uint40 lastUpdatedTimestamp = reserve.lastUpdateTimestamp;

    uint256 newLiquidityIndex = reserve.liquidityIndex;
    if (IAToken(aToken).scaledTotalSupply() > 0) {
      uint256 cumulatedLiquidityInterest =
        MathUtils.calculateLinearInterest(currentLiquidityRate, lastUpdatedTimestamp);
      newLiquidityIndex = cumulatedLiquidityInterest.rayMul(reserve.liquidityIndex);
      reserve.liquidityIndex = uint128(newLiquidityIndex);
    }

    IAToken(aToken).burn(msg.sender, to, amountToWithdraw, reserve.liquidityIndex);

    emit Withdraw(asset, msg.sender, to, amountToWithdraw);

    reserve.lastUpdateTimestamp = uint40(block.timestamp);

    return amountToWithdraw;
  }

  function finalizeTransfer(
    address asset,
    address from,
    address to,
    uint256 amount,
    uint256 balanceFromBefore,
    uint256 balanceToBefore
  ) external override {
    require(msg.sender == _reserves[asset].aTokenAddress, "Errors.LP_CALLER_MUST_BE_AN_ATOKEN");
  }

  function getReserveNormalizedIncome(address asset) external view override returns (uint256) {
    return _reserves[asset].getNormalizedIncome();
  }


  function getAToken(address asset) external view returns (address) {
    return _reserves[asset].aTokenAddress;
  }

  /**
   * @dev Initializes a reserve, activating it, assigning an aToken and  tokens and an
   * interest rate strategy
   * - Only callable by the LendingPoolConfigurator contract
   * @param asset The address of the underlying asset of the reserve
   * @param aTokenAddress The address of the aToken that will be assigned to the reserve
   **/
  function initReserve(
    address asset,
    address aTokenAddress
  ) external override {
    require(Address.isContract(asset), "Errors.LP_NOT_CONTRACT");
    console.log("initReserve aTokenAddress", aTokenAddress);
    _reserves[asset].init(
      aTokenAddress
    );

    _addReserveToList(asset);
  }

  function _addReserveToList(address asset) internal {
    uint256 reservesCount = _reservesCount;

    require(reservesCount < _maxNumberOfReserves, "Errors.LP_NO_MORE_RESERVES_ALLOWED");

    bool reserveAlreadyAdded = _reserves[asset].id != 0 || _reservesList[0] == asset;

    if (!reserveAlreadyAdded) {
      _reserves[asset].id = uint8(reservesCount);
      _reservesList[reservesCount] = asset;

      _reservesCount = reservesCount + 1;
    }
  }
}