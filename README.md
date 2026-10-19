[readme (3).md](https://github.com/user-attachments/files/33667166/readme.3.md)
# 🤖 Autonomous Treasury Agent

> **Compliance Declaration:** All transactions use zero-value testnet tokens; no real-value cryptocurrency or stablecoins were used.
> **Networks:** Base Sepolia (chain 84532) and local Anvil (chain 31337, offline fallback).

**2026 Shenzhen International FinTechathon — Topic F (Agent Wallet)**

The Autonomous Treasury Agent acts as an on-chain treasurer for small crypto-native companies. It autonomously executes payroll, vendor payments, yield vault deposits, and liquidity withdrawals, while operating strictly within a founder-signed policy that is deterministically enforced by a smart contract. 

Even if the off-chain AI agent or hot-key is compromised, manipulated by prompt injection, or suffers a logic failure, the smart contract mathematically prevents unauthorized spending, limits breaches, or policy violations. The off-chain AI can only *ask*; the contract *decides*.

---

## 🗂️ Project Structure

| Path | Description |
|---|---|
| `src/Treasury.sol` | The core vault contract enforcing roles, limits, allowlists, and emergency exits. |
| `src/mocks/` | Zero-value mocks: `MockUSDC`, `MockYieldVault`, `MockPriceFeed`. |
| `script/` | Foundry deployment and demo seeding scripts. |
| `test/` | 75 Foundry tests (C1-C12) and the stateful fuzzing invariant suite. |
| `agent/engine.py` | The main execution agent (Risk Monitor, Sweep Logic, Executor, Logger). |
| `agent/engine_logic.py` | Deterministic treasury math (buffers, caps, sweeping). |
| `agent/explainer.py` | LLM module for generating plain-English executive summaries of actions. |
| `agent/app.py` | The Streamlit executive dashboard. |
| `agent/policy.json` | The founder-defined rule configuration (caps, schedules, allowlists). |
| `deployments/` | Contract addresses, owner, agent, and start block data. |

---

## ⚙️ Prerequisites & Installation

**1. System Dependencies**
*   **Foundry**: Contract compilation and testing (`curl -L https://getfoundry.sh | bash`)
*   **Python 3.10+**: Off-chain agent and dashboard

**2. Clone and Install Python Packages:**
```bash
git clone <your-repo-link>
cd <repo-folder>
pip install -r requirements.txt
```

**3. Environment Configuration:**
Copy the example environment file and populate it with your testnet keys.
```bash
cp .env.example .env
```
Inside `.env`, configure:
*   `BASE_SEPOLIA_RPC`: e.g., `https://sepolia.base.org`
*   `OWNER_PRIVATE_KEY`: Founder key for contract deployment and approvals.
*   `AGENT_PRIVATE_KEY`: Agent hot key for autonomous transactions. (Must have Base Sepolia ETH for gas).
*   `OPENAI_API_KEY`: For the LLM explainer (or use `OPENAI_BASE_URL` for local models).

---

## 🚀 Smart Contract Deployment

**Local Testing (Offline):**
```bash
make anvil           # terminal 1: local chain on http://127.0.0.1:8545
make deploy-local    # terminal 2: deploy + write deployments/anvil.json
make seed-local      # finance demo policy + deployments/demo-payees.json
```

**Live Testnet (Base Sepolia):**
```bash
make deploy-base-sepolia
make seed-base-sepolia
```
*This deploys the Treasury, mints 4,000,000 zero-value mUSDC, and syncs the agent.*

---

## 🏃 Running the AI Agent

The Python agent operates in three distinct modes.

**1. Simulated Test Suite (Debug Mode)**
Runs the core scenarios locally without spending gas, including the 60% vault cap logic and the $0.96 depeg emergency exit.
```bash
python3 agent/engine.py --debug
```

**2. Live On-Chain Execution**
Connects to Base Sepolia, evaluates the contract state against `policy.json`, and broadcasts real transactions if actions are required (e.g., Yield Sweep, Payroll).
```bash
python3 agent/engine.py --live
```

**3. Adversarial Security Suite**
Forces prompt-injection and out-of-bounds payment attacks onto Base Sepolia to generate verifiable, reverted on-chain execution evidence.
```bash
python3 agent/engine.py --live --attacks
```

---

## 📊 Launching the Dashboard

Open a separate terminal to run the interactive UI. The dashboard automatically syncs with the blockchain telemetry and reads the agent's SQLite `decisions.db`.

```bash
streamlit run agent/app.py
```

---

## ⚖️ Smart Contract Roles & Rules

**Owner** = founder key. **Agent** = service hot key. They must be different addresses. The constructor, `setAgent`, and `transferOwnership` all enforce this. 

| Function | Caller | Enforced On-Chain (reverts otherwise) |
|---|---|---|
| `pay(...)` | Agent | not paused · `isPayee` · `amount < approvalThreshold` · day total ≤ `dailyPaymentCap` |
| `payBatch(...)` | Agent | same per item · daily cap on the batch total · atomic execution |
| `requestPayment(...)` | Agent | not paused · `isPayee` · `approvalThreshold ≤ amount ≤ perPaymentCap` · moves no funds |
| `depositToVault(...)` | Agent | not paused · `isVault` · vault holdings after deposit ≤ `maxVaultShareBps` · receiver is Treasury |
| `withdrawFromVault(...)` | Agent | not paused · `isVault` · funds always return to the Treasury |
| `emergencyExit(...)` | Agent **or** Owner | **works while paused** · any vault ever allowlisted · pulls the full position home |
| `approvePayment(...)` | Owner | request pending · payee allowlisted · amount ≤ current cap · counts toward daily cap |
| `rejectPayment(...)` | Owner | request still pending |

### Critical Integration Notes for the Engine
*   **Daily cap uses chain time** (`block.timestamp / 1 days`, UTC). 
*   **Owner approvals count toward the daily cap.** If a tier-2 approval would breach it, it reverts with `ExceedsDailyCap` and stays Pending, so it can be approved the next day.
*   **Vault share is enforced on-chain.** Deposits that would put more than 60% of `totalAssets()` in vaults revert with `ExceedsVaultShare`.
*   **Idempotency:** `ref` is indexed in `PaymentExecuted`. The engine filters by it to make payroll idempotent, physically preventing duplicate monthly runs.

---

## 🛡️ Security & Testing

The security of the Treasury is guaranteed on-chain. The system utilizes OpenZeppelin v5.1.0 `Ownable`, `ReentrancyGuard`, and `SafeERC20`.

```bash
forge test
```
Coverage of `Treasury.sol` is 100% of lines, statements, branches, and functions. 

| ID | Test Focus | Proves |
|---|---|---|
| **C1** | Access Control | Agent calling owner functions → `NotOwner`; state unchanged. |
| **C2** | Payee Allowlist | Pay/request to unlisted address → `PayeeNotAllowed`. |
| **C3-C4** | Thresholds & Caps | Enforces `approvalThreshold` and `perPaymentCap`. |
| **C5** | Daily Limits | Exact boundary enforcement of `dailyPaymentCap` across batches and approvals. |
| **C7-C8** | Circuit Breakers | Agent actions while paused → `IsPaused`. `emergencyExit` succeeds while paused. |
| **C12** | Happy Path | End-to-end integration of payroll, sweeping, and buffer top-ups. |

**Invariant Fuzzing (`TreasuryInvariant.t.sol`):**
A handler plays a fully compromised agent key. It makes 25,600 random calls (256 runs × 100) with attacker-chosen recipients, amounts, and vaults. At the end of every run, it proves:
1. Every token ever minted is in the Treasury, the allowlisted vault, or an allowlisted payee (funds cannot be extracted).
2. The `spentToday` limit is never breached.
3. The Owner, Caps, Vault Share, and Policy Hash are completely immutable against the Agent.
