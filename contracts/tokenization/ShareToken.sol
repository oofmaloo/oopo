// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ILendingPool} from '../../interfaces/ILendingPool.sol';
import {IShareToken} from '../../interfaces/IShareToken.sol';
import {PercentageMath} from '../../libraries/PercentageMath.sol';
import {WadRayMath} from '../../libraries/WadRayMath.sol';

contract ShareToken is IERC20, IShareToken {
	using SafeMath for uint256;
	using WadRayMath for uint256;
	using PercentageMath for PercentageMath;
	using SafeERC20 for IERC20;

	IPool internal _pool;
	IPoolAddressesProvider internal _poolAddressesProvider;
	address internal _underlyingAsset;

	IBaseAggregator internal _aggregator;

	uint8 immutable private _decimals;

	// sharer is the the initiator
	// benefactor is the benefactor

	// sharer can have_many many benefactors
	// benefactors can have_many sharers
	// sharer can track all their benefactors

  struct Sharer {
  	uint256 scaledAmount;
  	uint256 benefactorScaled;
  	uint256 index;
  	uint256 sharePercentage;
  	bool allowSharePercentageUpdates, // allow updates to yield share perc
  	bool active;
  }
  // _sharer[benefactor][msg.sender] => Sharer
	mapping(address => mapping(address => Sharer)) private _sharers;
	// benefactors for the sharer
  address[] public _sharerBenefactors;
	// sharers for the benefactor
  address[] public _benefactorSharers;

	modifier onlyPool {
		require(_msgSender() == address(_pool), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
		_;
	}


	modifier onlyPoolAdmin {
		require(_msgSender() == _poolAddressesProvider.getPoolAdmin(), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
		_;
	}


  constructor(
    address provider,
    address underlyingAsset,
    uint8 decimals
	) ERC20("", "") {
    string memory underlyingAssetName = IERC20Metadata(underlyingAsset).name();
    string memory underlyingAssetSymbol = IERC20Metadata(underlyingAsset).symbol();

    string memory name = string(abi.encodePacked("Share ", underlyingAssetName));
    string memory symbol = string(abi.encodePacked("share", underlyingAssetSymbol));

    _decimals = decimals;
    _setDecimals(decimals);
    _setName(name);
    _setSymbol(symbol);

    _poolAddressesProvider = IPoolAddressesProvider(provider);
    _pool = IPool(_poolAddressesProvider.getPool());
    _underlyingAsset = underlyingAsset;
    initAggregator(aggregator)
  }

  function initAggregator(address aggregator) public onlyPoolAdmin {
  	_aggregator = IBaseAggregator(aggregator);
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
		address benefactor,
		uint256 amount,
		uint256 sharePercentage,
		bool allowSharePercentageUpdates,
		uint256 index
	) external override onlyLendingPool {
		require(sharePercentage <= 1e4 && sharePercentage > 0, Errors.CT_INVALID_MINT_AMOUNT);

		Sharer storage _sharer = _sharers[sharer][benefactor];

		bool active = _updateBalances(sharer, index);

		if (!active) {
			_sharer.active = true;
			_sharer.allowSharePercentageUpdates = allowSharePercentageUpdates;
			_sharer.sharePercentage = sharePercentage;
			_benefactorSharers.push(sharer);
			_sharerBenefactors.push(benefactor);
		}

		supply(amount);

		uint256 amountScaled = amount.rayDiv(index);
		require(amountScaled != 0, Errors.CT_INVALID_MINT_AMOUNT);

		// mint scaled to sharer benefactor struct 
		// _sharer.scaledAmount += amountScaled;
		// update index of sharer benefactor struct
		_sharer.index = index;
		_mint(_sharer, amountScaled);

		emit Transfer(address(0), sharer, amount);
		emit Mint(sharer, amount, index);
	}

	/**
	* @dev Sets the share percentage for a benefactor by a sharer
	* - Only updated if original mint `allowSharePercentageUpdates` 
	**/
	function setSharePercentage(address sharer, address benefactor) external {
			require(msg.sender == sharer);
			require(sharePercentage <= 1e4, Errors.CT_INVALID_MINT_AMOUNT);
			Sharer storage _sharer = _sharers[sharer][benefactor];
			require(_sharer.active);
			require(_sharer.allowSharePercentageUpdates);
			_sharer.sharePercentage = sharePercentage;
	}

	/**
	* @dev Burns avasTokens from `sharer` and sends the equivalent amount of underlying to `receiverOfUnderlying`
	* - Only callable by the LendingPool, as extra state updates there need to be managed
	* @param sharer The owner of the avasTokens, getting them burned
	* @param benefactor The owner of the avasTokens, getting them burned
	* @param userType The address that will receive the underlying
	* @param amount The amount being burned
	* @param index The new liquidity index of the reserve
	**/
	function burn(
		address sharer,
		address benefactor,
		uint256 userType,
		uint256 amount,
		uint256 index
	) external override onlyLendingPool {
		Sharer storage _sharer = _sharers[sharer][benefactor];
		require(sharer.active, Errors.CT_INVALID_BURN_AMOUNT);

		bool active = _updateBalances(sharer, index);

		(uint256 sharerBalance, uint256 benefactorBalance) = balanceOfSharersPositionWithBenefactor(sharer, benefactor);

		address receiver;
		if (userType == 1) {
			receiver = sharer;
			require(msg.sender == sharer, "Error: Match userType");
			if (sharerBalance == amount) {
				burnAmountScaled = _sharer.scaledAmount;
				_sharer.benefactorScaled = benefactorBalance.rayDiv(index);
			} else {
				burnAmountScaled = sharerBalance.rayDiv(index).sub(amount.rayDiv(index));
			}

		} else if (userType == 2) {
			receiver = benefactor;
			require(msg.sender == benefactor, "Error: Match userType");
			if (sharerBalance == 0 && benefactorBalance > 0) {
				burnAmountScaled = amount.wadDiv(index);
			}

		}

		_sharer.index = index;

		redeem(amount, receiver)

		_burn(sharer, burnAmountScaled);

		emit Transfer(sharer, address(0), amount);
		emit Burn(sharer, receiverOfUnderlying, amount, index);
	}

	function updateBalances(address sharer, address benefactor) public returns (uint256, uint256) {

		// call accrue here 

		// accrue()?
		Sharer storage _sharer = _sharers[sharer][benefactor];

		bool active = _updateBalances(sharer, index);

		if (!_sharer.active) {
			return (0,0);
		}

		uint256 _index = _sharer.index;
		returns (_sharer.scaledAmount.rayMul(_index) , _sharer.benefactorScaled.rayMul(_index))

	}

	function _updateBalances(Sharer storage _sharer, uint256 currentIndex) internal returns (bool) {
		if (!_sharer.active) {
			return false;
		}
		uint256 sharerPrincipal = _sharer.scaledAmount.rayMul(_sharer.index);
		uint256 balance = _sharer.scaledAmount.rayMul(currentIndex);
		uint256 appreciation = balance.sub(sharerPrincipal);
		uint256 sendToBenefactorScaled = appreciation.percentMul(_sharer.sharePercentage).rayDiv(currentIndex);

		// update sharer and benefactor scaled balance
		_sharer.scaledAmount -= sendToBenefactorScaled;
		_sharer.benefactorScaled += sendToBenefactorScaled;
		return true;
	}


	function getBalances(address sharer, address benefactor, uint256 index) public view returns (uint256, uint256) {
		Sharer storage _sharer = _sharers[sharer][benefactor];

		if (!_sharer.active) {
			return (0,0);
		}

		uint256 indexSim = _pool.getReserveNormalizedIncome(_underlyingAsset);

		(uint256 sharerBalance, uint256 benefactorBalance) = _getBalances(Sharer storage _sharer, indexSim);
		returns (sharerBalance, benefactorBalance);
	}

	function _getBalances(Sharer storage _sharer, uint256 currentIndex) internal returns (uint256, uint256) {
		// sharer balances
		uint256 sharerPrincipal = _sharer.scaledAmount.rayMul(_sharer.index);
		uint256 balance = _sharer.scaledAmount.rayMul(currentIndex);

		// benefactor
		uint256 currentBenefactorBalance = _sharer.benefactorScaled.rayMul(_sharer.index);

		// appreciation since last update
		uint256 appreciation = balance.sub(sharerPrincipal);
		// appreciation share to benefactor
		uint256 sendToBenefactor = appreciation.percentMul(_sharer.sharePercentage);

		return (balance.sub(sendToBenefactor).rayMul(currentIndex), currentBenefactorBalance.add(sendToBenefactor).rayMul(currentIndex));
	}

	function balanceOfBenefactor(address benefactor) external override returns (uint256) {
		uint256 balance;
		for (i = 0; i < _benefactorSharers.length; i++) {
			address sharer = i;
			Sharer storage _sharer = _sharers[i][benefactor];
			uint256 indexSim = _pool.getReserveNormalizedIncome(_underlyingAsset);
			( , uint256 benefactorBalance) = _getBalances(_sharer, indexSim)
			balance += benefactorBalance;
		}
		return balance;
	}

	function balanceOfSharer(address sharer) external override returns (uint256) {
		uint256 balance;
		for (i = 0; i < _sharerBenefactors.length; i++) {
			address sharer = i;
			Sharer storage _sharer = _sharers[sharer][i];
			uint256 indexSim = _pool.getReserveNormalizedIncome(_underlyingAsset);
			(uint256 sharerBalance, ) = _getBalances(_sharer, indexSim)
			balance += sharerBalance;
		}
		return balance;
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

	function getSharerData(address sharer, address benefactor)
		public
		view
		override
		returns (Sharer memory)
	{
		return _sharer[sharer][benefactor];
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
