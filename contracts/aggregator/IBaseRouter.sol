// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBaseRouter {
    function deposit(address asset, uint256 _amount, uint256 _minAmountOut, address to) external override returns (uint256);

    function redeem(address asset, uint256 _amount, address to, address _outAsset) external override returns (uint256);

    function getBalance(address account) external view returns (uint256);
    
    function underlying() external override returns (uint256);

    function token() external override returns (uint256);

}
