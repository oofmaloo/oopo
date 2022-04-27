//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {IPool} from '../interfaces/IPool.sol';
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import '../tokenization/ShareToken.sol';
import '../tokenization/ShareTokenERC1155.sol';

import "hardhat/console.sol";

contract ShareTokenFactory {

  IPoolAddressesProvider private _provider;
  IPool private _pool;

  constructor(IPoolAddressesProvider provider) {
      _provider = provider;
      _pool = IPool(_provider.getPool());
  }

  modifier onlyPoolAdmin() {
      require(msg.sender == _provider.getPoolAdmin(), "Errors: Caller must be pool admin");
      _;
  }

  function initShareToken(
      address provider,
      address asset,
      address aggregator
  ) public {
      uint8 decimals = IERC20Metadata(asset).decimals();

      ShareTokenERC1155 shareTokenInstance = new ShareTokenERC1155(provider, asset, decimals, aggregator);
      address shareTokenAddress = address(shareTokenInstance);

      _pool.initPoolAsset(
        asset,
        shareTokenAddress,
        decimals,
        aggregator
      );
  }
}
