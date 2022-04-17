//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {IPool} from '../interfaces/IPool.sol';
import {ICollateralTokenFactory} from '../interfaces/ICollateralTokenFactory.sol';
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import '../tokens/CollateralToken.sol';
import '../tokens/YCollateralToken.sol';
import {ICollateralToken} from '../interfaces/ICollateralToken.sol';

contract ShareTokenFactory {

  IPoolAddressesProvider _provider;
  IPool _pool;

  constructor(IPoolAddressesProvider provider) {
      _provider = provider;
      _pool = IPool(_provider.getPool());
  }

  modifier onlyPoolAdmin() {
      require(msg.sender == _provider.getPoolAdmin(), "Errors: Caller must be pool admin");
      _;
  }

  /**
   * @dev Initiates collateral token
   * @param asset The underlying asset
   * @param aggregator The protocol asset router
   **/
  function initShareToken(
      address asset,
      address aggregator
  ) public override onlyPoolAdmin {
      uint8 decimals = IERC20Metadata(asset).decimals();

      ShareToken shareTokenInstance = new ShareToken(address(_provider), asset, decimals);
      address token = address(shareTokenInstance);

      _pool.initShareToken(
          asset,
          token,
          aggregator
      );
  }
}
