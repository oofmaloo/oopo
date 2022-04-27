// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.10;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AssetLogic} from './AssetLogic.sol';

import {WadRayMath} from './math/WadRayMath.sol';
import {PercentageMath} from './math/PercentageMath.sol';
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Errors} from './helpers/Errors.sol';

import {DataTypes} from './types/DataTypes.sol';
import {AssetLogic} from './AssetLogic.sol';
import {IShareToken} from '../interfaces/IShareToken.sol';

import "hardhat/console.sol";


/**
* @title ValidationLogic library
* @author Aave
* @notice Implements functions to validate the different actions of the protocol
*/
library ValidationLogic {
	using AssetLogic for DataTypes.PoolAssetData;
	using SafeMath for uint256;
	using WadRayMath for uint256;
	using PercentageMath for uint256;
	using SafeERC20 for IERC20;

	uint256 public constant REBALANCE_UP_LIQUIDITY_RATE_THRESHOLD = 4000;
	uint256 public constant REBALANCE_UP_USAGE_RATIO_THRESHOLD = 0.95 * 1e27; //usage ratio of 95%

	/**
	* @dev Validates a deposit action
	* @param poolAsset The poolAsset object on which the user is depositing
 	* @param to The amount to be deposited
	* @param amount The amount to be deposited
	*/
	function validateDeposit(DataTypes.PoolAssetData storage poolAsset, address to, uint256 amount) external view {

		require(to != msg.sender, "Error: to is sender");
		require(poolAsset.shareTokenAddress != address(0), Errors.VL_INVALID_AMOUNT);
		require(amount != 0, Errors.VL_INVALID_AMOUNT);
		require(poolAsset.active, Errors.VL_NO_ACTIVE_RESERVE);
	}

	/**
	* @dev Validates a withdraw action
	* @param poolAsset The address of the poolAsset
	* @param amount The amount to be withdrawn
	* @param sharer The balance of the user
	* @param benefactor The reserves state
 	* @param userType The reserves state
	*/
	function validateWithdraw(
		DataTypes.PoolAssetData storage poolAsset,
		uint256 amount,
		address caller,
		address sharer,
		address benefactor,
		uint256 userType
	) external view {
		require(amount != 0, Errors.VL_INVALID_AMOUNT);
		require(userType != 0, Errors.VL_INVALID_AMOUNT);
		require(poolAsset.shareTokenAddress != address(0), Errors.VL_INVALID_AMOUNT);
		require(poolAsset.active, Errors.VL_NO_ACTIVE_RESERVE);

		require(
			uint256(DataTypes.UserType.SHARER) == userType ||
			uint256(DataTypes.UserType.BENEFACTOR) == userType,
			Errors.VL_INVALID_INTEREST_RATE_MODE_SELECTED
		);

		(uint256 sharerBalance, uint256 benefactorBalance) = IShareToken(poolAsset.shareTokenAddress).getBalances(sharer, benefactor);
		uint256 balance;
		if (uint256(DataTypes.UserType.SHARER) == userType) {
			require(caller == sharer, "Error");
			balance = sharerBalance;
		} else {
			require(caller == benefactor, "Error");
			balance = benefactorBalance;
		}

		console.log("validateWithdraw balance", balance);
		require(amount <= balance, Errors.VL_NOT_ENOUGH_AVAILABLE_USER_BALANCE);


	}

	// *
	// * @dev Validates an aToken transfer
	// * @param from The user from which the aTokens are being transferred
	// * @param reservesData The state of all the reserves
	// * @param userConfig The state of the user for the specific poolAsset
	// * @param reserves The addresses of all the active reserves
	// * @param oracle The price oracle
	
	// function validateTransfer(
	// 	address from,
	// 	mapping(address => DataTypes.PoolAssetData) storage poolAssetsData,
	// 	DataTypes.UserConfigurationMap storage userConfig,
	// 	mapping(uint256 => address) storage reserves,
	// 	uint256 reservesCount,
	// 	address oracle
	// ) internal view {

	// }
}
