// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.10;

import {ILendingPoolAddressesProvider} from '../../interfaces/ILendingPoolAddressesProvider.sol';
import {ILendingPool} from '../../interfaces/ILendingPool.sol';

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {DataTypes} from '../libraries/types/DataTypes.sol';
// import {ILendingPoolConfigurator} from '../../interfaces/ILendingPoolConfigurator.sol';

import '../tokenization/AToken.sol';

/**
 * @title LendingPoolConfigurator contract
 * @author Aave
 * @dev Implements the configuration methods for the Aave protocol
 **/

contract LendingPoolConfigurator {

  ILendingPoolAddressesProvider internal addressesProvider;
  ILendingPool internal pool;

  constructor(ILendingPoolAddressesProvider provider) {
    addressesProvider = provider;
    pool = ILendingPool(addressesProvider.getLendingPool());
  }

  /**
   * @dev Initializes reserves in batch
   **/
  // function batchInitReserve(InitReserveInput[] memory input) external {
  //   ILendingPool cachedPool = pool;
  //   for (uint256 i = 0; i < input.length; i++) {
  //     _initReserve(cachedPool, input[i]);
  //   }
  // }

  // function _initReserve(
  //   ILendingPool pool, 
  //   InitReserveInput memory input
  // ) internal {
  //   AToken aTokenInstance = new AToken(
  //     pool,
  //     address(pool),
  //     input.underlyingAsset,
  //     input.underlyingAssetDecimals,
  //     input.aTokenName,
  //     input.aTokenSymbol
  //   );

  //   address aTokenAddress = address(aTokenInstance);

  //   pool.initReserve(
  //     input.underlyingAsset,
  //     aTokenAddress
  //   );
  // }

  function initReserve(
    ILendingPool pool, 
    address underlyingAsset,
    uint8 underlyingAssetDecimals,
    string memory aTokenName,
    string memory aTokenSymbol
  ) public {
    AToken aTokenInstance = new AToken(
      pool,
      address(pool),
      underlyingAsset,
      underlyingAssetDecimals,
      aTokenName,
      aTokenSymbol
    );

    address aTokenAddress = address(aTokenInstance);

    pool.initReserve(
      underlyingAsset,
      aTokenAddress
    );
  }

}
