// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {IERC20} from '../../dependencies/openzeppelin/contracts/IERC20.sol';
import {SafeERC20} from '../../dependencies/openzeppelin/contracts/SafeERC20.sol';
import {ILendingPool} from '../../interfaces/ILendingPool.sol';
import {IToToken} from '../../interfaces/IToToken.sol';

contract ToToken is IToToken	{
	using WadRayMath for uint256;
	using SafeERC20 for IERC20;

	// sharer is the the initiator
	// sharee is the benefactor

	// sharer can have_many many sharees
	// sharees can have_many sharers
	// sharer can track all their sharees

  struct Sharer {
  	uint256 scaledAmount;
  	uint256 index;
  	uint256 sharePercentage;
  	uint256 shareeScaled; // releases here on full sharer withdraw
  	bool allowSharePercentageUpdates,
  	bool active;
  }
  // _sharer[sharee][msg.sender] => Sharer
	mapping(address => mapping(address => Sharer)) private _sharers;
	// sharees for the sharer
  address[] public _sharerSharees;
	// sharers for the sharee
  address[] public _shareeSharers;



	IPool internal _pool;
	address internal _underlyingAsset;

	modifier onlyPool {
		require(_msgSender() == address(_pool), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
		_;
	}

	constructor() {

	}

	/**
	* @dev Mints `amount` avasTokens to `sharer`
	* - Only callable by the LendingPool, as extra state updates there need to be managed
	* - Sends portion of designated assets to aggregation
	* @param sharer The address receiving the minted tokens
	* @param amount The amount of tokens getting minted
	* @param index The new liquidity index of the reserve
	* - Once allowSharePercentageUpdates is set, it cannot be updated
	*/
	function mint(
		address sharer,
		address sharee,
		uint256 amount,
		uint256 sharePercentage,
		bool allowSharePercentageUpdates,
		uint256 index
	) external override onlyLendingPool {
		require(sharePercentage <= 1e4 && sharePercentage > 0, Errors.CT_INVALID_MINT_AMOUNT);

		Sharer storage _sharer = _sharers[sharer][sharee];

		_sharer.amount += amount;

		if (!_sharer.active) {
			_sharer.active = true;
			_sharer.allowSharePercentageUpdates = allowSharePercentageUpdates;
			_sharer.sharePercentage = sharePercentage;
			_shareeSharers.push(sharer);
			_sharerSharees.push(sharee);
		}

		supply(amount);

		uint256 amountScaled = amount.rayDiv(index);
		require(amountScaled != 0, Errors.CT_INVALID_MINT_AMOUNT);
		// _sharer.scaledAmount += scaledAmount;
		_sharer.index = index;
		_mint(_sharer, amountScaled);

		emit Transfer(address(0), sharer, amount);
		emit Mint(sharer, amount, index);
	}

	/**
	* @dev Sets the share percentage for a sharee by a sharer
	* - Only updated if original mint `allowSharePercentageUpdates` 
	**/
	function setSharePercentage(address sharer, address sharee) external {
			require(msg.sender == sharer);
			require(sharePercentage <= 1e4, Errors.CT_INVALID_MINT_AMOUNT);
			Sharer storage _sharer = _sharers[sharer][sharee];
			require(_sharer.active);
			require(_sharer.allowSharePercentageUpdates);
			_sharer.sharePercentage = sharePercentage;
	}

	/**
	* @dev Burns avasTokens from `sharer` and sends the equivalent amount of underlying to `receiverOfUnderlying`
	* - Only callable by the LendingPool, as extra state updates there need to be managed
	* @param sharer The owner of the avasTokens, getting them burned
	* @param sharee The owner of the avasTokens, getting them burned
	* @param userType The address that will receive the underlying
	* @param amount The amount being burned
	* @param index The new liquidity index of the reserve
	**/
	function burn(
		address sharer,
		address sharee,
		uint256 userType,
		uint256 amount,
		uint256 index
	) external override onlyLendingPool {
		Sharer storage _sharer = _sharers[sharer][sharee];
		require(sharer.active, Errors.CT_INVALID_BURN_AMOUNT);


		(uint256 sharerBalance, uint256 shareeBalance) = balanceOfSharersPositionWithSharee(sharer, sharee);

		address receiver;
		if (userType == 1) {
			receiver = sharer;
			require(msg.sender == sharer, "Error: Match userType");
			if (sharerBalance == amount) {
				burnAmountScaled = _sharer.scaledAmount;
				_sharer.shareeScaled = shareeBalance.rayDiv(index);
			} else {
				burnAmountScaled = sharerBalance.rayDiv(index).sub(amount.rayDiv(index));
			}

		} else if (userType == 2) {
			receiver = sharee;
			require(msg.sender == sharee, "Error: Match userType");
			if (sharerBalance == 0 && shareeBalance > 0) {
				burnAmountScaled = amount.wadDiv(index);
			}

		}

		// require(burnAmountScaled != 0, Errors.CT_INVALID_BURN_AMOUNT);

		_sharer.index = index;

		redeem(amount, receiver)

		_burn(sharer, burnAmountScaled);

		emit Transfer(sharer, address(0), amount);
		emit Burn(sharer, receiverOfUnderlying, amount, index);
	}

	/**
	* @dev Calculates the balance of the sharer: principal balance + interest generated by the principal
	* @param sharer The sharer whose balance is calculated
	* @return The balance of the sharer
	**/
	function balanceOf(address sharer)
		public
		view
		override
		returns (uint256)
	{
		return super.balanceOf(sharer).rayMul(_pool.getReserveNormalizedIncome(_underlyingAsset));
	}

	/**
	* @dev Calculates the balance of the sharer: principal balance + interest generated by the principal
	* @param sharer The sharer whose balance is calculated
	* @return The balance of the sharer
	**/
	function balanceOfSharersPositionWithSharee(address sharer, address sharee)
		public
		view
		override
		returns (uint256, uint256)
	{
		Sharer storage _sharer = _sharers[sharer][sharee];

		uint256 balance;
		uint256 totalYield;
		uint256 shareeBalance;
		uint256 sharerBalance;
		uint256 principalBalance = _sharer.scaledAmount.rayMul(index);
		if (principalBalance == 0) {
			sharerBalance = _sharer.shareeScaled.rayMul(index);
		} else {
			balance = _sharer.scaledAmount.rayMul(_pool.getReserveNormalizedIncome(_underlyingAsset));
			totalYield = balance.sub(principalBalance);
			shareeBalance = totalYield.percentMul(_sharer.sharePercentage).add(_sharer.shareeScaled.rayMul(index));
			sharerBalance = balance.sub(shareeBalance);
		}
		return (sharerBalance, shareeBalance);
	}

	/**
	* @dev Calculates the principal balance of a sharer
	* @param sharer The sharer whose balance is calculated
	* @return The balance of the sharer
	**/
	function balanceOfSharer(address sharer)
		public
		view
		override
		returns (uint256)
	{
		uint256 shareeBalance;
		for (i = 0; i < _sharerSharees.length; i++) {
			Sharer storage _sharer = _sharers[i][sharee];
			uint256 principalBalance = _sharer.scaledAmount.rayMul(index);
			if (principalBalance == 0) {
				sharerBalance += _sharer.shareeScaled.rayMul(index);
				continue;
			}
			uint256 balance = _sharer.scaledAmount.rayMul(_pool.getReserveNormalizedIncome(_underlyingAsset));
			sharerBalance += balance.sub(principalBalance).add(_sharer.shareeScaled.rayMul(index));
			uint256 totalYield = balance.sub(principalBalance);
			if (totalYield == 0 || _sharer.sharePercentage == 0) {
				continue;
			}
			sharerBalance += totalYield.percentMul(uint256(1e4).sub(_sharer.sharePercentage));

		}
		return sharerBalance;
	}

	/**
	* @dev Calculates the balance of the sharer: principal balance + interest generated by the principal
	* @param sharer The sharer whose balance is calculated
	* @return The balance of the sharer
	**/
	function balanceOfSharerSharees(address sharer)
		public
		view
		override
		returns (uint256)
	{
		uint256 shareeBalance;
		for (i = 0; i < _sharerSharees.length; i++) {
			Sharer storage _sharer = _sharers[sharer][i];
			uint256 principalBalance = _sharer.scaledAmount.rayMul(index);
			if (principalBalance == 0) {
				sharerBalance += _sharer.shareeScaled.rayMul(index);
				continue;
			}
			uint256 balance = _sharer.scaledAmount.rayMul(_pool.getReserveNormalizedIncome(_underlyingAsset));
			uint256 totalYield = balance.sub(principalBalance);
			if (totalYield == 0 || _sharer.sharePercentage == 0 || _sharer.shareeScaled == 0) {
				continue;
			}
			shareeBalance += totalYield.percentMul(_sharer.sharePercentage).add(_sharer.shareeScaled.rayMul(index));
		}
		return shareeBalance;
	}

	/**
	* @dev Calculates the balance of the sharer: principal balance + interest generated by the principal
	* @param sharer The sharer whose balance is calculated
	* @return The balance of the sharer
	**/
	function balanceOfSharee(address sharee)
		public
		view
		override
		returns (uint256)
	{
		uint256 shareeBalance;
		for (i = 0; i < _shareeSharers.length; i++) {
			Sharer storage _sharer = _sharers[i][sharee];
			if (principalBalance == 0) {
				sharerBalance += _sharer.shareeScaled.rayMul(index);
				continue;
			}
			uint256 principalBalance = _sharer.scaledAmount.rayMul(index);
			uint256 balance = _sharer.scaledAmount.rayMul(_pool.getReserveNormalizedIncome(_underlyingAsset));
			uint256 totalYield = balance.sub(principalBalance);
			if (totalYield == 0 || _sharer.sharePercentage == 0 || _sharer.shareeScaled == 0) {
				continue;
			}
			shareeBalance += totalYield.percentMul(_sharer.sharePercentage).add(_sharer.shareeScaled.rayMul(index));
		}
		return shareeBalance;
	}

	function getSharerData(address sharer, address sharee)
		public
		view
		override
		returns (Sharer memory)
	{
		return _sharer[sharer][sharee];
	}

	/**
	* @dev Returns the scaled balance of the sharer. The scaled balance is the sum of all the
	* updated stored balance divided by the reserve's liquidity index at the moment of the update
	* @param sharer The sharer whose balance is calculated
	* @return The scaled balance of the sharer
	**/
	function scaledBalanceOf(address sharer) external view override returns (uint256) {
		return super.balanceOf(sharer);
	}

	/**
	* @dev Returns the scaled balance of the sharer and the scaled total supply.
	* @param sharer The address of the sharer
	* @return The scaled balance of the sharer
	* @return The scaled balance and the scaled total supply
	**/
	function getScaledUserBalanceAndSupply(address sharer)
		external
		view
		override
		returns (uint256, uint256)
	{
		return (super.balanceOf(sharer), super.totalSupply());
	}

	/**
	* @dev calculates the total supply of the specific avasToken
	* since the balance of every single sharer increases over time, the total supply
	* does that too.
	* @return the current total supply
	**/
	function totalSupply() public view override(IncentivizedERC20, IERC20) returns (uint256) {
		uint256 currentSupplyScaled = super.totalSupply();

		if (currentSupplyScaled == 0) {
			return 0;
		}

		return currentSupplyScaled.rayMul(_pool.getReserveNormalizedIncome(_underlyingAsset));
	}

	/**
	* @dev Returns the scaled total supply of the variable debt token. Represents sum(debt/index)
	* @return the scaled total supply
	**/
	function scaledTotalSupply() public view virtual override returns (uint256) {
		return super.totalSupply();
	}

	/**
	* @dev Returns the address of the underlying asset of this avasToken (E.g. WETH for aWETH)
	**/
	function UNDERLYING_ASSET_ADDRESS() public override view returns (address) {
		return _underlyingAsset;
	}

	/**
	* @dev Returns the address of the lending pool where this avasToken is used
	**/
	function POOL() public view returns (ILendingPool) {
		return _pool;
	}

	/**
	* @dev Transfers the underlying asset to `target`. Used by the LendingPool to transfer
	* assets in borrow(), withdraw() and flashLoan()
	* @param target The recipient of the avasTokens
	* @param amount The amount getting transferred
	* @return The amount transferred
	**/
	function transferUnderlyingTo(address target, uint256 amount)
		external
		override
		onlyLendingPool
		returns (uint256)
	{
		IERC20(_underlyingAsset).safeTransfer(target, amount);
		return amount;
	}

  /**
   * @dev Supplies underlying asset to Anchor or vault for AUST in return
   **/
  function supply(uint256 amount) public override onlyPool returns (uint256) {

      // amountBack is underlying asset we are supplying
      // this may not be the underlying asset of this avastoken
      // applied in _aggregatorSuppliedTotalScaledSupply below
      // amountBack is either actual local amount, or
      // aggregatord estimated amount
      ( , uint256 amountBack) = _aggregator.deposit(
          _underlyingAsset,
          amount,
          0,
          address(this)
      );

      return amountBack;

      emit AggregatorDeposit(
          amountBack
      );

  }

  /**
   * @dev Redeem underlying asset from Anchor or vault
   **/
  function redeem(uint256 amount, address to) public override onlyPool returns (bool) {
      // amountReturned is value of underlying we swapped to
      uint256 amountReturned = _aggregator.redeem(
          address(0),
          amount,
          to,
          _underlyingAsset
      );

      emit AggregatorRedeem(
          to,
          amount
      );

      return true;
  }

  function _mint(Sharer storage _sharer, uint256 amount) public virtual override {
    require(account != address(0), "ERC20: mint to the zero address");

    _beforeTokenTransfer(address(0), account, amount);

    _totalSupply = _totalSupply.add(amount);
    _sharer.scaledAmount = _sharer.scaledAmount.add(amount);
    emit Transfer(address(0), account, amount);

  }

  function _burn(Sharer storage _sharer, uint256 amount) public virtual override {
    require(account != address(0), "ERC20: burn from the zero address");

    _beforeTokenTransfer(account, address(0), amount);

    _sharer.scaledAmount = _sharer.scaledAmount.sub(amount, "ERC20: burn amount exceeds balance");
    _totalSupply = _totalSupply.sub(amount);
    emit Transfer(account, address(0), amount);
  }

}
