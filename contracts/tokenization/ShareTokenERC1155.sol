// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.10;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {IPool} from '../interfaces/IPool.sol';
import {IAggregator} from '../interfaces/IAggregator.sol';

import {IShareToken} from '../interfaces/IShareToken.sol';
import {PercentageMath} from '../libraries/math/PercentageMath.sol';
import {WadRayMath} from '../libraries/math/WadRayMath.sol';

import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import "hardhat/console.sol";

interface IShareTokenERC1155 {
  function name() external view returns (string memory);

  function symbol() external view returns (string memory);

  function decimals() external view returns (uint8);

  function totalSupply() external view returns (uint256);

  function balanceOf(address account) external view returns (uint256);
}

contract ShareTokenERC1155 is Context, ERC1155Supply, IShareTokenERC1155, IShareToken {
	using SafeMath for uint256;
	using WadRayMath for uint256;
	using PercentageMath for uint256;
	using SafeERC20 for IERC20;

	/**
	* @dev TOTAL used for tracking totalSupply
	*/
	uint256 public constant TOTAL = 0; // read-only
	/**
	* @dev BENEFACTOR tracks a benefactors universal balance
	* - This is the benefactors actual balance
	* - The Sharer Account is data only for benefactor
	* 		- Used for Sharer to track output
	*/
	uint256 public constant BENEFACTOR = 1; // read|write

	IPool internal _pool;
	IPoolAddressesProvider internal _poolAddressesProvider;
	address internal _underlyingAsset;

	IAggregator internal _aggregator;

	uint8 immutable private _decimals;

  string private _name;
  string private _symbol;
	// sharer is the the initiator
	// benefactor is the benefactor

	// sharer can have_many many benefactors
	// benefactors can have_many sharers
	// sharer can track all their benefactors

  // struct Sharer {
  // 	uint256 scaledAmount;
  // 	uint256 benefactorScaled;
  // 	uint256 index;
  // 	uint256 sharePercentage;
  // 	bool allowSharePercentageUpdates; // allow updates to yield share perc
  // 	bool active;
  // }

  // _sharer[benefactor][msg.sender] => Sharer
	mapping(address => mapping(address => Sharer)) private _sharers;
	// benefactors for the sharer
  address[] public _sharerBenefactors;
	// sharers for the benefactor
  address[] public _benefactorSharers;

	modifier onlyPool {
		require(_msgSender() == address(_pool), "Errors.CT_CALLER_MUST_BE_LENDING_POOL");
		_;
	}


	modifier onlyPoolAdmin {
		require(_msgSender() == _poolAddressesProvider.getPoolAdmin(), "Errors.CT_CALLER_MUST_BE_LENDING_POOL");
		_;
	}

	event BalanceUpdate (
		address sharer,
		address benefactor,
		uint256 amount
	);

	event AggregatorRedeem (
		address indexed to,
		uint256 amount
	);

  event AggregatorDeposit(
		uint256 amountBack
  );

  // event AggregatorDeposit(
		// address indexed sharer,
		// address indexed benefactor,
		// uint256 amountBack
  // );

  constructor(
    address provider,
    address underlyingAsset,
    uint8 decimals,
    address aggregator
	) ERC1155("") {
    string memory underlyingAssetName = IERC20Metadata(underlyingAsset).name();
    string memory underlyingAssetSymbol = IERC20Metadata(underlyingAsset).symbol();

    string memory name = string(abi.encodePacked("Share ", underlyingAssetName));
    string memory symbol = string(abi.encodePacked("share", underlyingAssetSymbol));

    _decimals = decimals;
		_name = name;
		_symbol = symbol;


    _poolAddressesProvider = IPoolAddressesProvider(provider);
    _pool = IPool(_poolAddressesProvider.getPool());
    _underlyingAsset = underlyingAsset;
    _aggregator = IAggregator(aggregator);
    IERC20(_underlyingAsset).safeIncreaseAllowance(aggregator, type(uint256).max);
  }

  function initAggregator(address aggregator) public onlyPoolAdmin {
  	_aggregator = IAggregator(aggregator);
    IERC20(_underlyingAsset).safeIncreaseAllowance(aggregator, type(uint256).max);
  }

	/**
	* @dev Mints `amount` shareTokens to `sharer`
	* - Only callable by the LendingPool, as extra state updates there need to be managed
	* - Sends portion of designated assets to aggregation
	* @param sharer The address receiving the minted tokens
	* @param benefactor The amount of tokens getting minted
	* @param amount The new liquidity index of the reserve
	* @param sharePercentage The percentage of appreciation to share to benefactor as 100.00%
	* @param allowSharePercentageUpdates The new liquidity index of the reserve
	* @param index The new liquidity index of the reserve

	* - Once allowSharePercentageUpdates is set, it cannot be updated
	* 
	* - If account already ini, don't create new one
	* - Send to aggregation
	* - Update account
	* - Mint to main data tracker
	*/
	function mint(
		address sharer,
		address benefactor,
		uint256 amount,
		uint256 sharePercentage,
		bool allowSharePercentageUpdates,
		uint256 index
	) external override onlyPool {
		require(sharePercentage <= 1e4 && sharePercentage > 0, "Errors.CT_INVALID_MINT_AMOUNT");

		Sharer storage _sharer = _sharers[sharer][benefactor];

		bool active = _updateBalances(_sharer, benefactor, index);

		if (!active) {
			_sharer.active = true;
			_sharer.allowSharePercentageUpdates = allowSharePercentageUpdates;
			_sharer.sharePercentage = sharePercentage;
			_benefactorSharers.push(sharer);
			_sharerBenefactors.push(benefactor);
		}

		supply(amount);

		uint256 amountScaled = amount.rayDiv(index);
		require(amountScaled != 0, "Errors.CT_INVALID_MINT_AMOUNT");

		// mint scaled to sharer benefactor struct 
		_sharer.scaledAmount += amountScaled;
		// update index of sharer benefactor struct
		_sharer.index = index;

		_mint(
      sharer,
      0,
      amountScaled,
      ""
    );

		// _totalSupply = _totalSupply.add(amountScaled);

		// emit Transfer(address(0), sharer, amount);
		// emit Mint(sharer, amount, index);
	}

	/**
	* @dev Sets the share percentage for a benefactor by a sharer
	* - Only updated if original mint `allowSharePercentageUpdates` 
	**/
	function setSharePercentage(address sharer, address benefactor, uint256 sharePercentage) external {
			require(msg.sender == sharer);
			require(sharePercentage <= 1e4, "Errors.CT_INVALID_MINT_AMOUNT");
			Sharer storage _sharer = _sharers[sharer][benefactor];
			require(_sharer.active);
			require(_sharer.allowSharePercentageUpdates);
			_sharer.sharePercentage = sharePercentage;
	}

	/**
	* @dev Burns shareTokens from `sharer` and sends the equivalent amount of underlying to `receiver`
	* - Only callable by the LendingPool, as extra state updates there need to be managed
 	* @param caller The caller
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
	) external override onlyPool {
		Sharer storage _sharer = _sharers[sharer][benefactor];
		require(_sharer.active, "Errors.CT_INVALID_BURN_AMOUNT");

		bool active = _updateBalances(_sharer, benefactor, index);
		require(active, "Error: Active");
		console.log("burn active", active);

		uint256 scaledAmount = amount.rayDiv(index);

		address receiver;
		uint256 _id;
		if (userType == 1) {
			receiver = sharer;
			require(caller == sharer, "Error: Match userType");
			_sharer.scaledAmount -= scaledAmount;
		} else if (userType == 2) {
			receiver = benefactor;
			require(caller == benefactor, "Error: Match userType");
			_sharer.benefactorScaled -= scaledAmount;
			_burn(
	      receiver,
	      1,
	      scaledAmount
	    );
		}

		redeem(amount, receiver);

		_burn(
      receiver,
      0,
      scaledAmount
    );

		// _totalSupply = _totalSupply.sub(scaledAmount);

		// emit Transfer(sharer, address(0), amount);
		// emit Burn(sharer, receiver, amount, index);
	}

	// /**
	// * @dev Can be called by anyone
	// * - Only updated if original mint `allowSharePercentageUpdates` 
	// **/
	// function updateBalances(address sharer, address benefactor) external returns (uint256, uint256) {

	// 	// call accrue here 

	// 	// accrue()?
	// 	Sharer storage _sharer = _sharers[sharer][benefactor];

	// 	bool active = _updateBalances(_sharer, index);

	// 	if (!_sharer.active) {
	// 		return (0,0);
	// 	}
	// 	uint256 indexSim = _pool.getReserveNormalizedIncome(_underlyingAsset);

	// 	return (_sharer.scaledAmount.rayMul(indexSim) , _sharer.benefactorScaled.rayMul(indexSim));
	// }

	/**
	* @dev Update a benefactors balance through all sharers
	* - May revert is benefactor has multiple sharers
	**/
	function updatedBalanceOfBenefactor(address benefactor, uint256 currentIndex) external override onlyPool {
		uint256 balance;
		for (uint256 i = 0; i < _benefactorSharers.length; i++) {
			Sharer storage _sharer = _sharers[_benefactorSharers[i]][benefactor];
			_updateBalances(_sharer, benefactor, currentIndex);
		}
	}

	/**
	* @dev Update a sharers balance through all benefactors
	* - May revert is benefactor has multiple sharers
	**/
	function updatedBalanceOfSharer(address sharer, uint256 currentIndex) external override onlyPool {
		uint256 balance;
		for (uint256 i = 0; i < _sharerBenefactors.length; i++) {
			Sharer storage _sharer = _sharers[sharer][_sharerBenefactors[i]];
			_updateBalances(_sharer, _sharerBenefactors[i], currentIndex);
		}
	}

	function _updateBalances(Sharer storage _sharer, address benefactor, uint256 currentIndex) internal returns (bool) {
		if (!_sharer.active) {
			return false;
		}
		console.log("_updateBalances currentIndex", currentIndex);
		uint256 sharerPrincipal = _sharer.scaledAmount.rayMul(_sharer.index);
		console.log("_updateBalances sharerPrincipal", sharerPrincipal);
		uint256 balance = _sharer.scaledAmount.rayMul(currentIndex);
		console.log("_updateBalances balance", balance);
		uint256 appreciation = balance.sub(sharerPrincipal);
		console.log("_updateBalances appreciation", appreciation);
		uint256 sendToBenefactorScaled = appreciation.percentMul(_sharer.sharePercentage).rayDiv(currentIndex);
		console.log("_updateBalances sendToBenefactorScaled", sendToBenefactorScaled);

		// update sharer and benefactor scaled balance
		_sharer.scaledAmount -= sendToBenefactorScaled;
		_sharer.benefactorScaled += sendToBenefactorScaled;

		// _sharer.index = currentIndex; // ?

		_mint(
      benefactor,
      1,
      sendToBenefactorScaled,
      ""
    );

		return true;
	}

	function getBalances(address sharer, address benefactor) public view override returns (uint256, uint256) {
		Sharer storage _sharer = _sharers[sharer][benefactor];

		if (!_sharer.active) {
			return (0,0);
		}

		uint256 indexSim = _pool.getReserveNormalizedIncome(_underlyingAsset);

		console.log("getBalances indexSim", indexSim);
		(uint256 sharerBalance, uint256 benefactorBalance) = _getBalances(_sharer, indexSim);
		return (sharerBalance, benefactorBalance);
	}

	function _getBalances(Sharer storage _sharer, uint256 currentIndex) internal view returns (uint256, uint256) {
		// sharer balances
		uint256 sharerPrincipal = _sharer.scaledAmount.rayMul(_sharer.index);
		uint256 balance = _sharer.scaledAmount.rayMul(currentIndex);

		// benefactor
		uint256 currentBenefactorBalance = _sharer.benefactorScaled.rayMul(_sharer.index);
		console.log("_getBalances currentBenefactorBalance", currentBenefactorBalance);

		// appreciation since last update
		uint256 appreciation = balance.sub(sharerPrincipal);

		// appreciation share to benefactor
		uint256 sendToBenefactor = appreciation.percentMul(_sharer.sharePercentage);

		return (balance.sub(sendToBenefactor), currentBenefactorBalance.add(sendToBenefactor));
	}

	function balanceOfBenefactor(address benefactor) external override returns (uint256) {
		uint256 balance;
		for (uint256 i = 0; i < _benefactorSharers.length; i++) {
			Sharer storage _sharer = _sharers[_benefactorSharers[i]][benefactor];
			uint256 indexSim = _pool.getReserveNormalizedIncome(_underlyingAsset);
			( , uint256 benefactorBalance) = _getBalances(_sharer, indexSim);
			balance += benefactorBalance;
		}
		return balance;
	}

	function balanceOfSharer(address sharer) external override returns (uint256) {
		uint256 balance;
		for (uint256 i = 0; i < _sharerBenefactors.length; i++) {
			Sharer storage _sharer = _sharers[sharer][_sharerBenefactors[i]];
			uint256 indexSim = _pool.getReserveNormalizedIncome(_underlyingAsset);
			(uint256 sharerBalance, ) = _getBalances(_sharer, indexSim);
			balance += sharerBalance;
		}
		return balance;
	}

	/**
	* @dev Calculates the balance of the sharer: principal balance + interest generated by the principal
	* @param account The sharer whose balance is calculated
	* @return The balance of the sharer
	**/
	function balanceOf(address account)
		public
		view
		override
		returns (uint256)
	{
		return 0;
	}

	function getSharerData(address sharer, address benefactor)
		public
		view
		returns (Sharer memory)
	{
		return _sharers[sharer][benefactor];
	}

	/**
	* @dev Returns the scaled balance of the sharer. The scaled balance is the sum of all the
	* updated stored balance divided by the reserve's liquidity index at the moment of the update
	* @param sharer The sharer whose balance is calculated
	* @return The scaled balance of the sharer
	**/
	function scaledBalanceOf(address sharer) external view override returns (uint256) {
		return super.balanceOf(sharer, 0);
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
		return (super.balanceOf(sharer, 0), super.totalSupply(0));
	}

	/**
	* @dev calculates the total supply of the specific shareToken
	* since the balance of every single sharer increases over time, the total supply
	* does that too.
	* @return the current total supply
	**/
	function totalSupply() public view override returns (uint256) {
		uint256 currentSupplyScaled = super.totalSupply(0);

		if (currentSupplyScaled == 0) {
			return 0;
		}

		return currentSupplyScaled.rayMul(_pool.getReserveNormalizedIncome(_underlyingAsset));
	}

	/**
	* @dev Returns the scaled total supply of the variable debt token. Represents sum(debt/index)
	* @return the scaled total supply
	**/
	function scaledTotalSupply() public view override returns (uint256) {
		return super.totalSupply(0);
	}

	/**
	* @dev Returns the address of the underlying asset of this shareToken (E.g. WETH for aWETH)
	**/
	function UNDERLYING_ASSET_ADDRESS() public override view returns (address) {
		return _underlyingAsset;
	}

	/**
	* @dev Returns the address of the lending pool where this shareToken is used
	**/
	function POOL() public view returns (IPool) {
		return _pool;
	}

	/**
	* @dev Transfers the underlying asset to `target`. Used by the LendingPool to transfer
	* assets in borrow(), withdraw() and flashLoan()
	* @param target The recipient of the shareTokens
	* @param amount The amount getting transferred
	* @return The amount transferred
	**/
	function transferUnderlyingTo(address target, uint256 amount)
		external
		override
		onlyPool
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
      // this may not be the underlying asset of this sharetoken
      // applied in _aggregatorSuppliedTotalScaledSupply below
      // amountBack is either actual local amount, or
      // aggregatord estimated amount
      uint256 amountBack = _aggregator.deposit(
          _underlyingAsset,
          amount,
          0,
          address(this)
      );

      return amountBack;

      emit AggregatorDeposit(
				amount
      );

  }

  /**
   * @dev Redeem underlying asset from Anchor or vault
   **/
  function redeem(uint256 amount, address to) public override onlyPool returns (bool) {
      // amountReturned is value of underlying we swapped to
      uint256 amountReturned = _aggregator.redeem(
          _underlyingAsset,
          amount,
          to
      );

      emit AggregatorRedeem(
          to,
          amount
      );

      return true;
  }

  /**
   * @dev Returns the name of the token.
   */
  function name() public view override returns (string memory) {
      return _name;
  }

  /**
   * @dev Returns the symbol of the token, usually a shorter version of the
   * name.
   */
  function symbol() public view override returns (string memory) {
      return _symbol;
  }


  /**
   * @dev Returns the number of decimals used to get its user representation.
   * For example, if `decimals` equals `2`, a balance of `505` tokens should
   * be displayed to a user as `5.05` (`505 / 10 ** 2`).
   *
   * Tokens usually opt for a value of 18, imitating the relationship between
   * Ether and Wei. This is the value {ERC20} uses, unless this function is
   * overridden;
   *
   * NOTE: This information is only used for _display_ purposes: it in
   * no way affects any of the arithmetic of the contract, including
   * {IERC20-balanceOf} and {IERC20-transfer}.
   */
  function decimals() public view override returns (uint8) {
      return 18;
  }

}
