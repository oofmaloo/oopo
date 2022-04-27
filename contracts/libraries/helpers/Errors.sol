// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

/**
 * @title Errors library
 * @author Aave
 * @notice Defines the error messages emitted by the different contracts of the Aave protocol
 */
library Errors {
// 'The caller of the function is not a risk or pool admin'
  string public constant CALLER_NOT_ASSET_LISTING_OR_POOL_ADMIN = '5'; // 'The caller of the function is not an asset listing or pool admin'
  string public constant CALLER_NOT_BRIDGE = '6'; // 'The caller of the function is not a bridge'
  string public constant ADDRESSES_PROVIDER_NOT_REGISTERED = '7'; // 'Pool addresses provider is not registered'
  string public constant INVALID_ADDRESSES_PROVIDER_ID = '8'; // 'Invalid id for the pool addresses provider'
  string public constant NOT_CONTRACT = '9'; // 'Address is not a contract'
  string public constant RL_RESERVE_ALREADY_INITIALIZED = '10';
  string public constant RL_LIQUIDITY_INDEX_OVERFLOW = '11';
  string public constant MATH_MULTIPLICATION_OVERFLOW = '12';
  string public constant MATH_ADDITION_OVERFLOW = '13';
  string public constant MATH_DIVISION_BY_ZERO = '14';
  string public constant INVALID_AMOUNT = '15';


  string public constant VL_INVALID_AMOUNT = '16';
  string public constant VL_NO_ACTIVE_RESERVE = '17';
  string public constant VL_NOT_ENOUGH_AVAILABLE_USER_BALANCE = '18';

  string public constant VL_INVALID_INTEREST_RATE_MODE_SELECTED = '19';

}