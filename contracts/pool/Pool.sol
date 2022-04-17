// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {SafeMath} from '../../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Pool is IPool, PoolStorage {
	using SafeMath for uint256;
	using WadRayMath for uint256;
	using PercentageMath for PercentageMath;
	using SafeERC20 for IERC20;

	constructor() {

	}

	function deposit(
		address asset,
		uint256 amount,
		address benefactor
	) external {
		PoolAsset storage poolAsset = poolAssets[asset];

		ValidationLogic.validateDeposit(poolAsset, amount);
		require(amount != 0);
		require(to != msg.sender);

		address shareToken = poolAsset.shareTokenAddress;

		poolAsset.updateState();

		// transfer asset in
		IERC20(asset).safeTransferFrom(msg.sender, shareToken, amount);

		// mint to to
		IShareToken(shareToken).mint(msg.sender, to, amount, poolAsset.liquidityIndex);

		emit Deposit(asset, msg.sender, to, amount);
	}

	// call as caller
	// use withdrawTo if recipient
	function withdraw(
		address asset,
		uint256 amount,
		address sharer,
		address benefactor,
		uint256 userType
	) external {
		PoolAsset storage poolAsset = poolAssets[asset];

		ValidationLogic.validateWithdraw(poolAsset, amount, sharer, benefactor, userType);

		address shareToken = poolAsset.shareTokenAddres;

		poolAsset.updateState();

		// mint to to
		IShareToken(shareToken).burn(msg.sender, userType, amount, poolAsset.liquidityIndex);

		emit Withdraw(asset, msg.sender, userType, amount);
	}

    function initShareToken(
        address asset,
        address shareTokenAddress,
        address decimals,
        address aggregator
    ) external override {
        PoolAsset storage poolAsset = poolAssets[asset];

        require(!poolAsset.active, "");

        poolAsset.liquidityIndex = 1e27;
        poolAsset.aggregator = aggregator;
        poolAsset.underlying = asset;
        poolAsset.shareTokenAddress = shareTokenAddress;

        addPoolAssetToListInternal(asset);

        emit PoolAssetInit(
            asset,
            wrapped
        );
    }

    function addPoolAssetToListInternal(address asset) internal {
        uint256 _poolAssetsCount = poolAssetsCount;
        bool poolAssetAlreadyAdded = false;
        for (uint256 i = 0; i < _poolAssetsCount; i++)
            if (poolAssetsList[i] == asset) {
                poolAssetAlreadyAdded = true;
            }
        if (!poolAssetAlreadyAdded) {
            poolAssetsList[poolAssetsCount] = asset;
            poolAssetsCount = _poolAssetsCount + 1;
        }
    }
}