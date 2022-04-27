// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.10;

import {IPool} from '../interfaces/IPool.sol';
import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {IShareToken} from '../interfaces/IShareToken.sol';

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {AssetLogic} from '../libraries/AssetLogic.sol';
import {ValidationLogic} from '../libraries/ValidationLogic.sol';
import {DataTypes} from '../libraries/types/DataTypes.sol';

import {WadRayMath} from '../libraries/math/WadRayMath.sol';
import {PercentageMath} from '../libraries/math/PercentageMath.sol';
import {PoolStorage} from './PoolStorage.sol';

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "hardhat/console.sol";

contract Pool is IPool, PoolStorage {
	using SafeMath for uint256;
	using WadRayMath for uint256;
	using PercentageMath for uint256;
	using SafeERC20 for IERC20;

	using AssetLogic for DataTypes.PoolAssetData;

	constructor(IPoolAddressesProvider addressesProvider_) {
		_addressesProvider = addressesProvider_;
	}

	function deposit(
		address asset,
		uint256 amount,
		address benefactor,
		uint256 sharePercentage,
		bool allowSharePercentageUpdates
	) external {
		DataTypes.PoolAssetData storage poolAsset = poolAssets[asset];

		ValidationLogic.validateDeposit(poolAsset, benefactor, amount);

		address shareToken = poolAsset.shareTokenAddress;

		poolAsset.updateState();

		// transfer asset in
		IERC20(asset).safeTransferFrom(msg.sender, shareToken, amount);

		// mint to to
		IShareToken(shareToken).mint(
			msg.sender, 
			benefactor, 
			amount, 
			sharePercentage, 
			allowSharePercentageUpdates, 
			poolAsset.index
		);

		emit Deposit(asset, msg.sender, benefactor, amount);
	}

	/**
	* @dev Withdraws underlying
	* @param asset The address of the poolAsset
	* @param amount The amount to be withdrawn
	* @param sharer The sharer account to remove from
	* @param benefactor The benefactor of the account
	* @param userType The user caller
	*/
	function withdraw(
		address asset,
		uint256 amount,
		address sharer,
		address benefactor,
		uint256 userType
	) external {
		DataTypes.PoolAssetData storage poolAsset = poolAssets[asset];

		ValidationLogic.validateWithdraw(poolAsset, amount, msg.sender, sharer, benefactor, userType);

		address shareToken = poolAsset.shareTokenAddress;

		poolAsset.updateState();

		// confirmed on validated
		// if (uint256(DataTypes.UserType.SHARER) == userType) {
		// 	IShareToken(shareToken).updatedBalanceOfSharer(sharer, poolAsset.index);
		// } else {
		// 	IShareToken(shareToken).updatedBalanceOfBenefactor(benefactor, poolAsset.index);
		// }

		IShareToken(shareToken).burn(msg.sender, sharer, benefactor, userType, amount, poolAsset.index);

		emit Withdraw(asset, msg.sender, userType, amount);
	}

	function getReserveNormalizedIncome(address asset) external view override returns (uint256) {
		DataTypes.PoolAssetData storage poolAsset = poolAssets[asset];
		return poolAsset.getNormalizedIncome();
	}

	function getPoolAssetData(address asset) external view returns (DataTypes.PoolAssetData memory) {
		return poolAssets[asset];
	}

    function initPoolAsset(
        address asset,
        address shareTokenAddress,
        uint8 decimals,
        address aggregatorAddress
    ) external override {
        DataTypes.PoolAssetData storage poolAsset = poolAssets[asset];

        require(!poolAsset.active, "Error: Active");

        poolAsset.index = uint128(WadRayMath.ray());
        poolAsset.aggregatorAddress = aggregatorAddress;
        poolAsset.underlying = asset;
        poolAsset.shareTokenAddress = shareTokenAddress;
        poolAsset.active = true;

        addPoolAssetToListInternal(asset);

        emit PoolAssetInit(
            asset,
            shareTokenAddress
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