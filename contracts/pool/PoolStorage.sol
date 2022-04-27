//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;
import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {DataTypes} from '../libraries/types/DataTypes.sol';
import {AssetLogic} from '../libraries/AssetLogic.sol';

/**
 * @title PoolStorage
 * @author Advias
 * @title Protocol storage
 */
contract PoolStorage {
    using AssetLogic for DataTypes.PoolAssetData;

    // poolAssetsList[underlying] => PoolAssetData
    mapping(address => DataTypes.PoolAssetData) internal poolAssets;

    // poolAssetsList[uint256] => mapping
    mapping(uint256 => address) public poolAssetsList;

    uint256 public poolAssetsCount;

    bool internal paused;

    IPoolAddressesProvider internal _addressesProvider;

}
