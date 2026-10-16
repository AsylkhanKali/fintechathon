// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldVault} from "./interfaces/IYieldVault.sol";

/// @title Treasury
/// @notice Holds the company's stablecoins and enforces the founder-signed policy on-chain.
///         The owner (founder key) sets every rule. The agent (service hot key) can only pay
///         allowlisted payees within caps, or move funds between the Treasury and allowlisted
///         vaults. There is no function by which the agent can change rules or send funds anywhere else.
contract Treasury is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Status {
        None,
        Pending,
        Approved,
        Rejected
    }

    /// @notice A tier-2 payment waiting for the owner.
    struct PendingPayment {
        address payee;
        uint256 amount;
        bytes32 ref;
        Status status;
    }

    uint256 public constant BPS = 10_000;

    IERC20 public immutable token;
    address public agent;

    /// @notice Hard max per payment; above this is never allowed (tier 3).
    uint256 public perPaymentCap;
    /// @notice Payments at or above this need owner approval (tier 2).
    uint256 public approvalThreshold;
    /// @notice Max total payments per UTC day (block.timestamp / 1 days).
    uint256 public dailyPaymentCap;
    /// @notice Max share of total assets that may sit in vaults after a deposit.
    uint256 public maxVaultShareBps = BPS;

    mapping(uint256 day => uint256 amount) public spentToday;
    mapping(address => bool) public isPayee;
    mapping(address => bool) public isVault;
    mapping(uint256 id => PendingPayment) public pending;
    /// @notice Number of payment requests created; request ids start at 1.
    uint256 public paymentCount;

    /// @notice keccak256 of the signed policy JSON, for audit matching.
    bytes32 public policyHash;
    /// @notice Owner kill switch for agent actions (emergencyExit still works).
    bool public paused;

    /// @notice Every vault ever allowlisted, so holdings are still valued (and exitable) after de-listing.
    address[] public vaults;
    mapping(address => bool) public isKnownVault;

    event PaymentExecuted(address indexed payee, uint256 amount, bytes32 indexed ref);
    event PaymentRequested(uint256 indexed id, address indexed payee, uint256 amount, bytes32 indexed ref);
    event PaymentApproved(uint256 indexed id);
    event PaymentRejected(uint256 indexed id);
    event Deposited(address indexed vault, uint256 amount);
    event Withdrawn(address indexed vault, uint256 amount);
    event EmergencyExit(address indexed vault, uint256 amount, address indexed caller);
    event CapsUpdated(uint256 perPaymentCap, uint256 approvalThreshold, uint256 dailyPaymentCap);
    event MaxVaultShareSet(uint256 bps);
    event PayeeSet(address indexed payee, bool allowed);
    event VaultSet(address indexed vault, bool allowed);
    event AgentSet(address indexed agent);
    event PolicyHashSet(bytes32 hash);
    event Paused(bool paused);
    event OwnerWithdrawal(address indexed to, uint256 amount);

    error NotOwner();
    error NotAgent();
    error PayeeNotAllowed();
    error VaultNotAllowed();
    error BelowApprovalThreshold();
    error RequiresApproval();
    error ExceedsPerPaymentCap();
    error ExceedsDailyCap();
    error ExceedsVaultShare();
    error IsPaused();
    error AlreadyExecuted();
    error PaymentNotFound();
    error InvalidCaps();
    error InvalidAgent();
    error InvalidPayee();
    error InvalidVault();
    error InvalidAmount();
    error LengthMismatch();
    error RenounceDisabled();

    modifier onlyAgent() {
        if (msg.sender != agent) revert NotAgent();
        _;
    }

    modifier onlyAgentOrOwner() {
        if (msg.sender != agent && msg.sender != owner()) revert NotAgent();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert IsPaused();
        _;
    }

    constructor(IERC20 token_, address owner_, address agent_) Ownable(owner_) {
        if (agent_ == address(0) || agent_ == owner_) revert InvalidAgent();
        token = token_;
        agent = agent_;
        emit AgentSet(agent_);
    }

    // =====================================================================
    //                               Owner
    // =====================================================================

    function setAgent(address newAgent) external onlyOwner {
        if (newAgent == address(0) || newAgent == owner() || isPayee[newAgent]) revert InvalidAgent();
        agent = newAgent;
        emit AgentSet(newAgent);
    }

    function setCaps(uint256 perPaymentCap_, uint256 approvalThreshold_, uint256 dailyPaymentCap_)
        external
        onlyOwner
    {
        if (approvalThreshold_ > perPaymentCap_) revert InvalidCaps();
        perPaymentCap = perPaymentCap_;
        approvalThreshold = approvalThreshold_;
        dailyPaymentCap = dailyPaymentCap_;
        emit CapsUpdated(perPaymentCap_, approvalThreshold_, dailyPaymentCap_);
    }

    function setMaxVaultShareBps(uint256 bps) external onlyOwner {
        if (bps > BPS) revert InvalidCaps();
        maxVaultShareBps = bps;
        emit MaxVaultShareSet(bps);
    }

    function setPayee(address payee, bool allowed) external onlyOwner {
        _setPayee(payee, allowed);
    }

    /// @notice Batch form of setPayee, so a full payroll can be allowlisted in one transaction.
    function setPayees(address[] calldata payees, bool allowed) external onlyOwner {
        for (uint256 i; i < payees.length; ++i) {
            _setPayee(payees[i], allowed);
        }
    }

    function setVault(address vault, bool allowed) external onlyOwner {
        if (allowed) {
            if (vault.code.length == 0) revert InvalidVault();
            if (!isKnownVault[vault]) {
                isKnownVault[vault] = true;
                vaults.push(vault);
            }
        }
        isVault[vault] = allowed;
        emit VaultSet(vault, allowed);
    }

    function setPolicyHash(bytes32 hash) external onlyOwner {
        policyHash = hash;
        emit PolicyHashSet(hash);
    }

    /// @notice Approves a tier-2 request. Re-checks the allowlist and per-payment cap and counts
    ///         toward the daily cap. Works while paused: it is the owner's explicit decision.
    function approvePayment(uint256 id) external nonReentrant onlyOwner {
        PendingPayment storage p = _openRequest(id);
        if (!isPayee[p.payee]) revert PayeeNotAllowed();
        if (p.amount > perPaymentCap) revert ExceedsPerPaymentCap();
        _spend(p.amount);
        p.status = Status.Approved;
        emit PaymentApproved(id);
        emit PaymentExecuted(p.payee, p.amount, p.ref);
        token.safeTransfer(p.payee, p.amount);
    }

    function rejectPayment(uint256 id) external onlyOwner {
        PendingPayment storage p = _openRequest(id);
        p.status = Status.Rejected;
        emit PaymentRejected(id);
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused(true);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Paused(false);
    }

    /// @notice Rescue: the owner can always move funds out.
    function ownerWithdraw(address to, uint256 amount) external nonReentrant onlyOwner {
        emit OwnerWithdrawal(to, amount);
        token.safeTransfer(to, amount);
    }

    /// @dev Owner and agent must stay different addresses.
    function transferOwnership(address newOwner) public override onlyOwner {
        if (newOwner == agent) revert OwnableInvalidOwner(newOwner);
        super.transferOwnership(newOwner);
    }

    /// @dev Disabled: without an owner nobody could pause the agent or change its limits.
    function renounceOwnership() public pure override {
        revert RenounceDisabled();
    }

    // =====================================================================
    //                               Agent
    // =====================================================================

    /// @notice Tier-0 payment: allowlisted payee, below the approval threshold, within the daily cap.
    function pay(address payee, uint256 amount, bytes32 ref) external nonReentrant onlyAgent whenNotPaused {
        _checkRoutinePayment(payee, amount);
        _spend(amount);
        emit PaymentExecuted(payee, amount, ref);
        token.safeTransfer(payee, amount);
    }

    /// @notice Atomic batch of tier-0 payments; the daily cap applies to the batch total.
    function payBatch(address[] calldata payees, uint256[] calldata amounts, bytes32 ref)
        external
        nonReentrant
        onlyAgent
        whenNotPaused
    {
        uint256 n = payees.length;
        if (n == 0 || n != amounts.length) revert LengthMismatch();
        uint256 total;
        for (uint256 i; i < n; ++i) {
            _checkRoutinePayment(payees[i], amounts[i]);
            total += amounts[i];
        }
        _spend(total);
        for (uint256 i; i < n; ++i) {
            emit PaymentExecuted(payees[i], amounts[i], ref);
            token.safeTransfer(payees[i], amounts[i]);
        }
    }

    /// @notice Tier-2: records a payment that needs the owner's approval. Moves no funds.
    function requestPayment(address payee, uint256 amount, bytes32 ref)
        external
        onlyAgent
        whenNotPaused
        returns (uint256 id)
    {
        if (!isPayee[payee]) revert PayeeNotAllowed();
        if (amount == 0) revert InvalidAmount();
        if (amount < approvalThreshold) revert BelowApprovalThreshold();
        if (amount > perPaymentCap) revert ExceedsPerPaymentCap();
        id = ++paymentCount;
        pending[id] = PendingPayment(payee, amount, ref, Status.Pending);
        emit PaymentRequested(id, payee, amount, ref);
    }

    /// @notice Moves idle funds into an allowlisted vault. The Treasury is always the receiver.
    function depositToVault(address vault, uint256 amount) external nonReentrant onlyAgent whenNotPaused {
        if (!isVault[vault]) revert VaultNotAllowed();
        if (amount == 0) revert InvalidAmount();
        if ((vaultHoldings() + amount) * BPS > maxVaultShareBps * totalAssets()) revert ExceedsVaultShare();
        emit Deposited(vault, amount);
        token.forceApprove(vault, amount);
        IYieldVault(vault).deposit(amount, address(this));
    }

    /// @notice Pulls funds back from an allowlisted vault. Funds always return to the Treasury.
    function withdrawFromVault(address vault, uint256 amount) external nonReentrant onlyAgent whenNotPaused {
        if (!isVault[vault]) revert VaultNotAllowed();
        if (amount == 0) revert InvalidAmount();
        emit Withdrawn(vault, _pullFromVault(vault, amount));
    }

    /// @notice Withdraws the full position back to the Treasury. Callable by agent or owner, even
    ///         while paused, and for any vault that was ever allowlisted.
    function emergencyExit(address vault) external nonReentrant onlyAgentOrOwner {
        if (!isKnownVault[vault]) revert VaultNotAllowed();
        uint256 position = IYieldVault(vault).balanceOf(address(this));
        emit EmergencyExit(vault, _pullFromVault(vault, position), msg.sender);
    }

    // =====================================================================
    //                               Views
    // =====================================================================

    function today() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function remainingDailyAllowance() external view returns (uint256) {
        uint256 spent = spentToday[today()];
        return spent >= dailyPaymentCap ? 0 : dailyPaymentCap - spent;
    }

    function liquidBalance() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function vaultHoldings() public view returns (uint256 total) {
        for (uint256 i; i < vaults.length; ++i) {
            total += IYieldVault(vaults[i]).balanceOf(address(this));
        }
    }

    function totalAssets() public view returns (uint256) {
        return liquidBalance() + vaultHoldings();
    }

    function vaultCount() external view returns (uint256) {
        return vaults.length;
    }

    // =====================================================================
    //                              Internal
    // =====================================================================

    function _checkOwner() internal view override {
        if (msg.sender != owner()) revert NotOwner();
    }

    function _setPayee(address payee, bool allowed) internal {
        if (allowed && (payee == address(0) || payee == address(this) || payee == owner() || payee == agent)) {
            revert InvalidPayee();
        }
        isPayee[payee] = allowed;
        emit PayeeSet(payee, allowed);
    }

    function _checkRoutinePayment(address payee, uint256 amount) internal view {
        if (!isPayee[payee]) revert PayeeNotAllowed();
        if (amount == 0) revert InvalidAmount();
        if (amount >= approvalThreshold) revert RequiresApproval();
    }

    function _spend(uint256 amount) internal {
        uint256 day = today();
        uint256 spent = spentToday[day] + amount;
        if (spent > dailyPaymentCap) revert ExceedsDailyCap();
        spentToday[day] = spent;
    }

    function _openRequest(uint256 id) internal view returns (PendingPayment storage p) {
        p = pending[id];
        if (p.status == Status.None) revert PaymentNotFound();
        if (p.status != Status.Pending) revert AlreadyExecuted();
    }

    function _pullFromVault(address vault, uint256 amount) internal returns (uint256 received) {
        uint256 before = token.balanceOf(address(this));
        if (amount > 0) IYieldVault(vault).withdraw(amount, address(this));
        received = token.balanceOf(address(this)) - before;
    }
}
