// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {SafeMath} from '../../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {IERC20} from '../../../dependencies/openzeppelin/contracts/IERC20.sol';
import {SafeERC20} from '../../../dependencies/openzeppelin/contracts/SafeERC20.sol';

contract Pool {
	using SafeMath for uint256;
	using WadRayMath for uint256;
	using PercentageMath for uint256;
	using SafeERC20 for IERC20;


	constructor() {

	}

	struct AssetData {
		address asset;
		address token;
		uint256 decimals;
		address aggregator;
		bool active;
	}

	enum UserType {NONE, SHARER, SHAREE}

	function deposit(
		address asset,
		uint256 amount,
		address to
	) external {
		DataTypes.AssetData storage assetData = _assetsData[asset];

		ValidationLogic.validateDeposit(assetData, amount);
		require(amount != 0);
		require(to != msg.sender);

		address toToken = assetData.toTokenAddress;

		assetData.updateState();

		// transfer asset in
		IERC20(asset).safeTransferFrom(msg.sender, toToken, amount);

		// mint to to
		IToToken(toToken).mint(msg.sender, to, amount, assetData.liquidityIndex);

		emit Deposit(asset, msg.sender, to, amount);
	}

	// call as caller
	// use withdrawTo if recipient
	function withdraw(
		address asset,
		uint256 amount,
		address sharer,
		address sharee,
		uint256 userType
	) external {
		DataTypes.AssetData storage assetData = _assetsData[asset];

		ValidationLogic.validateWithdraw(assetData, amount, sharer, sharee, userType);

		address toToken = assetData.toTokenAddress;

		assetData.updateState();

		// mint to to
		IToToken(toToken).burn(msg.sender, userType, amount, assetData.liquidityIndex);

		emit Withdraw(asset, msg.sender, userType, amount);
	}
	function _checkValue(DataTypes.AssetData storage assetData) internal returns (uint256) {
		uint256 assetIndex = _getIndex(asset);
		return IERC20()
	}

	function calculateAmountInterest(
		uint256 lastUpdatedAmount, 
		uint256 amountAdded
	)
		internal
		view
		returns (uint256)
	{
		return (amountAdded.rayDiv(lastUpdatedAmount));
	}


	function initAsset(address asset, uint256 decimals) external {
		AssetData storage assetData = _assetsData[asset];
		assetData.liquidityIndex = 1e27;
	}

}