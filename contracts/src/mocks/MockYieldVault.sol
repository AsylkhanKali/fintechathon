// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IYieldVault} from "../interfaces/IYieldVault.sol";
import {MockUSDC} from "./MockUSDC.sol";

/// @title MockYieldVault
/// @notice SIMULATED yield venue the demo can control. Not a real protocol; zero-value tokens only.
///         Share-based accounting; interest accrues on elapsed time at `rateBps` per year and is
///         paid by minting MockUSDC (this vault must be a MockUSDC minter).
contract MockYieldVault is IYieldVault, Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;

    MockUSDC public immutable token;

    uint256 public rateBps;
    uint256 public utilizationBps;
    bool public withdrawalsPaused;

    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;
    /// @dev Tracked internally (not token.balanceOf) so donations cannot move the share price.
    uint256 public storedAssets;
    uint256 public lastAccrual;

    event Deposit(address indexed caller, address indexed receiver, uint256 amount, uint256 shares);
    event Withdraw(address indexed caller, address indexed receiver, uint256 amount, uint256 shares);
    event Accrued(uint256 interest, uint256 elapsed);
    event RateSet(uint256 rateBps);
    event UtilizationSet(uint256 utilizationBps);
    event WithdrawalsPausedSet(bool paused);

    error WithdrawalsPaused();
    error InsufficientBalance();
    error InvalidAmount();
    error InvalidBps();

    constructor(MockUSDC token_, address owner_, uint256 rateBps_) Ownable(owner_) {
        token = token_;
        rateBps = rateBps_;
        lastAccrual = block.timestamp;
    }

    // ---------------------------------------------------------------- user

    function deposit(uint256 amount, address receiver) external {
        if (amount == 0) revert InvalidAmount();
        _accrue(0);
        uint256 shares = (totalShares == 0 || storedAssets == 0) ? amount : amount * totalShares / storedAssets;
        if (shares == 0) revert InvalidAmount();
        storedAssets += amount;
        totalShares += shares;
        sharesOf[receiver] += shares;
        IERC20(address(token)).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, receiver, amount, shares);
    }

    /// @notice Withdraws `amount` of the caller's position to `receiver`.
    function withdraw(uint256 amount, address receiver) external {
        if (withdrawalsPaused) revert WithdrawalsPaused();
        if (amount == 0) revert InvalidAmount();
        _accrue(0);
        if (amount > storedAssets) revert InsufficientBalance();
        // Round shares up so withdrawing exactly balanceOf() always works and never over-burns value.
        uint256 shares = Math.mulDiv(amount, totalShares, storedAssets, Math.Rounding.Ceil);
        if (shares > sharesOf[msg.sender]) revert InsufficientBalance();
        sharesOf[msg.sender] -= shares;
        totalShares -= shares;
        storedAssets -= amount;
        IERC20(address(token)).safeTransfer(receiver, amount);
        emit Withdraw(msg.sender, receiver, amount, shares);
    }

    function balanceOf(address account) external view returns (uint256) {
        if (totalShares == 0) return 0;
        return sharesOf[account] * totalAssets() / totalShares;
    }

    /// @return Assets under management including interest not yet minted.
    function totalAssets() public view returns (uint256) {
        return storedAssets + _interest(block.timestamp - lastAccrual);
    }

    // --------------------------------------------------------------- owner

    function setRateBps(uint256 rateBps_) external onlyOwner {
        _accrue(0);
        rateBps = rateBps_;
        emit RateSet(rateBps_);
    }

    /// @notice Risk signal read by the off-chain monitor; has no effect on vault logic.
    function setUtilizationBps(uint256 utilizationBps_) external onlyOwner {
        if (utilizationBps_ > BPS) revert InvalidBps();
        utilizationBps = utilizationBps_;
        emit UtilizationSet(utilizationBps_);
    }

    /// @notice Simulates a liquidity freeze: withdrawals revert while paused.
    function setWithdrawalsPaused(bool paused) external onlyOwner {
        withdrawalsPaused = paused;
        emit WithdrawalsPausedSet(paused);
    }

    /// @notice Adds interest as if `seconds_` extra seconds had passed, so yield is visible in a short demo.
    function simulateAccrual(uint256 seconds_) external onlyOwner {
        _accrue(seconds_);
    }

    // ------------------------------------------------------------ internal

    function _accrue(uint256 extraSeconds) internal {
        uint256 elapsed = block.timestamp - lastAccrual + extraSeconds;
        lastAccrual = block.timestamp;
        uint256 interest = _interest(elapsed);
        if (interest == 0) return;
        storedAssets += interest;
        token.mint(address(this), interest);
        emit Accrued(interest, elapsed);
    }

    function _interest(uint256 elapsed) internal view returns (uint256) {
        return storedAssets * rateBps * elapsed / (BPS * 365 days);
    }
}
