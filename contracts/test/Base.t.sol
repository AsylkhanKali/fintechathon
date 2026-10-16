// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Treasury} from "../src/Treasury.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockYieldVault} from "../src/mocks/MockYieldVault.sol";
import {MockPriceFeed} from "../src/mocks/MockPriceFeed.sol";

/// @notice Shared fixture using the finance-team demo policy (amounts in 6-decimal mUSDC).
abstract contract BaseTest is Test {
    uint256 internal constant USDC = 1e6;
    uint256 internal constant APPROVAL_THRESHOLD = 40_000 * USDC;
    uint256 internal constant PER_PAYMENT_CAP = 100_000 * USDC;
    uint256 internal constant DAILY_CAP = 600_000 * USDC;
    uint256 internal constant MAX_VAULT_SHARE_BPS = 6_000;
    uint256 internal constant START_BALANCE = 4_000_000 * USDC;
    uint256 internal constant VAULT_RATE_BPS = 500;
    /// Mid-day UTC, so tests can cross a day boundary deliberately.
    uint256 internal constant T0 = 20_000 days + 12 hours;

    address internal owner = makeAddr("owner");
    address internal agent = makeAddr("agent");
    address internal stranger = makeAddr("stranger");
    address internal attacker = makeAddr("attacker");
    address internal alice = makeAddr("contributor-alice");
    address internal bob = makeAddr("contributor-bob");
    address internal vendor = makeAddr("vendor-cloud");

    MockUSDC internal usdc;
    MockPriceFeed internal feed;
    MockYieldVault internal vault;
    Treasury internal treasury;

    function setUp() public virtual {
        vm.warp(T0);
        vm.startPrank(owner);
        usdc = new MockUSDC(owner);
        feed = new MockPriceFeed(owner, 1e8);
        vault = new MockYieldVault(usdc, owner, VAULT_RATE_BPS);
        usdc.setMinter(address(vault), true);

        treasury = new Treasury(usdc, owner, agent);
        treasury.setCaps(PER_PAYMENT_CAP, APPROVAL_THRESHOLD, DAILY_CAP);
        treasury.setMaxVaultShareBps(MAX_VAULT_SHARE_BPS);
        treasury.setVault(address(vault), true);
        address[] memory payees = new address[](3);
        payees[0] = alice;
        payees[1] = bob;
        payees[2] = vendor;
        treasury.setPayees(payees, true);
        usdc.mint(address(treasury), START_BALANCE);
        vm.stopPrank();
    }

    /// @dev The finance spec's 60-person payroll: team size x average salary = 481,000 total.
    function _payroll() internal returns (address[] memory payees, uint256[] memory amounts) {
        uint8[5] memory people = [25, 10, 8, 10, 7];
        uint16[5] memory salary = [9_000, 8_500, 8_000, 6_500, 6_000];
        payees = new address[](60);
        amounts = new uint256[](60);
        uint256 k;
        for (uint256 t; t < 5; ++t) {
            for (uint256 i; i < people[t]; ++i) {
                payees[k] = makeAddr(string.concat("contributor-", vm.toString(k)));
                amounts[k] = uint256(salary[t]) * USDC;
                ++k;
            }
        }
        vm.prank(owner);
        treasury.setPayees(payees, true);
    }

    function _deposit(uint256 amount) internal {
        vm.prank(agent);
        treasury.depositToVault(address(vault), amount);
    }

    function _request(address payee, uint256 amount) internal returns (uint256 id) {
        vm.prank(agent);
        id = treasury.requestPayment(payee, amount, keccak256("invoice"));
    }
}
