// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.10;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IShareToken} from '../interfaces/IShareToken.sol';
import {MathUtils} from './math/MathUtils.sol';
import {WadRayMath} from './math/WadRayMath.sol';
import {PercentageMath} from './math/PercentageMath.sol';
import {Errors} from './helpers/Errors.sol';
import {DataTypes} from './types/DataTypes.sol';
import {IAggregator} from '../interfaces/IAggregator.sol';

import "hardhat/console.sol";

/**
 * @title AssetLogic library
 * @author Aave
 * @notice Implements the logic to update the reserves state
 */
library AssetLogic {
	using SafeMath for uint256;
	using WadRayMath for uint256;
	using PercentageMath for uint256;
	using SafeERC20 for IERC20;
	using AssetLogic for DataTypes.PoolAssetData;
	/**
	* @dev Emitted when the state of a reserve is updated
	* @param asset The address of the underlying asset of the reserve
	* @param liquidityRate The new liquidity rate
	* @param variableBorrowRate The new variable borrow rate
	* @param index The new liquidity index
	* @param variableBorrowIndex The new variable borrow index
	**/
	event ReserveDataUpdated(
		address indexed asset,
		uint256 liquidityRate,
		uint256 variableBorrowRate,
		uint256 index,
		uint256 variableBorrowIndex
	);

	/**
	* @dev Returns the ongoing normalized income for the poolAsset
	* A value of 1e27 means there is no income. As time passes, the income is accrued
	* A value of 2*1e27 means for each unit of asset one unit of income has been accrued
	* @param poolAsset The poolAsset object
	* @return the normalized income. expressed in ray
	**/
	function getNormalizedIncome(DataTypes.PoolAssetData storage poolAsset)
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
		) = IAggregator(poolAsset.aggregatorAddress).accrueSim();

		uint256 aggregatorAmountAccrued = newAggregatorBalance.sub(lastAggregatorUpdatedBalance);

		if (aggregatorAmountAccrued == 0) {
			return poolAsset.index;
		}

		uint256 lastShareTokenTotalSupply = IShareToken(poolAsset.shareTokenAddress).scaledTotalSupply().rayMul(poolAsset.index);

		uint256 mintToTreasuryAmount;
		if (poolAsset.reserveFactor > 0) {
			mintToTreasuryAmount = aggregatorAmountAccrued.percentMul(poolAsset.reserveFactor);
		}

		uint256 cumulatedLiquidityInterest =
			MathUtils.calculateAmountInterest(lastShareTokenTotalSupply, aggregatorAmountAccrued);

		uint256 cumulated = cumulatedLiquidityInterest.rayMul(poolAsset.index).add(poolAsset.index);
		return cumulated;
	}
	/**
	* @dev Updates the liquidity cumulative index and the variable borrow index.
	**/
	function updateState(DataTypes.PoolAssetData storage poolAsset) internal {

		(
			uint256 newBalance,
			uint256 lastUpdatedBalance
		) = _getAggregatorData(poolAsset.aggregatorAddress);

		console.log("updateState lastUpdatedBalance", lastUpdatedBalance);
		console.log("updateState newBalance", newBalance);

        if (lastUpdatedBalance >= newBalance) {
        	return;
        }

		uint256 aggregatorAccrued = newBalance.sub(lastUpdatedBalance);
		console.log("updateState aggregatorAccrued", aggregatorAccrued);

		if (aggregatorAccrued > 0) {
			// collateral/deposits can share aggregator so we use percent instead of amount
			aggregatorAccrued = aggregatorAccrued.percentMul(poolAsset.aggregatorFactor);
		}


		// last updated deposits supply balance
		uint256 lastTotalSupply = IShareToken(poolAsset.shareTokenAddress).scaledTotalSupply().rayMul(poolAsset.index);
		console.log("updateState lastTotalSupply", lastTotalSupply);

		// amount the aggregator appreciated for deposits plus amount borrowers accrued
		uint256 mintToTreasuryAmount;
		if (aggregatorAccrued > 0) {
			if (poolAsset.reserveFactor > 0) {
				mintToTreasuryAmount = aggregatorAccrued.percentMul(poolAsset.reserveFactor);
			}
			uint256 cumulatedLiquidityInterest =
				MathUtils.calculateAmountInterest(lastTotalSupply, aggregatorAccrued.sub(mintToTreasuryAmount));
			uint256 newIndex = cumulatedLiquidityInterest.rayMul(poolAsset.index).add(poolAsset.index);
			require(newIndex <= type(uint128).max, Errors.RL_LIQUIDITY_INDEX_OVERFLOW);

			poolAsset.index = uint128(newIndex);
		}

		console.log(poolAsset.index);

		poolAsset.lastUpdateTimestamp = uint40(block.timestamp);
	}

	/**
	* @dev Initializes a poolAsset
	* @param poolAsset The poolAsset object
	* @param shareTokenAddress The address of the overlying atoken contract
	* @param aggregatorAddress The address of the interest rate strategy contract
	**/
	function init(
		DataTypes.PoolAssetData storage poolAsset,
		address shareTokenAddress,
		address aggregatorAddress
	) external {
		require(poolAsset.shareTokenAddress == address(0), Errors.RL_RESERVE_ALREADY_INITIALIZED);

		poolAsset.index = uint128(WadRayMath.ray());
		poolAsset.shareTokenAddress = shareTokenAddress;
		poolAsset.aggregatorAddress = aggregatorAddress;
	}

	struct UpdateInterestRatesLocalVars {
		uint256 availableLiquidity;
		uint256 newLiquidityRate;
		uint256 newVariableRate;
	}

	function _getAggregatorData(address aggregator) internal returns (uint256, uint256) {
		(
			uint256 newBalance,
			uint256 lastUpdatedBalance
		) = IAggregator(aggregator).accrue();
		return (newBalance, lastUpdatedBalance);
	}
}
