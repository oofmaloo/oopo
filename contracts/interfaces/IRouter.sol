// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IRouter {
    function deposit(address asset, uint256 _amount, uint256 _minAmountOut, address to) external returns (uint256);

    function redeem(address asset, uint256 _amount, address to, address _outAsset) external returns (uint256);

    function getBalance(address account) external view returns (uint256);
    
    function underlying() external view returns (address);

    function token() external view returns (address);

}
