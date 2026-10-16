// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "../Base.t.sol";
import {Treasury} from "../../src/Treasury.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";
import {MockYieldVault} from "../../src/mocks/MockYieldVault.sol";

/// @notice Plays a fully compromised agent key: random calls, attacker-chosen recipients and
///         amounts, and attempts on every owner function. The owner occasionally approves
///         requests and time moves forward, so daily-cap and approval paths are exercised too.
contract CompromisedAgentHandler is Test {
    Treasury internal treasury;
    MockUSDC internal usdc;
    MockYieldVault internal vault;
    address internal owner;
    address internal agent;
    address internal attacker;
    address internal rogueVault;
    address[] internal payees;

    uint256[] public daysSeen;
    mapping(uint256 => bool) internal _daySeen;
    /// Sum of every successful payment, as observed from the handler's side.
    uint256 public ghostPaidOut;
    /// Number of owner-only calls the agent managed to execute. Must stay 0.
    uint256 public ghostRuleChanges;
    /// Set if a deposit ever left vault holdings above the max share. Must stay false.
    bool public ghostShareBreached;

    constructor(
        Treasury treasury_,
        MockUSDC usdc_,
        MockYieldVault vault_,
        address owner_,
        address agent_,
        address attacker_,
        address[] memory payees_
    ) {
        treasury = treasury_;
        usdc = usdc_;
        vault = vault_;
        owner = owner_;
        agent = agent_;
        attacker = attacker_;
        payees = payees_;
        rogueVault = address(new MockYieldVault(usdc_, attacker_, 500));
        _markDay();
    }

    // ------------------------------------------------------- agent actions

    function pay(uint256 toSeed, uint256 amount) external {
        address to = _recipient(toSeed);
        amount = bound(amount, 0, 150_000e6);
        vm.prank(agent);
        try treasury.pay(to, amount, keccak256(abi.encode(toSeed))) {
            ghostPaidOut += amount;
        } catch {}
    }

    function payBatch(uint256 seed, uint256 n, uint256 amountSeed) external {
        n = bound(n, 1, 8);
        address[] memory to = new address[](n);
        uint256[] memory amounts = new uint256[](n);
        uint256 total;
        for (uint256 i; i < n; ++i) {
            to[i] = _recipient(uint256(keccak256(abi.encode(seed, i))));
            amounts[i] = bound(uint256(keccak256(abi.encode(amountSeed, i))), 0, 60_000e6);
            total += amounts[i];
        }
        vm.prank(agent);
        try treasury.payBatch(to, amounts, bytes32(seed)) {
            ghostPaidOut += total;
        } catch {}
    }

    function requestPayment(uint256 toSeed, uint256 amount) external {
        amount = bound(amount, 0, 200_000e6);
        vm.prank(agent);
        try treasury.requestPayment(_recipient(toSeed), amount, bytes32(toSeed)) {} catch {}
    }

    function deposit(uint256 vaultSeed, uint256 amount) external {
        address target = vaultSeed % 3 == 0 ? rogueVault : (vaultSeed % 3 == 1 ? attacker : address(vault));
        amount = bound(amount, 0, 3_000_000e6);
        vm.prank(agent);
        try treasury.depositToVault(target, amount) {
            if (treasury.vaultHoldings() * 10_000 > treasury.maxVaultShareBps() * treasury.totalAssets()) {
                ghostShareBreached = true;
            }
        } catch {}
    }

    function withdraw(uint256 vaultSeed, uint256 amount) external {
        address target = vaultSeed % 2 == 0 ? rogueVault : address(vault);
        amount = bound(amount, 0, 3_000_000e6);
        vm.prank(agent);
        try treasury.withdrawFromVault(target, amount) {} catch {}
    }

    function emergencyExit(uint256 vaultSeed) external {
        address target = vaultSeed % 2 == 0 ? rogueVault : address(vault);
        vm.prank(agent);
        try treasury.emergencyExit(target) {} catch {}
    }

    /// Every rule-changing or fund-moving owner function, called with the agent key.
    function attackRules(uint256 seed) external {
        address[] memory evil = new address[](1);
        evil[0] = attacker;
        vm.startPrank(agent);
        uint256 k = seed % 13;
        bool ok;
        if (k == 0) (ok,) = _try(abi.encodeCall(Treasury.setPayee, (attacker, true)));
        if (k == 1) (ok,) = _try(abi.encodeCall(Treasury.setPayees, (evil, true)));
        if (k == 2) (ok,) = _try(abi.encodeCall(Treasury.setCaps, (type(uint128).max, 1e30, type(uint128).max)));
        if (k == 3) (ok,) = _try(abi.encodeCall(Treasury.setAgent, (attacker)));
        if (k == 4) (ok,) = _try(abi.encodeCall(Treasury.setPolicyHash, (bytes32(seed))));
        if (k == 5) (ok,) = _try(abi.encodeCall(Treasury.setVault, (rogueVault, true)));
        if (k == 6) (ok,) = _try(abi.encodeCall(Treasury.setMaxVaultShareBps, (10_000)));
        if (k == 7) (ok,) = _try(abi.encodeCall(Treasury.ownerWithdraw, (attacker, 1e6)));
        if (k == 8) (ok,) = _try(abi.encodeCall(Treasury.transferOwnership, (attacker)));
        if (k == 9) (ok,) = _try(abi.encodeCall(Treasury.approvePayment, (bound(seed, 1, 50))));
        if (k == 10) (ok,) = _try(abi.encodeCall(Treasury.rejectPayment, (bound(seed, 1, 50))));
        if (k == 11) (ok,) = _try(abi.encodeCall(Treasury.pause, ()));
        if (k == 12) (ok,) = _try(abi.encodeCall(Treasury.renounceOwnership, ()));
        vm.stopPrank();
        if (ok) ++ghostRuleChanges;
    }

    // ---------------------------------------------- owner and environment

    function ownerApprove(uint256 idSeed) external {
        uint256 count = treasury.paymentCount();
        if (count == 0) return;
        (address payee, uint256 amount,,) = treasury.pending(bound(idSeed, 1, count));
        vm.prank(owner);
        try treasury.approvePayment(bound(idSeed, 1, count)) {
            ghostPaidOut += amount;
            payee; // silence unused warning
        } catch {}
    }

    function passTime(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 1, 2 days));
        _markDay();
    }

    // ------------------------------------------------------------ helpers

    function daysSeenCount() external view returns (uint256) {
        return daysSeen.length;
    }

    /// Mostly real payees, sometimes the attacker, the agent itself, or a random address.
    function _recipient(uint256 seed) internal view returns (address) {
        uint256 k = seed % 8;
        if (k < 4) return payees[seed % payees.length];
        if (k == 4) return attacker;
        if (k == 5) return agent;
        if (k == 6) return address(treasury);
        return address(uint160(uint256(keccak256(abi.encode("random", seed)))));
    }

    function _try(bytes memory data) internal returns (bool ok, bytes memory ret) {
        (ok, ret) = address(treasury).call(data);
    }

    function _markDay() internal {
        uint256 d = block.timestamp / 1 days;
        if (!_daySeen[d]) {
            _daySeen[d] = true;
            daysSeen.push(d);
        }
    }
}

/// @notice "A compromised agent key cannot override the owner's rules", checked after every random
///         call sequence: no leak to non-payees, daily cap never exceeded, rules never changed.
contract TreasuryInvariantTest is BaseTest {
    CompromisedAgentHandler internal handler;
    address[] internal payees;

    function setUp() public override {
        super.setUp();
        payees = new address[](3);
        (payees[0], payees[1], payees[2]) = (alice, bob, vendor);

        handler = new CompromisedAgentHandler(treasury, usdc, vault, owner, agent, attacker, payees);
        targetContract(address(handler));
    }

    /// Every token ever minted sits in the Treasury, the allowlisted vault, or an allowlisted payee.
    function invariant_fundsOnlyReachAllowlistedDestinations() public view {
        uint256 accounted = usdc.balanceOf(address(treasury)) + usdc.balanceOf(address(vault));
        for (uint256 i; i < payees.length; ++i) {
            accounted += usdc.balanceOf(payees[i]);
        }
        assertEq(accounted, usdc.totalSupply());
        assertEq(usdc.balanceOf(attacker), 0);
        assertEq(usdc.balanceOf(agent), 0);
    }

    function invariant_payeesReceivedExactlyWhatSucceeded() public view {
        uint256 received;
        for (uint256 i; i < payees.length; ++i) {
            received += usdc.balanceOf(payees[i]);
        }
        assertEq(received, handler.ghostPaidOut());
    }

    function invariant_dailyCapNeverExceeded() public view {
        uint256 n = handler.daysSeenCount();
        for (uint256 i; i < n; ++i) {
            assertLe(treasury.spentToday(handler.daysSeen(i)), DAILY_CAP);
        }
    }

    function invariant_rulesUnchangedByAgent() public view {
        assertEq(handler.ghostRuleChanges(), 0);
        assertEq(treasury.owner(), owner);
        assertEq(treasury.agent(), agent);
        assertEq(treasury.perPaymentCap(), PER_PAYMENT_CAP);
        assertEq(treasury.approvalThreshold(), APPROVAL_THRESHOLD);
        assertEq(treasury.dailyPaymentCap(), DAILY_CAP);
        assertEq(treasury.maxVaultShareBps(), MAX_VAULT_SHARE_BPS);
        assertEq(treasury.policyHash(), bytes32(0));
        assertFalse(treasury.paused());
        assertFalse(treasury.isPayee(attacker));
        assertEq(treasury.vaultCount(), 1);
    }

    function invariant_vaultShareRespectedOnEveryDeposit() public view {
        assertFalse(handler.ghostShareBreached());
    }
}
