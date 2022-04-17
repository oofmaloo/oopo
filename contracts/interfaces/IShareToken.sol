// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ILendingPool} from '../../interfaces/ILendingPool.sol';
import {IShareToken} from '../../interfaces/IShareToken.sol';

contract ShareToken is IERC20, IShareToken {
	using WadRayMath for uint256;
	using SafeERC20 for IERC20;

	// sharer is the the initiator
	// benefactor is the benefactor

	// sharer can have_many many benefactors
	// benefactors can have_many sharers
	// sharer can track all their benefactors

  struct Sharer {
  	uint256 scaledAmount;
  	uint256 index;
  	uint256 sharePercentage;
  	uint256 benefactorScaled; // releases here on full sharer withdraw
  	bool allowSharePercentageUpdates,
  	bool active;
  }
  // _sharer[benefactor][msg.sender] => Sharer
	mapping(address => mapping(address => Sharer)) private _sharers;
	// benefactors for the sharer
  address[] external _sharerBenefactors;
	// sharers for the benefactor
  address[] external _benefactorSharers;



	IPool internal _pool;
	address internal _underlyingAsset;

	modifier onlyPool {
		require(_msgSender() == address(_pool), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
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

    ADDRESSES_PROVIDER = IPoolAddressesProvider(provider);
    _pool = IPool(ADDRESSES_PROVIDER.getPool());
    _underlyingAsset = underlyingAsset;
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
	) external;

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
	) external;

	function updateBalances(address sharer, address benefactor) external returns (uint256, uint256);

	function getBalances(address sharer, address benefactor, uint256 index) external view returns (uint256, uint256);

	function balanceOfBenefactor(address benefactor) external returns (uint256);

	function balanceOfSharer(address sharer) external returns (uint256);

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
	* @dev Returns the scaled total supply of the variable debt token. Represents sum(debt/index)
	* @return the scaled total supply
	**/
	function scaledTotalSupply() external view virtual returns (uint256);

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
		returns (uint256);

  /**
   * @dev Supplies underlying asset to Anchor or vault for AUST in return
   **/
  function supply(uint256 amount) external override onlyPool returns (uint256);

  /**
   * @dev Redeem underlying asset from Anchor or vault
   **/
  function redeem(uint256 amount, address to) external override onlyPool returns (bool);

  function _mint(Sharer storage _sharer, uint256 amount) external virtual override;

  function _burn(Sharer storage _sharer, uint256 amount) external virtual override;

}
