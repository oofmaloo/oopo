// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IAggregator {

    function setToken(address token_) external;

    function _underlyingAsset() external view returns (address);

    function _token() external view returns (address);

    /**
     * @dev Get accurate balance of tokens and update state
     */
    function accrue() external returns (uint256, uint256);

    function accrueSim() external view returns (uint256, uint256);

    /**
     * @dev Deposits underlying to Anchor or Vault and returns wrapped to `to`
     * @param asset Asset to transfer in
     * @param _amount Amount to transfer in
     * @param _minAmountOut Min amount our on swap
     * @param to Address to send wrapped to
     */
    function deposit(address asset, uint256 _amount, uint256 _minAmountOut, address to) external returns (uint256);

    function redeem(address asset, uint256 _amount, address to) external returns (uint256);
}
