// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.10;

interface IPool {
    event PoolAssetInit(
        address indexed asset,
        address shareTokenAddress
    );

	event Deposit(
		address indexed asset, 
		address indexed sharer, 
		address indexed benefactor, 
		uint256 amount
	);

	event Withdraw(
		address indexed asset, 
		address indexed caller, 
		uint256 userType, 
		uint256 amount
	);

	function deposit(
		address asset,
		uint256 amount,
		address benefactor,
		uint256 sharePercentage,
		bool allowSharePercentageUpdates
	) external;

	function withdraw(
		address asset,
		uint256 amount,
		address sharer,
		address benefactor,
		uint256 userType
	) external;

	function getReserveNormalizedIncome(address asset) external view returns (uint256);

    function initPoolAsset(
        address asset,
        address shareTokenAddress,
        uint8 decimals,
        address aggregator
    ) external;
}