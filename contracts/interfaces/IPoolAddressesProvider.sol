//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

interface IPoolAddressesProvider {

  function setPool(address _pool) external;
  
  function getPool() external view returns (address);

  function setTokenFactory(address _tokenFactory) external;

  function getTokenFactory() external view returns (address);

  function getPoolAdmin() external view returns (address);

  function setPoolAdmin(address _poolAdmin) external;
}
