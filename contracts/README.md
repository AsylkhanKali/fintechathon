# Autonomous Treasury — on-chain vault (Coder 1)

> **All transactions use zero-value testnet tokens; no real-value cryptocurrency or stablecoins were used.**
> Networks: local Anvil (chain 31337, offline fallback) and Base Sepolia (chain 84532). The deploy
> scripts refuse any other chain.

The Treasury contract holds the company's (mock) stablecoins and enforces the founder-signed policy.
The off-chain agent can only *ask*; the contract decides. A compromised agent key, engine or LLM
cannot pay an unlisted address, exceed a cap, or change a rule. Tests C1–C12 and a fuzzing
invariant suite prove this (see [Tests](#tests)).

## What is here

| Path | What |
|---|---|
| `src/Treasury.sol` | The vault: roles, allowlists, caps, tier-2 approvals, vault moves, pause, emergency exit |
| `src/mocks/MockUSDC.sol` | ERC20, 6 decimals, "Mock USD Coin (testnet, zero value)", symbol `mUSDC` |
| `src/mocks/MockYieldVault.sol` | Simulated yield venue the demo controls (rate, utilisation, freeze, accrual) |
| `src/mocks/MockPriceFeed.sol` | Chainlink AggregatorV3-compatible USDC/USD feed; owner sets price to stage a depeg |
| `script/Deploy.s.sol` | Deploys all four, wires roles, allowlists the vault, mints 4,000,000 mUSDC to the Treasury |
| `script/SeedDemo.s.sol` | Applies the finance-team demo policy: caps, 60% vault share, 66 payees |
| `abi/*.json` | ABIs for web3.py (no Foundry needed to use them) |
| `../deployments/<network>.json` | Contract addresses, owner, agent, start block (written by Deploy) |
| `../deployments/demo-payees.json` | 60 contributors + 6 vendors with addresses and amounts (written by SeedDemo) |

## Quickstart (local, works offline)

Needs [Foundry](https://getfoundry.sh) (`brew install foundry`).

```bash
make test            # 75 tests: C1–C12, mocks, invariants
make anvil           # terminal 1: local chain on http://127.0.0.1:8545
make deploy-local    # terminal 2: deploy + write ../deployments/anvil.json
make seed-local      # finance demo policy + ../deployments/demo-payees.json
make abi             # refresh abi/*.json after contract changes
```

Locally, **owner = Anvil account #0** and **agent = Anvil account #1**. `anvil` prints their
private keys on startup. Those keys are public and zero-value, so use account #1's key as the
agent key for local runs only. No private key is stored in this repo.

## Base Sepolia

1. Create two fresh testnet-only keys (owner, agent) and fund both with Base Sepolia ETH from a
   faucet that **does not require holding mainnet funds** (competition rule). The agent needs gas.
2. `cp .env.example .env` and fill in `OWNER_PRIVATE_KEY`, `AGENT_ADDRESS` (and optionally
   `ETHERSCAN_API_KEY` to verify on sepolia.basescan.org, `POLICY_HASH`).
3. `make deploy-base-sepolia` then `make seed-base-sepolia`. Addresses go to
   `../deployments/base-sepolia.json`; tx hashes are in `broadcast/` (keep these as evidence).

## Roles and rules

**Owner** = founder key. **Agent** = service hot key. They must be different addresses. The
constructor, `setAgent` and `transferOwnership` all enforce this, and `renounceOwnership` is
disabled. Amounts are in 6-decimal units (`1 mUSDC = 1_000_000`). The finance-spec demo values are:
approval threshold 40,000, per-payment cap 100,000, daily cap 600,000, max vault share 60%.

| Function | Who | Enforced (reverts otherwise) |
|---|---|---|
| `pay(payee, amount, ref)` | agent | not paused · `isPayee` · `0 < amount < approvalThreshold` · day total ≤ `dailyPaymentCap` |
| `payBatch(payees[], amounts[], ref)` | agent | same per item · daily cap on the batch total · atomic |
| `requestPayment(payee, amount, ref) → id` | agent | not paused · `isPayee` · `approvalThreshold ≤ amount ≤ perPaymentCap` · moves no funds |
| `depositToVault(vault, amount)` | agent | not paused · `isVault` · vault holdings after deposit ≤ `maxVaultShareBps` of `totalAssets()` · receiver is always the Treasury |
| `withdrawFromVault(vault, amount)` | agent | not paused · `isVault` · funds always return to the Treasury |
| `emergencyExit(vault)` | agent **or** owner | works **while paused** · any vault ever allowlisted · pulls the full position home |
| `approvePayment(id)` | owner | request still pending · payee still allowlisted · amount ≤ current cap · counts toward the daily cap · allowed while paused |
| `rejectPayment(id)` | owner | request still pending |
| `setCaps(perPaymentCap, approvalThreshold, dailyPaymentCap)` | owner | `approvalThreshold ≤ perPaymentCap` |
| `setMaxVaultShareBps(bps)` | owner | `bps ≤ 10000` |
| `setPayee(addr, bool)` / `setPayees(addr[], bool)` | owner | cannot allowlist zero, the Treasury, the owner or the agent |
| `setVault(addr, bool)` | owner | must be a contract |
| `setAgent`, `setPolicyHash`, `pause`, `unpause`, `ownerWithdraw(to, amount)` | owner | — |

**Views for the engine and dashboard:** `liquidBalance()`, `vaultHoldings()`, `totalAssets()`,
`today()` (UTC day index), `spentToday(day)`, `remainingDailyAllowance()`, `paymentCount()`,
`pending(id) → (payee, amount, ref, status)` where status is 0 None, 1 Pending, 2 Approved, 3 Rejected,
`policyHash()`, `paused()`, the caps, `isPayee(addr)`, `isVault(addr)`.
Vault: `balanceOf(treasury)`, `utilizationBps()`, `withdrawalsPaused()`, `rateBps()`.
Feed: `latestRoundData()` (8 decimals; 1.00 = `100000000`).

### Events

`PaymentExecuted(payee, amount, ref)` is emitted for **every** outflow to a payee, including owner
approvals, so reconciliation can match on one event. `ref` is indexed: filter by it to make
payroll idempotent (PRD §5).

`PaymentRequested(id, payee, amount, ref)` · `PaymentApproved(id)` · `PaymentRejected(id)` ·
`Deposited(vault, amount)` · `Withdrawn(vault, amount)` · `EmergencyExit(vault, amount, caller)` ·
`CapsUpdated(perPaymentCap, approvalThreshold, dailyPaymentCap)` · `MaxVaultShareSet(bps)` ·
`PayeeSet(addr, allowed)` · `VaultSet(addr, allowed)` · `AgentSet(addr)` · `PolicyHashSet(hash)` ·
`Paused(bool)` · `OwnerWithdrawal(to, amount)`

### Custom errors (revert data starts with the selector)

| Treasury error | Selector |
|---|---|
| `AlreadyExecuted()` | `0x0dc10197` |
| `BelowApprovalThreshold()` | `0x40b731ca` |
| `ExceedsDailyCap()` | `0xf02fe4dd` |
| `ExceedsPerPaymentCap()` | `0x81898631` |
| `ExceedsVaultShare()` | `0x3d99de31` |
| `InvalidAgent()` | `0xbebdc757` |
| `InvalidAmount()` | `0x2c5211c6` |
| `InvalidCaps()` | `0x5c9e11e8` |
| `InvalidPayee()` | `0xb387a238` |
| `InvalidVault()` | `0xd03a6320` |
| `IsPaused()` | `0x1309a563` |
| `LengthMismatch()` | `0xff633a38` |
| `NotAgent()` | `0x0d9ab13f` |
| `NotOwner()` | `0x30cd7471` |
| `PayeeNotAllowed()` | `0xa0a30653` |
| `PaymentNotFound()` | `0xbefcc57b` |
| `RenounceDisabled()` | `0x89051165` |
| `RequiresApproval()` | `0x6f26dad0` |
| `VaultNotAllowed()` | `0x5040aaa3` |
| `OwnableInvalidOwner(address)` | `0x1e4fbdf7` |

Errors bubbling up from the vault: `WithdrawalsPaused()` `0x6022a9e7` (freeze, so retry the exit),
`InsufficientBalance()` `0xf4d678b8`.

## For the agent (web3.py)

Load `abi/Treasury.json` and `../deployments/<network>.json`. Simulate first, then sign with the
agent key. An untested sketch for web3.py v7:

```python
import json
from web3 import Web3

w3 = Web3(Web3.HTTPProvider("http://127.0.0.1:8545"))
dep = json.load(open("deployments/anvil.json"))
treasury = w3.eth.contract(address=dep["Treasury"], abi=json.load(open("contracts/abi/Treasury.json")))
agent = w3.eth.account.from_key(AGENT_PRIVATE_KEY)

call = treasury.functions.pay(payee, 4_000 * 10**6, Web3.keccak(text="invoice:INV-104"))
call.call({"from": agent.address})  # pre-flight: raises with the custom-error data on a policy violation
tx = call.build_transaction({"from": agent.address, "nonce": w3.eth.get_transaction_count(agent.address)})
tx_hash = w3.eth.send_raw_transaction(agent.sign_transaction(tx).raw_transaction)
receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
```

To put a *reverted* attack on-chain as evidence (PRD `SKIP_SIMULATION`), skip `.call()` and set a
fixed `gas` (for example 200000) so the node does not refuse at gas estimation. This was checked
with `cast`: the result is a failed transaction with a hash and the `PayeeNotAllowed` revert data.

### Things the engine must know

- **Daily cap uses chain time** (`block.timestamp / 1 days`, UTC). The demo clock does not move
  it. On Anvil the engine can move chain time with `evm_increaseTime` + `evm_mine` so chain day =
  demo day. On Base Sepolia every demo step lands on the same real day: keep same-day payouts
  ≤ 600,000 (payroll 481,000 leaves 119,000) and redeploy for each rehearsal.
- **Owner approvals count toward the daily cap.** If a tier-2 approval would breach it, it reverts
  `ExceedsDailyCap` and stays Pending, so it can be approved the next day.
- **Vault share is enforced on-chain.** Deposits that would put more than 60% of `totalAssets()` in
  vaults revert `ExceedsVaultShare`. The engine should cap its sweep (finance demo: 2,808,000
  spare, 2,400,000 allowed). Withdrawals are never limited.
- **Feed staleness:** compare `updatedAt` with *chain* time, not the demo clock. Advancing the
  demo clock 25 days would otherwise make the feed look stale. The owner can refresh it by calling
  `setPrice` again with the same price.
- **Mock controls** (`setPrice`, `setRateBps`, `setUtilizationBps`, `setWithdrawalsPaused`,
  `simulateAccrual`) are owner-only on each mock. The deployer key owns them; the agent key never does.
- `ref` is any `bytes32`; the PRD convention is `keccak256("<obligationId>:<YYYY-MM>")` for
  scheduled runs.

## Tests

`forge test` runs 75 tests. Coverage of `Treasury.sol` is 100% of lines, statements, branches
and functions. Run one PRD group with `forge test --mt C5`.

| ID | Test(s) | Proves |
|---|---|---|
| C1 | `test_C1_*`, `testFuzz_C1_*` | Agent (or any non-owner) calling every owner function → `NotOwner`; state unchanged |
| C2 | `test_C2_*`, `testFuzz_C2_*` | Pay / batch / request to a non-allowlisted address → `PayeeNotAllowed`; batch is atomic |
| C3 | `test_C3_*`, `testFuzz_C3_*` | Pay at or above threshold → `RequiresApproval`; threshold − 1 succeeds |
| C4 | `test_C4_*`, `testFuzz_C4_*` | Request above cap → `ExceedsPerPaymentCap`; below threshold → `BelowApprovalThreshold` |
| C5 | `test_C5_*` | Breaching call → `ExceedsDailyCap` (exact boundary); batch total; next-day reset; approvals count |
| C6 | `test_C6_*` | Deposit/withdraw with non-allowlisted vault → `VaultNotAllowed` |
| C7 | `test_C7_*` | Every agent action while paused → `IsPaused` |
| C8 | `test_C8_*` | `emergencyExit` while paused (agent and owner), includes interest, retries through a freeze, works after de-listing |
| C9 | `test_C9_*` | Approve twice or approve after reject → `AlreadyExecuted` |
| C10 | `test_C10_*` | Approve after payee removed → `PayeeNotAllowed` (and after cap lowered) |
| C11 | `test_C11_*` | `approvalThreshold > perPaymentCap` → `InvalidCaps` |
| C12 | `test_C12_*` | Happy paths with events and balances: pay, 60-person payroll batch (481,000), request → approve/reject, deposit, withdraw, accrual, payday buffer top-up (−481,000 then +73,000 → 1,192,000) |

**Invariant suite** (`test/invariant/TreasuryInvariant.t.sol`): a handler plays a fully
compromised agent key. It makes 25,600 random calls (256 runs × 100) with attacker-chosen recipients,
amounts and vaults, and also tries every owner function, while time passes and the owner
approves requests. After every call:

1. every token ever minted is in the Treasury, the allowlisted vault or an allowlisted payee
   (nothing reaches the attacker, the agent or any other address);
2. payees received exactly the sum of successful payments;
3. `spentToday` never exceeds the daily cap on any day;
4. owner, agent, caps, vault share, policy hash, pause state and allowlists never change;
5. no deposit ever leaves vault holdings above the max share.

## Security notes (for the self-assessment)

- **Trust model:** the owner key is fully trusted (it can change any rule and withdraw). The agent
  key is untrusted: everything it can do is listed in the table above. The LLM never holds a key.
- **Additions beyond the PRD:** on-chain max vault share; `setPayees` batch; payee allowlist
  rejects the Treasury, owner and agent; owner ≠ agent everywhere; renounce disabled;
  `emergencyExit` also works for de-listed vaults (money can always come home);
  a status enum on pending requests (a rejected request cannot be approved later).
- **Known limits:** the daily cap is per UTC chain day, not a rolling 24 hours. Vaults are trusted
  once allowlisted, because the vault list is valued in `totalAssets()`. MockYieldVault is a
  simulation with no real yield. Demo payee addresses are fictional and have no private keys.
- OpenZeppelin v5.1.0 `Ownable`, `ReentrancyGuard` and `SafeERC20` are used. Fund-moving
  functions are `nonReentrant`, and events are emitted before token transfers.
