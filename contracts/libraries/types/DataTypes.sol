//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

/**
 * @title PoolStorage
 * @author Advias
 * @title Protocol storage
 */
library DataTypes {

    struct PoolAssetData {
    	address underlying;
    	address shareTokenAddress;
        address aggregatorAddress;
    	uint8 decimals;
    	uint128 index;
        uint256 aggregatorFactor;
        uint256 reserveFactor;
        bool active;
        uint256 lastUpdateTimestamp;
    }

    enum UserType {NONE, SHARER, BENEFACTOR}


}
