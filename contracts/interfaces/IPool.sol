// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

interface IPool {
	function deposit(
		address asset,
		uint256 amount,
		address benefactor
	) external;

	function withdraw(
		address asset,
		uint256 amount,
		address sharer,
		address benefactor,
		uint256 userType
	) external;

    function initPoolAsset(
        address asset,
        address shareTokenAddress,
        address decimals,
        address aggregator
    ) external;
}