// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice The minimal yield-venue interface the Treasury talks to.
interface IYieldVault {
    function deposit(uint256 amount, address receiver) external;
    function withdraw(uint256 amount, address receiver) external;
    /// @return Current position of `account`, including accrued interest.
    function balanceOf(address account) external view returns (uint256);
}
