//
// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {SafeMath} from '../../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {IERC20} from '../../../dependencies/openzeppelin/contracts/IERC20.sol';
import {ReserveLogic} from './ReserveLogic.sol';
import {GenericLogic} from './GenericLogic.sol';
import {WadRayMath} from '../math/WadRayMath.sol';
import {PercentageMath} from '../math/PercentageMath.sol';
import {SafeERC20} from '../../../dependencies/openzeppelin/contracts/SafeERC20.sol';
import {ReserveConfiguration} from '../configuration/ReserveConfiguration.sol';
import {UserConfiguration} from '../configuration/UserConfiguration.sol';
import {Errors} from '../helpers/Errors.sol';
import {Helpers} from '../helpers/Helpers.sol';
import {IReserveInterestRateStrategy} from '../../../interfaces/IReserveInterestRateStrategy.sol';
import {DataTypes} from '../types/DataTypes.sol';

/**
* @title ReserveLogic library
* @author Aave
* @notice Implements functions to validate the different actions of the protocol
*/
library ValidationLogic {
	using ReserveLogic for DataTypes.ReserveData;
	using SafeMath for uint256;
	using WadRayMath for uint256;
	using PercentageMath for uint256;
	using SafeERC20 for IERC20;
	using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
	using UserConfiguration for DataTypes.UserConfigurationMap;

	uint256 public constant REBALANCE_UP_LIQUIDITY_RATE_THRESHOLD = 4000;
	uint256 public constant REBALANCE_UP_USAGE_RATIO_THRESHOLD = 0.95 * 1e27; //usage ratio of 95%

	/**
	* @dev Validates a deposit action
	* @param poolAsset The poolAsset object on which the user is depositing
	* @param amount The amount to be deposited
	*/
	function validateDeposit(DataTypes.ReserveData storage poolAsset, uint256 amount) external view {
		(bool isActive, bool isFrozen, , ) = poolAsset.configuration.getFlags();

		require(poolAsset.shareTokenAddress != address(0), Errors.VL_INVALID_AMOUNT);
		require(amount != 0, Errors.VL_INVALID_AMOUNT);
		require(isActive, Errors.VL_NO_ACTIVE_RESERVE);
		require(!isFrozen, Errors.VL_RESERVE_FROZEN);
	}

	/**
	* @dev Validates a withdraw action
	* @param reserveAddress The address of the poolAsset
	* @param amount The amount to be withdrawn
	* @param userBalance The balance of the user
	* @param reservesData The reserves state
	* @param oracle The price oracle
	*/
	function validateWithdraw(
		DataTypes.ReserveData storage poolAsset,
		uint256 amount,
		address sharer,
		address sharee,
		uint256 userType
	) external view {
		require(amount != 0, Errors.VL_INVALID_AMOUNT);
		require(userType != 0, Errors.VL_INVALID_AMOUNT);
		require(poolAsset.shareTokenAddress != address(0), Errors.VL_INVALID_AMOUNT);
		require(poolAsset.active, Errors.VL_NO_ACTIVE_RESERVE);

		require(
			uint256(DataTypes.UserType.SHARER) == userType ||
			uint256(DataTypes.UserType.SHAREE) == userType,
			Errors.VL_INVALID_INTEREST_RATE_MODE_SELECTED
		);

		(uint256 sharerBalance, uint256 shareeBalance) = IToToken(poolAsset.token).balanceOfSharersPositionWithSharee(sharer, sharee);
		if (uint256(DataTypes.UserType.SHARER) == userType) {
			// balance = balanceOfSharer(user);
			balance = sharerBalance;
		} else if (uint256(DataTypes.UserType.SHAREE) == userType) {
			// balance = balanceOfSharee(user);
			balance = shareeBalance;
		}

		require(amount <= balance, Errors.VL_NOT_ENOUGH_AVAILABLE_USER_BALANCE);


	}

	/**
	* @dev Validates an aToken transfer
	* @param from The user from which the aTokens are being transferred
	* @param reservesData The state of all the reserves
	* @param userConfig The state of the user for the specific poolAsset
	* @param reserves The addresses of all the active reserves
	* @param oracle The price oracle
	*/
	function validateTransfer(
		address from,
		mapping(address => DataTypes.ReserveData) storage reservesData,
		DataTypes.UserConfigurationMap storage userConfig,
		mapping(uint256 => address) storage reserves,
		uint256 reservesCount,
		address oracle
	) internal view {
		(, , , , uint256 healthFactor) =
			GenericLogic.calculateUserAccountData(
				from,
				reservesData,
				userConfig,
				reserves,
				reservesCount,
				oracle
			);

		require(
			healthFactor >= GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD,
			Errors.VL_TRANSFER_NOT_ALLOWED
		);
	}
}
