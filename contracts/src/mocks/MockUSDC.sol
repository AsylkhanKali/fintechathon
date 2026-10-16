// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockUSDC
/// @notice ZERO-VALUE testnet stand-in for USDC. Not backed, not redeemable, not for sale.
contract MockUSDC is ERC20, Ownable {
    uint256 public constant FAUCET_MAX = 1_000_000e6;

    mapping(address => bool) public isMinter;

    event MinterSet(address indexed account, bool allowed);

    error NotMinter();
    error FaucetLimit();

    constructor(address owner_) ERC20("Mock USD Coin (testnet, zero value)", "mUSDC") Ownable(owner_) {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function setMinter(address account, bool allowed) external onlyOwner {
        isMinter[account] = allowed;
        emit MinterSet(account, allowed);
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != owner() && !isMinter[msg.sender]) revert NotMinter();
        _mint(to, amount);
    }

    /// @notice Public demo faucet, capped per call.
    function faucet(address to, uint256 amount) external {
        if (amount > FAUCET_MAX) revert FaucetLimit();
        _mint(to, amount);
    }
}
