// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BaseTest} from "./Base.t.sol";
import {Treasury} from "../src/Treasury.sol";
import {MockYieldVault} from "../src/mocks/MockYieldVault.sol";

/// @notice PRD section 8 contract tests C1-C12, plus tests for the hardening additions.
///         Run one group with e.g. `forge test --mt C5`.
contract TreasuryTest is BaseTest {
    bytes32 internal constant REF = keccak256("payroll:2026-11");

    // =====================================================================
    // C1  Agent calls owner functions -> NotOwner
    // =====================================================================

    function test_C1_agentCannotChangeRules() public {
        uint256 id = _request(vendor, 50_000 * USDC);
        address[] memory list = new address[](1);
        list[0] = attacker;

        vm.startPrank(agent);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.setPayee(attacker, true);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.setPayees(list, true);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.setCaps(type(uint256).max, type(uint256).max, type(uint256).max);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.setMaxVaultShareBps(10_000);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.setAgent(attacker);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.setPolicyHash(keccak256("evil policy"));
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.setVault(address(usdc), true);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.pause();
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.unpause();
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.approvePayment(id);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.rejectPayment(id);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.ownerWithdraw(attacker, 1);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.transferOwnership(attacker);
        vm.stopPrank();

        assertFalse(treasury.isPayee(attacker));
        assertEq(treasury.perPaymentCap(), PER_PAYMENT_CAP);
        assertEq(treasury.approvalThreshold(), APPROVAL_THRESHOLD);
        assertEq(treasury.dailyPaymentCap(), DAILY_CAP);
        assertEq(treasury.agent(), agent);
        assertEq(treasury.owner(), owner);
        assertEq(treasury.policyHash(), bytes32(0));
        assertEq(usdc.balanceOf(attacker), 0);
    }

    function test_C1_agentCannotUnpause() public {
        vm.prank(owner);
        treasury.pause();
        vm.prank(agent);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.unpause();
        assertTrue(treasury.paused());
    }

    function testFuzz_C1_nonOwnerCannotChangeRules(address caller) public {
        vm.assume(caller != owner);
        vm.startPrank(caller);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.setPayee(caller == address(0) ? attacker : caller, true);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.setCaps(1, 1, 1);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.setAgent(caller);
        vm.stopPrank();
    }

    // =====================================================================
    // C2  Agent pays non-allowlisted address -> PayeeNotAllowed
    // =====================================================================

    function test_C2_payToUnknownAddressReverts() public {
        vm.prank(agent);
        vm.expectRevert(Treasury.PayeeNotAllowed.selector);
        treasury.pay(attacker, 1_000 * USDC, REF);
        assertEq(usdc.balanceOf(attacker), 0);
    }

    function test_C2_payBatchWithOneUnknownAddressRevertsAtomically() public {
        address[] memory payees = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        (payees[0], amounts[0]) = (alice, 5_000 * USDC);
        (payees[1], amounts[1]) = (attacker, 5_000 * USDC);

        vm.prank(agent);
        vm.expectRevert(Treasury.PayeeNotAllowed.selector);
        treasury.payBatch(payees, amounts, REF);
        assertEq(usdc.balanceOf(alice), 0);
        assertEq(usdc.balanceOf(attacker), 0);
    }

    function test_C2_requestToUnknownAddressReverts() public {
        vm.prank(agent);
        vm.expectRevert(Treasury.PayeeNotAllowed.selector);
        treasury.requestPayment(attacker, 50_000 * USDC, REF);
    }

    function testFuzz_C2_payToAnyUnknownAddressReverts(address to, uint256 amount) public {
        vm.assume(!treasury.isPayee(to));
        amount = bound(amount, 1, APPROVAL_THRESHOLD - 1);
        vm.prank(agent);
        vm.expectRevert(Treasury.PayeeNotAllowed.selector);
        treasury.pay(to, amount, REF);
    }

    // =====================================================================
    // C3  Agent pay at or above approvalThreshold -> RequiresApproval
    // =====================================================================

    function test_C3_payAtThresholdRequiresApproval() public {
        vm.startPrank(agent);
        vm.expectRevert(Treasury.RequiresApproval.selector);
        treasury.pay(vendor, APPROVAL_THRESHOLD, REF);
        vm.expectRevert(Treasury.RequiresApproval.selector);
        treasury.pay(vendor, PER_PAYMENT_CAP + 1, REF);

        treasury.pay(vendor, APPROVAL_THRESHOLD - 1, REF); // one unit below: tier 0
        vm.stopPrank();
        assertEq(usdc.balanceOf(vendor), APPROVAL_THRESHOLD - 1);
    }

    function test_C3_payBatchItemAtThresholdRequiresApproval() public {
        address[] memory payees = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        (payees[0], amounts[0]) = (alice, 5_000 * USDC);
        (payees[1], amounts[1]) = (vendor, APPROVAL_THRESHOLD);

        vm.prank(agent);
        vm.expectRevert(Treasury.RequiresApproval.selector);
        treasury.payBatch(payees, amounts, REF);
    }

    function testFuzz_C3_payAboveThresholdRequiresApproval(uint256 amount) public {
        amount = bound(amount, APPROVAL_THRESHOLD, type(uint128).max);
        vm.prank(agent);
        vm.expectRevert(Treasury.RequiresApproval.selector);
        treasury.pay(vendor, amount, REF);
    }

    // =====================================================================
    // C4  requestPayment above perPaymentCap -> ExceedsPerPaymentCap
    // =====================================================================

    function test_C4_requestAboveCapReverts() public {
        vm.startPrank(agent);
        vm.expectRevert(Treasury.ExceedsPerPaymentCap.selector);
        treasury.requestPayment(vendor, PER_PAYMENT_CAP + 1, REF);

        uint256 id = treasury.requestPayment(vendor, PER_PAYMENT_CAP, REF); // exactly at cap is allowed
        vm.stopPrank();
        assertEq(id, 1);
    }

    function test_C4_requestBelowThresholdReverts() public {
        vm.prank(agent);
        vm.expectRevert(Treasury.BelowApprovalThreshold.selector);
        treasury.requestPayment(vendor, APPROVAL_THRESHOLD - 1, REF);
    }

    function testFuzz_C4_requestAboveCapReverts(uint256 amount) public {
        amount = bound(amount, PER_PAYMENT_CAP + 1, type(uint128).max);
        vm.prank(agent);
        vm.expectRevert(Treasury.ExceedsPerPaymentCap.selector);
        treasury.requestPayment(vendor, amount, REF);
    }

    // =====================================================================
    // C5  Payments in one day exceed dailyPaymentCap -> ExceedsDailyCap on the breaching call
    // =====================================================================

    function test_C5_breachingCallReverts() public {
        uint256 small = APPROVAL_THRESHOLD - 1; // 39,999.999999
        vm.startPrank(agent);
        for (uint256 i; i < 15; ++i) {
            treasury.pay(alice, small, REF); // 15 x ~40k, just under 600k
        }
        uint256 left = DAILY_CAP - 15 * small;
        vm.expectRevert(Treasury.ExceedsDailyCap.selector);
        treasury.pay(bob, left + 1, REF); // the breaching call

        treasury.pay(bob, left, REF); // exactly up to the cap is fine
        vm.expectRevert(Treasury.ExceedsDailyCap.selector);
        treasury.pay(bob, 1, REF);
        vm.stopPrank();

        assertEq(treasury.spentToday(treasury.today()), DAILY_CAP);
        assertEq(treasury.remainingDailyAllowance(), 0);
    }

    function test_C5_capResetsNextUtcDay() public {
        vm.startPrank(agent);
        for (uint256 i; i < 15; ++i) {
            treasury.pay(alice, APPROVAL_THRESHOLD - 1, REF);
        }
        vm.expectRevert(Treasury.ExceedsDailyCap.selector);
        treasury.pay(bob, 30_000 * USDC, REF);

        vm.warp(T0 + 12 hours); // next UTC day
        treasury.pay(bob, 30_000 * USDC, REF);
        vm.stopPrank();
        assertEq(treasury.spentToday(treasury.today()), 30_000 * USDC);
    }

    function test_C5_batchTotalCountsTowardCap() public {
        (address[] memory payees, uint256[] memory amounts) = _payroll(); // 481,000
        vm.startPrank(agent);
        treasury.pay(vendor, 39_000 * USDC, REF);
        treasury.pay(vendor, 39_000 * USDC, REF);
        treasury.pay(vendor, 39_000 * USDC, REF); // 117,000 + 481,000 = 598,000 ok
        treasury.pay(vendor, 3_000 * USDC, REF); // 601,000 would breach once payroll lands
        vm.expectRevert(Treasury.ExceedsDailyCap.selector);
        treasury.payBatch(payees, amounts, REF);
        vm.stopPrank();
    }

    function test_C5_ownerApprovalCountsTowardCap() public {
        uint256 id = _request(vendor, PER_PAYMENT_CAP);
        vm.startPrank(agent);
        for (uint256 i; i < 13; ++i) {
            treasury.pay(alice, APPROVAL_THRESHOLD - 1, REF); // ~520k spent
        }
        vm.stopPrank();

        vm.prank(owner);
        vm.expectRevert(Treasury.ExceedsDailyCap.selector);
        treasury.approvePayment(id);
        (,,, Treasury.Status status) = treasury.pending(id);
        assertEq(uint8(status), uint8(Treasury.Status.Pending)); // still open, can be approved tomorrow

        vm.warp(T0 + 12 hours);
        vm.prank(owner);
        treasury.approvePayment(id);
        assertEq(usdc.balanceOf(vendor), PER_PAYMENT_CAP);
    }

    // =====================================================================
    // C6  Deposit to non-allowlisted vault -> VaultNotAllowed
    // =====================================================================

    function test_C6_depositToUnknownVaultReverts() public {
        MockYieldVault rogue = new MockYieldVault(usdc, attacker, 500);
        vm.startPrank(agent);
        vm.expectRevert(Treasury.VaultNotAllowed.selector);
        treasury.depositToVault(address(rogue), 100_000 * USDC);
        vm.expectRevert(Treasury.VaultNotAllowed.selector);
        treasury.depositToVault(attacker, 100_000 * USDC);
        vm.expectRevert(Treasury.VaultNotAllowed.selector);
        treasury.withdrawFromVault(address(rogue), 1);
        vm.stopPrank();
        assertEq(treasury.liquidBalance(), START_BALANCE);
    }

    // =====================================================================
    // C7  Agent action while paused (except emergencyExit) -> IsPaused
    // =====================================================================

    function test_C7_agentActionsBlockedWhilePaused() public {
        _deposit(500_000 * USDC);
        vm.prank(owner);
        treasury.pause();

        address[] memory payees = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        (payees[0], amounts[0]) = (alice, 1_000 * USDC);

        vm.startPrank(agent);
        vm.expectRevert(Treasury.IsPaused.selector);
        treasury.pay(alice, 1_000 * USDC, REF);
        vm.expectRevert(Treasury.IsPaused.selector);
        treasury.payBatch(payees, amounts, REF);
        vm.expectRevert(Treasury.IsPaused.selector);
        treasury.requestPayment(vendor, 50_000 * USDC, REF);
        vm.expectRevert(Treasury.IsPaused.selector);
        treasury.depositToVault(address(vault), 1_000 * USDC);
        vm.expectRevert(Treasury.IsPaused.selector);
        treasury.withdrawFromVault(address(vault), 1_000 * USDC);
        vm.stopPrank();
    }

    function test_C7_unpauseRestoresAgent() public {
        vm.startPrank(owner);
        treasury.pause();
        treasury.unpause();
        vm.stopPrank();
        vm.prank(agent);
        treasury.pay(alice, 1_000 * USDC, REF);
        assertEq(usdc.balanceOf(alice), 1_000 * USDC);
    }

    // =====================================================================
    // C8  emergencyExit while paused -> succeeds; funds back in Treasury
    // =====================================================================

    function test_C8_agentEmergencyExitWhilePaused() public {
        _deposit(2_400_000 * USDC);
        vm.prank(owner);
        treasury.pause();

        vm.expectEmit(address(treasury));
        emit Treasury.EmergencyExit(address(vault), 2_400_000 * USDC, agent);
        vm.prank(agent);
        treasury.emergencyExit(address(vault));

        assertEq(vault.balanceOf(address(treasury)), 0);
        assertEq(treasury.liquidBalance(), START_BALANCE);
    }

    function test_C8_ownerEmergencyExitIncludesInterest() public {
        _deposit(1_000_000 * USDC);
        vm.warp(T0 + 30 days);
        uint256 position = vault.balanceOf(address(treasury));
        assertGt(position, 1_000_000 * USDC);

        vm.startPrank(owner);
        treasury.pause();
        treasury.emergencyExit(address(vault));
        vm.stopPrank();
        assertEq(treasury.liquidBalance(), START_BALANCE - 1_000_000 * USDC + position);
        assertEq(vault.balanceOf(address(treasury)), 0);
    }

    function test_C8_strangerCannotEmergencyExit() public {
        _deposit(1_000_000 * USDC);
        vm.prank(stranger);
        vm.expectRevert(Treasury.NotAgent.selector);
        treasury.emergencyExit(address(vault));
    }

    function test_C8_exitRetriesUntilVaultUnfreezes() public {
        _deposit(1_000_000 * USDC);
        vm.prank(owner);
        vault.setWithdrawalsPaused(true);

        vm.prank(agent);
        vm.expectRevert(MockYieldVault.WithdrawalsPaused.selector);
        treasury.emergencyExit(address(vault));

        vm.prank(owner);
        vault.setWithdrawalsPaused(false);
        vm.prank(agent);
        treasury.emergencyExit(address(vault));
        assertEq(treasury.liquidBalance(), START_BALANCE);
    }

    function test_C8_exitStillWorksAfterVaultDelisted() public {
        _deposit(1_000_000 * USDC);
        vm.prank(owner);
        treasury.setVault(address(vault), false);

        vm.startPrank(agent);
        vm.expectRevert(Treasury.VaultNotAllowed.selector);
        treasury.withdrawFromVault(address(vault), 1_000 * USDC);
        treasury.emergencyExit(address(vault)); // money can always come home
        vm.stopPrank();
        assertEq(treasury.liquidBalance(), START_BALANCE);
    }

    function test_C8_exitOfNeverAllowlistedVaultReverts() public {
        vm.prank(agent);
        vm.expectRevert(Treasury.VaultNotAllowed.selector);
        treasury.emergencyExit(attacker);
    }

    // =====================================================================
    // C9  approvePayment twice -> second reverts AlreadyExecuted
    // =====================================================================

    function test_C9_approveTwiceReverts() public {
        uint256 id = _request(vendor, 60_000 * USDC);
        vm.startPrank(owner);
        treasury.approvePayment(id);
        vm.expectRevert(Treasury.AlreadyExecuted.selector);
        treasury.approvePayment(id);
        vm.stopPrank();
        assertEq(usdc.balanceOf(vendor), 60_000 * USDC); // paid exactly once
    }

    function test_C9_approveAfterRejectReverts() public {
        uint256 id = _request(vendor, 60_000 * USDC);
        vm.startPrank(owner);
        treasury.rejectPayment(id);
        vm.expectRevert(Treasury.AlreadyExecuted.selector);
        treasury.approvePayment(id);
        vm.expectRevert(Treasury.AlreadyExecuted.selector);
        treasury.rejectPayment(id);
        vm.stopPrank();
        assertEq(usdc.balanceOf(vendor), 0);
    }

    function test_C9_unknownRequestReverts() public {
        vm.prank(owner);
        vm.expectRevert(Treasury.PaymentNotFound.selector);
        treasury.approvePayment(42);
    }

    // =====================================================================
    // C10 approvePayment after payee removed from allowlist -> PayeeNotAllowed
    // =====================================================================

    function test_C10_approveAfterPayeeRemovedReverts() public {
        uint256 id = _request(vendor, 60_000 * USDC);
        vm.startPrank(owner);
        treasury.setPayee(vendor, false);
        vm.expectRevert(Treasury.PayeeNotAllowed.selector);
        treasury.approvePayment(id);
        vm.stopPrank();
        assertEq(usdc.balanceOf(vendor), 0);
    }

    function test_C10_approveAfterCapLoweredReverts() public {
        uint256 id = _request(vendor, 90_000 * USDC);
        vm.startPrank(owner);
        treasury.setCaps(80_000 * USDC, APPROVAL_THRESHOLD, DAILY_CAP);
        vm.expectRevert(Treasury.ExceedsPerPaymentCap.selector);
        treasury.approvePayment(id);
        vm.stopPrank();
    }

    // =====================================================================
    // C11 setCaps with approvalThreshold > perPaymentCap -> InvalidCaps
    // =====================================================================

    function test_C11_thresholdAboveCapReverts() public {
        vm.startPrank(owner);
        vm.expectRevert(Treasury.InvalidCaps.selector);
        treasury.setCaps(PER_PAYMENT_CAP, PER_PAYMENT_CAP + 1, DAILY_CAP);
        vm.expectRevert(Treasury.InvalidCaps.selector);
        treasury.setMaxVaultShareBps(10_001);
        vm.stopPrank();
        assertEq(treasury.approvalThreshold(), APPROVAL_THRESHOLD);
    }

    // =====================================================================
    // C12 Happy paths: balances and events
    // =====================================================================

    function test_C12_pay() public {
        vm.expectEmit(address(treasury));
        emit Treasury.PaymentExecuted(vendor, 8_000 * USDC, REF);
        vm.prank(agent);
        treasury.pay(vendor, 8_000 * USDC, REF);

        assertEq(usdc.balanceOf(vendor), 8_000 * USDC);
        assertEq(treasury.liquidBalance(), START_BALANCE - 8_000 * USDC);
        assertEq(treasury.spentToday(treasury.today()), 8_000 * USDC);
    }

    function test_C12_payBatchFullPayroll() public {
        (address[] memory payees, uint256[] memory amounts) = _payroll();
        vm.expectEmit(address(treasury));
        emit Treasury.PaymentExecuted(payees[0], 9_000 * USDC, REF);
        vm.prank(agent);
        treasury.payBatch(payees, amounts, REF);

        uint256 total;
        for (uint256 i; i < payees.length; ++i) {
            assertEq(usdc.balanceOf(payees[i]), amounts[i]);
            total += amounts[i];
        }
        assertEq(total, 481_000 * USDC);
        assertEq(treasury.liquidBalance(), START_BALANCE - 481_000 * USDC);
        assertEq(treasury.remainingDailyAllowance(), DAILY_CAP - 481_000 * USDC);
    }

    function test_C12_requestThenApprove() public {
        bytes32 ref = keccak256("invoice-audit-firm");
        vm.expectEmit(address(treasury));
        emit Treasury.PaymentRequested(1, vendor, 60_000 * USDC, ref);
        vm.prank(agent);
        uint256 id = treasury.requestPayment(vendor, 60_000 * USDC, ref);
        assertEq(usdc.balanceOf(vendor), 0); // nothing moves until the owner signs

        vm.expectEmit(address(treasury));
        emit Treasury.PaymentApproved(id);
        vm.expectEmit(address(treasury));
        emit Treasury.PaymentExecuted(vendor, 60_000 * USDC, ref);
        vm.prank(owner);
        treasury.approvePayment(id);

        (address payee, uint256 amount, bytes32 storedRef, Treasury.Status status) = treasury.pending(id);
        assertEq(payee, vendor);
        assertEq(amount, 60_000 * USDC);
        assertEq(storedRef, ref);
        assertEq(uint8(status), uint8(Treasury.Status.Approved));
        assertEq(usdc.balanceOf(vendor), 60_000 * USDC);
    }

    function test_C12_requestThenReject() public {
        uint256 id = _request(vendor, 60_000 * USDC);
        vm.expectEmit(address(treasury));
        emit Treasury.PaymentRejected(id);
        vm.prank(owner);
        treasury.rejectPayment(id);
        assertEq(usdc.balanceOf(vendor), 0);
    }

    function test_C12_depositAndWithdraw() public {
        vm.expectEmit(address(treasury));
        emit Treasury.Deposited(address(vault), 2_400_000 * USDC);
        _deposit(2_400_000 * USDC);
        assertEq(vault.balanceOf(address(treasury)), 2_400_000 * USDC);
        assertEq(treasury.liquidBalance(), 1_600_000 * USDC);
        assertEq(treasury.totalAssets(), START_BALANCE);

        vm.expectEmit(address(treasury));
        emit Treasury.Withdrawn(address(vault), 73_000 * USDC);
        vm.prank(agent);
        treasury.withdrawFromVault(address(vault), 73_000 * USDC);
        assertEq(treasury.liquidBalance(), 1_673_000 * USDC);
        assertEq(vault.balanceOf(address(treasury)), 2_327_000 * USDC);
    }

    function test_C12_accrual() public {
        _deposit(2_400_000 * USDC);
        vm.prank(owner);
        vault.simulateAccrual(25 days); // the demo's "advance clock 25 days"

        // 2,400,000 x 5% x 25/365 = 8,219.178082 mUSDC
        uint256 interest = 8_219_178_082;
        assertEq(vault.balanceOf(address(treasury)), 2_400_000 * USDC + interest);
        assertEq(treasury.totalAssets(), START_BALANCE + interest);
        assertEq(usdc.balanceOf(address(vault)), 2_400_000 * USDC + interest); // interest is real (minted)
    }

    /// The finance demo: payroll drops liquid below the 1,192,000 buffer; agent pulls back ~73,000.
    function test_C12_paydayRestoresBuffer() public {
        _deposit(2_400_000 * USDC);
        (address[] memory payees, uint256[] memory amounts) = _payroll();
        vm.startPrank(agent);
        treasury.payBatch(payees, amounts, REF);
        assertEq(treasury.liquidBalance(), 1_119_000 * USDC);
        treasury.withdrawFromVault(address(vault), 73_000 * USDC);
        vm.stopPrank();
        assertEq(treasury.liquidBalance(), 1_192_000 * USDC);
    }

    // =====================================================================
    // Hardening additions
    // =====================================================================

    /// Finance demo moment: 2,808,000 is spare, but the 60% cap only allows 2,400,000.
    function test_vaultShareCapOverridesGreed() public {
        vm.startPrank(agent);
        vm.expectRevert(Treasury.ExceedsVaultShare.selector);
        treasury.depositToVault(address(vault), 2_808_000 * USDC);

        treasury.depositToVault(address(vault), 2_400_000 * USDC); // exactly 60%
        vm.expectRevert(Treasury.ExceedsVaultShare.selector);
        treasury.depositToVault(address(vault), 1);
        vm.stopPrank();
    }

    function test_vaultShareNeverBlocksWithdrawals() public {
        _deposit(2_400_000 * USDC);
        (address[] memory payees, uint256[] memory amounts) = _payroll();
        vm.startPrank(agent);
        treasury.payBatch(payees, amounts, REF); // vault share is now ~68%, above the cap
        treasury.withdrawFromVault(address(vault), 73_000 * USDC);
        vm.stopPrank();
    }

    function test_setPayeeRejectsTreasuryOwnerAgentAndZero() public {
        vm.startPrank(owner);
        vm.expectRevert(Treasury.InvalidPayee.selector);
        treasury.setPayee(address(0), true);
        vm.expectRevert(Treasury.InvalidPayee.selector);
        treasury.setPayee(address(treasury), true);
        vm.expectRevert(Treasury.InvalidPayee.selector);
        treasury.setPayee(owner, true);
        vm.expectRevert(Treasury.InvalidPayee.selector);
        treasury.setPayee(agent, true);
        treasury.setPayee(agent, false); // removing is always allowed
        vm.stopPrank();
    }

    function test_setPayeesBatchEmitsPerAddress() public {
        address[] memory list = new address[](2);
        list[0] = makeAddr("p1");
        list[1] = makeAddr("p2");
        vm.expectEmit(address(treasury));
        emit Treasury.PayeeSet(list[0], true);
        vm.expectEmit(address(treasury));
        emit Treasury.PayeeSet(list[1], true);
        vm.prank(owner);
        treasury.setPayees(list, true);
        assertTrue(treasury.isPayee(list[0]) && treasury.isPayee(list[1]));
    }

    function test_constructorRejectsBadAgent() public {
        // try/catch instead of expectRevert: an expected revert on contract creation ends the test early.
        try new Treasury(usdc, owner, owner) {
            fail();
        } catch (bytes memory err) {
            assertEq(bytes4(err), Treasury.InvalidAgent.selector);
        }
        try new Treasury(usdc, owner, address(0)) {
            fail();
        } catch (bytes memory err) {
            assertEq(bytes4(err), Treasury.InvalidAgent.selector);
        }
    }

    function test_agentMustDifferFromOwnerAndPayees() public {
        vm.startPrank(owner);
        vm.expectRevert(Treasury.InvalidAgent.selector);
        treasury.setAgent(owner);
        vm.expectRevert(Treasury.InvalidAgent.selector);
        treasury.setAgent(alice);
        vm.expectRevert(Treasury.InvalidAgent.selector);
        treasury.setAgent(address(0));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, agent));
        treasury.transferOwnership(agent);
        vm.stopPrank();
    }

    function test_setAgentRotatesKey() public {
        address newAgent = makeAddr("agent-v2");
        vm.prank(owner);
        treasury.setAgent(newAgent);

        vm.prank(agent);
        vm.expectRevert(Treasury.NotAgent.selector);
        treasury.pay(alice, 1_000 * USDC, REF);
        vm.prank(newAgent);
        treasury.pay(alice, 1_000 * USDC, REF);
    }

    function test_transferOwnershipMovesAllPower() public {
        address newOwner = makeAddr("founder-2");
        vm.prank(owner);
        treasury.transferOwnership(newOwner);
        vm.prank(owner);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.pause();
        vm.prank(newOwner);
        treasury.pause();
    }

    function test_renounceOwnershipDisabled() public {
        vm.prank(owner);
        vm.expectRevert(Treasury.RenounceDisabled.selector);
        treasury.renounceOwnership();
        assertEq(treasury.owner(), owner);
    }

    function test_setVaultRejectsNonContract() public {
        vm.prank(owner);
        vm.expectRevert(Treasury.InvalidVault.selector);
        treasury.setVault(attacker, true);
    }

    function test_setVaultTracksEachVaultOnce() public {
        vm.startPrank(owner);
        treasury.setVault(address(vault), false);
        treasury.setVault(address(vault), true);
        vm.stopPrank();
        assertEq(treasury.vaultCount(), 1);
    }

    function test_ownerIsNotTheAgent() public {
        vm.startPrank(owner);
        vm.expectRevert(Treasury.NotAgent.selector);
        treasury.pay(alice, 1_000 * USDC, REF);
        vm.expectRevert(Treasury.NotAgent.selector);
        treasury.depositToVault(address(vault), 1_000 * USDC);
        vm.stopPrank();
    }

    function test_strangerCannotAct() public {
        vm.startPrank(stranger);
        vm.expectRevert(Treasury.NotAgent.selector);
        treasury.pay(alice, 1_000 * USDC, REF);
        vm.expectRevert(Treasury.NotAgent.selector);
        treasury.requestPayment(vendor, 50_000 * USDC, REF);
        vm.expectRevert(Treasury.NotAgent.selector);
        treasury.withdrawFromVault(address(vault), 1);
        vm.stopPrank();
    }

    function test_zeroAndMalformedInputsRevert() public {
        address[] memory none = new address[](0);
        address[] memory one = new address[](1);
        uint256[] memory two = new uint256[](2);
        one[0] = alice;

        vm.startPrank(agent);
        vm.expectRevert(Treasury.InvalidAmount.selector);
        treasury.pay(alice, 0, REF);
        vm.expectRevert(Treasury.InvalidAmount.selector);
        treasury.requestPayment(vendor, 0, REF);
        vm.expectRevert(Treasury.InvalidAmount.selector);
        treasury.depositToVault(address(vault), 0);
        vm.expectRevert(Treasury.InvalidAmount.selector);
        treasury.withdrawFromVault(address(vault), 0);
        vm.expectRevert(Treasury.LengthMismatch.selector);
        treasury.payBatch(none, new uint256[](0), REF);
        vm.expectRevert(Treasury.LengthMismatch.selector);
        treasury.payBatch(one, two, REF);
        vm.stopPrank();
    }

    function test_ownerCanApproveWhilePaused() public {
        uint256 id = _request(vendor, 60_000 * USDC);
        vm.startPrank(owner);
        treasury.pause();
        treasury.approvePayment(id);
        vm.stopPrank();
        assertEq(usdc.balanceOf(vendor), 60_000 * USDC);
    }

    function test_ownerWithdrawRescue() public {
        address cold = makeAddr("founder-cold-wallet");
        vm.expectEmit(address(treasury));
        emit Treasury.OwnerWithdrawal(cold, 1_000_000 * USDC);
        vm.prank(owner);
        treasury.ownerWithdraw(cold, 1_000_000 * USDC);
        assertEq(usdc.balanceOf(cold), 1_000_000 * USDC);
    }

    function test_policyHashAndEvents() public {
        bytes32 h = keccak256("{\"version\":1}");
        vm.expectEmit(address(treasury));
        emit Treasury.PolicyHashSet(h);
        vm.prank(owner);
        treasury.setPolicyHash(h);
        assertEq(treasury.policyHash(), h);
    }
}
