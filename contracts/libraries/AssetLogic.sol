// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {SafeMath} from '../../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {IERC20} from '../../../dependencies/openzeppelin/contracts/IERC20.sol';
import {SafeERC20} from '../../../dependencies/openzeppelin/contracts/SafeERC20.sol';
import {IAToken} from '../../../interfaces/IAToken.sol';
import {IVariableDebtToken} from '../../../interfaces/IVariableDebtToken.sol';
import {IReserveInterestRateStrategy} from '../../../interfaces/IReserveInterestRateStrategy.sol';
import {ReserveConfiguration} from '../configuration/ReserveConfiguration.sol';
import {MathUtils} from '../math/MathUtils.sol';
import {WadRayMath} from '../math/WadRayMath.sol';
import {PercentageMath} from '../math/PercentageMath.sol';
import {Errors} from '../helpers/Errors.sol';
import {DataTypes} from '../types/DataTypes.sol';

/**
 * @title ReserveLogic library
 * @author Aave
 * @notice Implements the logic to update the reserves state
 */
library ReserveLogic {
	using SafeMath for uint256;
	using WadRayMath for uint256;
	using PercentageMath for uint256;
	using SafeERC20 for IERC20;

	/**
	* @dev Emitted when the state of a reserve is updated
	* @param asset The address of the underlying asset of the reserve
	* @param liquidityRate The new liquidity rate
	* @param variableBorrowRate The new variable borrow rate
	* @param liquidityIndex The new liquidity index
	* @param variableBorrowIndex The new variable borrow index
	**/
	event ReserveDataUpdated(
		address indexed asset,
		uint256 liquidityRate,
		uint256 variableBorrowRate,
		uint256 liquidityIndex,
		uint256 variableBorrowIndex
	);

	using ReserveLogic for DataTypes.ReserveData;
	using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

	/**
	* @dev Returns the ongoing normalized income for the reserve
	* A value of 1e27 means there is no income. As time passes, the income is accrued
	* A value of 2*1e27 means for each unit of asset one unit of income has been accrued
	* @param reserve The reserve object
	* @return the normalized income. expressed in ray
	**/
	function getNormalizedIncome(DataTypes.ReserveData storage reserve)
		internal
		view
		returns (uint256)
	{
		///
		/// aggregator
		///
		(
			uint256 newAggregatorBalance,
			uint256 lastAggregatorUpdatedBalance
		) = IBaseAggregator(reserve.aggregator).accrueSim();

		uint256 aggregatorAmountAccrued = newAggregatorBalance.sub(lastAggregatorUpdatedBalance);

		if (aggregatorAmountAccrued == 0) {
			return reserve.liquidityIndex;
		}

		uint256 lastAvasTokenTotalSupply = IAvasToken(reserve.avasTokenAddress).scaledTotalSupply().rayMul(reserve.liquidityIndex);

		uint256 mintToTreasuryAmount;
		if (reserve.reserveFactor > 0) {
			mintToTreasuryAmount = aggregatorAmountAccrued.percentMul(reserve.reserveFactor);
		}

		uint256 cumulatedLiquidityInterest =
			MathUtils.calculateAmountInterest(lastAvasTokenTotalSupply, aggregatorAmountAccrued);
		uint256 cumulated = cumulatedLiquidityInterest.rayMul(reserve.liquidityIndex);

		return cumulated;
	}
	/**
	* @dev Updates the liquidity cumulative index and the variable borrow index.
	* @param reserve the reserve object
	**/
	function updateState(DataTypes.ReserveData storage reserve) internal {
		(
	        uint256 lastUpdatedBalance, 
	        uint256 newBalance
        ) = IBaseAggregator(reserve.aggregator).accrue();

		// interest of yielded amount into toToken
		uint256 interestYielded = calculateAmountInterest(
			IToToken(toTokenAddress).totalSupply(), 
			yieldAmount
		)
		assetData.liquidityIndex = assetData.liquidityIndex.rayMul(interestYielded);
	}

	/**
	* @dev Initializes a reserve
	* @param reserve The reserve object
	* @param avasTokenAddress The address of the overlying atoken contract
	* @param interestRateStrategyAddress The address of the interest rate strategy contract
	**/
	function init(
		DataTypes.ReserveData storage reserve,
		address avasTokenAddress,
		address variableDebtTokenAddress,
		address interestRateStrategyAddress,
		address aggregatorAddress,
		uint256 assetClassId
	) external {
		require(reserve.avasTokenAddress == address(0), Errors.RL_RESERVE_ALREADY_INITIALIZED);

		reserve.liquidityIndex = uint128(WadRayMath.ray());
		reserve.variableBorrowIndex = uint128(WadRayMath.ray());
		reserve.avasTokenAddress = avasTokenAddress;
		reserve.variableDebtTokenAddress = variableDebtTokenAddress;
		reserve.interestRateStrategyAddress = interestRateStrategyAddress;
		reserve.depositAggregatorAddress = aggregatorAddress;
		reserve.assetClassId = assetClassId;
	}

	struct UpdateInterestRatesLocalVars {
		uint256 availableLiquidity;
		uint256 newLiquidityRate;
		uint256 newVariableRate;
		uint256 totalVariableDebt;
	}

	/**
	* @dev Updates the reserve current variable borrow rate and the current liquidity rate
	* @param reserve The address of the reserve to be updated
	* @param liquidityAdded The amount of liquidity added to the protocol (deposit or repay) in the previous action
	* @param liquidityTaken The amount of liquidity taken from the protocol (redeem or borrow)
	**/
	function updateInterestRates(
		DataTypes.ReserveData storage reserve,
		address assetAddress,
		address avasTokenAddress,
		uint256 liquidityAdded,
		uint256 liquidityTaken
	) internal {
		UpdateInterestRatesLocalVars memory vars;

		//calculates the total variable debt locally using the scaled total supply instead
		//of totalSupply(), as it's noticeably cheaper. Also, the index has been
		//updated by the previous updateState() call
		vars.totalVariableDebt = IVariableDebtToken(reserve.variableDebtTokenAddress)
			.scaledTotalSupply()
			.rayMul(reserve.variableBorrowIndex);

		uint256 aggregatorBalance = IAggregator(reserve.depositAggregatorAddress)._balance();
		uint256 aggregatorRate = reserve.depositAggregatorInterestRate;

		(
			vars.newLiquidityRate,
			vars.newVariableRate
		) = IReserveInterestRateStrategy(reserve.interestRateStrategyAddress).calculateInterestRates(
			assetAddress,
			avasTokenAddress,
			aggregatorRate,
			aggregatorRate.percentMul(reserve.depositAggregatorFactor),
			vars.totalVariableDebt,
			reserve.ltv,
			liquidityAdded,
			liquidityTaken,
			reserve.configuration.getReserveFactor()
		);
		require(vars.newLiquidityRate <= type(uint128).max, Errors.RL_LIQUIDITY_RATE_OVERFLOW);
		require(vars.newVariableRate <= type(uint128).max, Errors.RL_VARIABLE_BORROW_RATE_OVERFLOW);

		reserve.currentLiquidityRate = uint128(vars.newLiquidityRate);
		reserve.currentVariableBorrowRate = uint128(vars.newVariableRate);

		emit ReserveDataUpdated(
			reserveAddress,
			vars.newLiquidityRate,
			vars.newVariableRate,
			reserve.liquidityIndex,
			reserve.variableBorrowIndex
		);
	}

	/**
	* @dev Updates the reserve indexes and the timestamp of the update
	* @param reserve The reserve reserve to be updated
	* @param scaledVariableDebt The scaled variable debt
	* @param liquidityIndex The last stored liquidity index
	* @param variableBorrowIndex The last stored variable borrow index
  	* @param timestamp The last stored timestamp
	**/


	function _updateIndexes(
		DataTypes.ReserveData storage reserve,
		uint256 scaledVariableDebt,
		uint256 liquidityIndex,
		uint256 variableBorrowIndex,
		uint40 timestamp
	) internal returns (uint256, uint256) {

		// if (block.timestamp <= timestamp) {
		// 	return;
		// }

		uint256 newLiquidityIndex = liquidityIndex;

		///
		/// aggregator
		///
		(
			uint256 aggregatorAmountAccrued,
			uint256 lastAggregatorUpdatedBalance
		) = _getAggregatorData(reserve.depositAggregatorAddress);

		uint256 depositAggregatorInterestRate = reserve.depositAggregatorInterestRate;
		uint256 aggregatorAmountAccrued;
		if (aggregatorAmountAccrued > 0) {
			// collateral/deposits can share aggregator so we use percent instead of amount
			aggregatorAmountAccrued = aggregatorAmountAccrued.percentMul(reserve.depositAggregatorFactor);
			depositAggregatorInterestRate = aggregatorAmountAccrued.rayDiv(lastAggregatorUpdatedBalance);
		}

		///
		/// debt
		///

		uint256 variableBorrowAccrued;

		// check if vari debt before accruing
		if (scaledVariableDebt != 0) {
			uint256 lastUpdatedBorrowedTotalSupply = scaledVariableDebt.rayMul(variableBorrowIndex);
			uint256 cumulatedVariableBorrowInterest =
				MathUtils.calculateCompoundedInterest(reserve.currentVariableBorrowRate, timestamp);
			newVariableBorrowIndex = cumulatedVariableBorrowInterest.rayMul(variableBorrowIndex);
			require(
				newVariableBorrowIndex <= type(uint128).max,
				Errors.RL_VARIABLE_BORROW_INDEX_OVERFLOW
			);
			reserve.variableBorrowIndex = uint128(newVariableBorrowIndex);
			uint256 currentBorrowedTotalSupply = scaledVariableDebt.rayMul(newVariableBorrowIndex);
			variableBorrowAccrued = currentBorrowedTotalSupply.sub(lastUpdatedBorrowedTotalSupply);
		}

		///
		/// deposit
		///

		// last updated deposits supply balance
		uint256 lastSavingsTotalSupply = IAvasToken(reserve.avasTokenAddress).scaledTotalSupply().rayMul(liquidityIndex);

		// amount the aggregator appreciated for deposits plus amount borrowers accrued
		uint256 totalAccrued = aggregatorAmountAccrued.add(variableBorrowAccrued);
		uint256 mintToTreasuryAmount;
		if (totalAccrued > 0) {
			if (reserve.reserveFactor > 0) {
				mintToTreasuryAmount = totalAccrued.percentMul(reserve.reserveFactor);
			}
			uint256 cumulatedLiquidityInterest =
				MathUtils.calculateAmountInterest(lastSavingsTotalSupply, totalAccrued.sub(mintToTreasuryAmount));
			newLiquidityIndex = cumulatedLiquidityInterest.rayMul(liquidityIndex);
			require(newLiquidityIndex <= type(uint128).max, Errors.RL_LIQUIDITY_INDEX_OVERFLOW);

			reserve.liquidityIndex = uint128(newLiquidityIndex);
		}

		reserve.depositAggregatorInterestRate = depositAggregatorInterestRate;
		reserve.lastUpdateTimestamp = uint40(block.timestamp);
		return (mintToTreasuryAmount, newLiquidityIndex);
	}
}
