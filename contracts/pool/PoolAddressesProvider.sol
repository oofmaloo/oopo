//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';

/**
 * @title PoolAddressesProvider
 * @author Advias
 * @title Stores protocols contracts for retrieval
 */
contract PoolAddressesProvider is IPoolAddressesProvider {
  address private pool;
  address private tokenFactory;
  address private poolAdmin;

  constructor() {
      _setPoolAdmin(msg.sender);
  }

  modifier onlyPoolAdmin() {
      require(msg.sender == poolAdmin);
      _;
  }

  function setPool(address _pool) external override {
      pool = _pool;
  }

  function getPool() external view override returns (address) {
      return pool;
  }

  function setTokenFactory(address _tokenFactory) external override onlyPoolAdmin {
      tokenFactory = _tokenFactory;
  }

  function getTokenFactory() external view override returns (address) {
      return tokenFactory;
  }

  function getPoolAdmin() external view override returns (address) {
      return poolAdmin;
  }

  function setPoolAdmin(address _poolAdmin) public override onlyPoolAdmin {
      _setPoolAdmin(_poolAdmin);
  }

  function _setPoolAdmin(address _poolAdmin) internal {
      poolAdmin = _poolAdmin;
  }

}
