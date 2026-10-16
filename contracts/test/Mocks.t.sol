// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BaseTest} from "./Base.t.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockYieldVault} from "../src/mocks/MockYieldVault.sol";
import {MockPriceFeed} from "../src/mocks/MockPriceFeed.sol";

contract MockUSDCTest is BaseTest {
    function test_metadata() public view {
        assertEq(usdc.name(), "Mock USD Coin (testnet, zero value)");
        assertEq(usdc.symbol(), "mUSDC");
        assertEq(usdc.decimals(), 6);
    }

    function test_onlyOwnerOrMinterCanMint() public {
        vm.prank(stranger);
        vm.expectRevert(MockUSDC.NotMinter.selector);
        usdc.mint(stranger, 1);

        vm.prank(address(vault)); // vault is a minter
        usdc.mint(stranger, 5);
        vm.prank(owner);
        usdc.mint(stranger, 5);
        assertEq(usdc.balanceOf(stranger), 10);
    }

    function test_setMinterOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        usdc.setMinter(stranger, true);
    }

    function test_faucetIsCapped() public {
        uint256 max = usdc.FAUCET_MAX();
        vm.startPrank(stranger);
        usdc.faucet(stranger, max);
        vm.expectRevert(MockUSDC.FaucetLimit.selector);
        usdc.faucet(stranger, max + 1);
        vm.stopPrank();
        assertEq(usdc.balanceOf(stranger), max);
    }
}

contract MockPriceFeedTest is BaseTest {
    function test_aggregatorV3Shape() public view {
        assertEq(feed.decimals(), 8);
        assertEq(feed.version(), 1);
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            feed.latestRoundData();
        assertEq(roundId, 1);
        assertEq(answer, 1e8);
        assertEq(startedAt, T0);
        assertEq(updatedAt, T0);
        assertEq(answeredInRound, 1);
    }

    function test_setPriceStartsNewRound() public {
        vm.warp(T0 + 1 hours);
        vm.prank(owner);
        feed.setPrice(97_000_000); // depeg to 0.97

        (uint80 roundId, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        assertEq(roundId, 2);
        assertEq(answer, 97_000_000);
        assertEq(updatedAt, T0 + 1 hours);
        (, int256 old,,,) = feed.getRoundData(1);
        assertEq(old, 1e8);
    }

    function test_unknownRoundReverts() public {
        vm.expectRevert(MockPriceFeed.RoundNotFound.selector);
        feed.getRoundData(99);
    }

    function test_setPriceOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        feed.setPrice(1);
    }
}

contract MockYieldVaultTest is BaseTest {
    function setUp() public override {
        super.setUp();
        vm.prank(owner);
        usdc.mint(alice, 1_000_000 * USDC);
        vm.prank(owner);
        usdc.mint(bob, 1_000_000 * USDC);
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
    }

    function test_depositWithdrawRoundTrip() public {
        vm.startPrank(alice);
        vault.deposit(100_000 * USDC, alice);
        assertEq(vault.balanceOf(alice), 100_000 * USDC);
        vault.withdraw(40_000 * USDC, alice);
        vm.stopPrank();
        assertEq(vault.balanceOf(alice), 60_000 * USDC);
        assertEq(usdc.balanceOf(alice), 940_000 * USDC);
    }

    function test_realTimeAccrualAtAnnualRate() public {
        vm.prank(alice);
        vault.deposit(100_000 * USDC, alice);
        vm.warp(T0 + 365 days);
        assertEq(vault.balanceOf(alice), 105_000 * USDC); // 5% APY, simple per accrual
    }

    function test_simulateAccrualMintsInterest() public {
        vm.prank(alice);
        vault.deposit(365_000 * USDC, alice);
        uint256 supplyBefore = usdc.totalSupply();
        vm.prank(owner);
        vault.simulateAccrual(1 days);
        // 365,000 x 5% / 365 = 50 mUSDC
        assertEq(vault.balanceOf(alice), 365_050 * USDC);
        assertEq(usdc.totalSupply(), supplyBefore + 50 * USDC);
    }

    function test_interestSplitsProRata() public {
        vm.prank(alice);
        vault.deposit(300_000 * USDC, alice);
        vm.prank(bob);
        vault.deposit(100_000 * USDC, bob);
        vm.prank(owner);
        vault.simulateAccrual(365 days); // +20,000 total
        assertEq(vault.balanceOf(alice), 315_000 * USDC);
        assertEq(vault.balanceOf(bob), 105_000 * USDC);
    }

    function testFuzz_withdrawFullBalanceAlwaysWorks(uint256 a, uint256 b, uint256 secs) public {
        // Sub-share dust deposits are rejected by design (InvalidAmount), so start at 1 mUSDC.
        a = bound(a, USDC, 1_000_000 * USDC);
        b = bound(b, USDC, 1_000_000 * USDC);
        secs = bound(secs, 0, 3 * 365 days);
        vm.prank(alice);
        vault.deposit(a, alice);
        vm.warp(T0 + secs / 2);
        vm.prank(bob);
        vault.deposit(b, bob);
        vm.warp(T0 + secs);

        uint256 aliceBal = vault.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(aliceBal, alice);
        uint256 bobBal = vault.balanceOf(bob);
        vm.prank(bob);
        vault.withdraw(bobBal, bob);

        assertLe(vault.balanceOf(alice), 1); // at most 1 unit of rounding dust
        assertGe(usdc.balanceOf(alice) + usdc.balanceOf(bob), 2_000_000 * USDC - 2);
    }

    function test_withdrawalsPausedFreezesExits() public {
        vm.prank(alice);
        vault.deposit(100_000 * USDC, alice);
        vm.prank(owner);
        vault.setWithdrawalsPaused(true);
        vm.prank(alice);
        vm.expectRevert(MockYieldVault.WithdrawalsPaused.selector);
        vault.withdraw(1, alice);
    }

    function test_cannotWithdrawOthersFunds() public {
        vm.prank(alice);
        vault.deposit(100_000 * USDC, alice);
        vm.prank(bob);
        vm.expectRevert(MockYieldVault.InsufficientBalance.selector);
        vault.withdraw(1, bob);
        vm.prank(alice);
        vm.expectRevert(MockYieldVault.InsufficientBalance.selector);
        vault.withdraw(100_000 * USDC + 1, alice);
    }

    function test_zeroAmountsRevert() public {
        vm.startPrank(alice);
        vm.expectRevert(MockYieldVault.InvalidAmount.selector);
        vault.deposit(0, alice);
        vm.expectRevert(MockYieldVault.InvalidAmount.selector);
        vault.withdraw(0, alice);
        vm.stopPrank();
    }

    function test_donationDoesNotMoveSharePrice() public {
        vm.prank(alice);
        vault.deposit(100_000 * USDC, alice);
        vm.prank(bob);
        usdc.transfer(address(vault), 500_000 * USDC);
        assertEq(vault.balanceOf(alice), 100_000 * USDC);
    }

    function test_ownerRiskControls() public {
        vm.startPrank(owner);
        vault.setUtilizationBps(9_500);
        vault.setRateBps(800);
        vm.expectRevert(MockYieldVault.InvalidBps.selector);
        vault.setUtilizationBps(10_001);
        vm.stopPrank();
        assertEq(vault.utilizationBps(), 9_500);
        assertEq(vault.rateBps(), 800);

        vm.startPrank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vault.simulateAccrual(1 days);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vault.setWithdrawalsPaused(true);
        vm.stopPrank();
    }
}
