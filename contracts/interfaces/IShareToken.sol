// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.10;

import {IPool} from '../interfaces/IPool.sol';

interface IShareToken {
	/**
	* @dev Mints `amount` shareTokens to `sharer`
	* - Only callable by the LendingPool, as extra state updates there need to be managed
	* - Sends portion of designated assets to aggregation
	* @param sharer The address receiving the minted tokens
	* @param amount The amount of tokens getting minted
	* @param index The new liquidity index of the reserve
	* - Once allowSharePercentageUpdates is set, it cannot be updated
	*/
	function mint(
		address sharer,
		address benefactor,
		uint256 amount,
		uint256 sharePercentage,
		bool allowSharePercentageUpdates,
		uint256 index
	) external;


	/**
	* @dev Burns shareTokens from `sharer` and sends the equivalent amount of underlying to `receiverOfUnderlying`
	* - Only callable by the LendingPool, as extra state updates there need to be managed
 	* @param caller The owner of the shareTokens, getting them burned
	* @param sharer The owner of the shareTokens, getting them burned
	* @param benefactor The owner of the shareTokens, getting them burned
	* @param userType The address that will receive the underlying
	* @param amount The amount being burned
	* @param index The new liquidity index of the reserve
	**/
	function burn(
		address caller,
		address sharer,
		address benefactor,
		uint256 userType,
		uint256 amount,
		uint256 index
	) external;

	// function updateBalances(address sharer, address benefactor) external returns (uint256, uint256);

	function getBalances(address sharer, address benefactor) external view returns (uint256, uint256);

	function balanceOfBenefactor(address benefactor) external returns (uint256);

	function balanceOfSharer(address sharer) external returns (uint256);

	/**
	* @dev Returns the scaled balance of the sharer. The scaled balance is the sum of all the
	* updated stored balance divided by the reserve's liquidity index at the moment of the update
	* @param sharer The sharer whose balance is calculated
	* @return The scaled balance of the sharer
	**/
	function scaledBalanceOf(address sharer) external view returns (uint256);

	/**
	* @dev Returns the scaled balance of the sharer and the scaled total supply.
	* @param sharer The address of the sharer
	* @return The scaled balance of the sharer
	* @return The scaled balance and the scaled total supply
	**/
	function getScaledUserBalanceAndSupply(address sharer)
		external
		view
		returns (uint256, uint256);

	/**
	* @dev Returns the scaled total supply of the variable debt token. Represents sum(debt/index)
	* @return the scaled total supply
	**/
	function scaledTotalSupply() external view returns (uint256);

	/**
	* @dev Transfers the underlying asset to `target`. Used by the LendingPool to transfer
	* assets in borrow(), withdraw() and flashLoan()
	* @param target The recipient of the shareTokens
	* @param amount The amount getting transferred
	* @return The amount transferred
	**/
	function transferUnderlyingTo(address target, uint256 amount)
		external
		returns (uint256);

	function UNDERLYING_ASSET_ADDRESS() external view returns (address);

	/**
	* @dev Supplies underlying asset to Anchor or vault for AUST in return
	**/
	function supply(uint256 amount) external returns (uint256);


	/**
	* @dev Redeem underlying asset from Anchor or vault
	**/
	function redeem(uint256 amount, address to) external returns (bool);

	struct Sharer {
		uint256 scaledAmount;
		uint256 benefactorScaled;
		uint256 index;
		uint256 sharePercentage;
		bool allowSharePercentageUpdates; // allow updates to yield share perc
		bool active;
	}

	// function _mint(Sharer storage _sharer, uint256 amount) external;

	// function _burn(Sharer storage _sharer, uint256 amount) external;
	function updatedBalanceOfBenefactor(address benefactor, uint256 currentIndex) external;

	function updatedBalanceOfSharer(address sharer, uint256 currentIndex) external;

}
