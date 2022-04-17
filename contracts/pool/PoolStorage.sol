//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';

/**
 * @title PoolStorage
 * @author Advias
 * @title Protocol storage
 */
contract PoolStorage {

    struct PoolAsset {
    	bool active;
    	address underlying;
    	address shareTokenAddress;
    	uint256 decimals;
    	uint256 index;
    	address aggregator;
    }

    // poolAssetsList[underlying] => PoolAsset
    mapping(address => PoolAsset) internal poolAssets;

    // poolAssetsList[uint256] => mapping
    mapping(uint256 => address) public poolAssetsList;

    uint256 public poolAssetsCount;

    bool internal paused;

    IPoolAddressesProvider internal addressesProvider;

}
