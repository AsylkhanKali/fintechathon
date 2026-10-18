[readme (2).md](https://github.com/user-attachments/files/33624497/readme.2.md)
# 🤖 Autonomous Treasury Agent

> **All transactions use zero-value testnet tokens; no real-value cryptocurrency or stablecoins were used.**
> Networks: Base Sepolia (chain 84532) and local Anvil (chain 31337, offline fallback).

**2026 Shenzhen International FinTechathon — Topic F (Agent Wallet)**

The Autonomous Treasury Agent acts as an on-chain treasurer for small crypto-native companies. It autonomously executes payroll, vendor payments, yield vault deposits, and liquidity withdrawals, while operating strictly within a founder-signed policy that is deterministically enforced by a smart contract. 

Even if the off-chain AI agent or hot key is compromised, manipulated by prompt injection, or suffers a logic failure, the smart contract mathematically prevents unauthorized spending, limits breaches, or policy violations.

## 🗂️ Project Structure

| Path | Description |
|---|---|
| `src/Treasury.sol` | The core vault contract enforcing roles, limits, allowlists, and emergency exits. |
| `src/mocks/` | Zero-value mocks: `MockUSDC`, `MockYieldVault`, `MockPriceFeed`. |
| `script/` | Foundry deployment and demo seeding scripts. |
| `test/` | 75 Foundry tests (C1-C12) and the stateful fuzzing invariant suite. |
| `engine.py` | The main execution agent (Risk Monitor, Sweep Logic, Executor, Logger). |
| `engine_logic.py` | Deterministic treasury math (buffers, caps, sweeping). |
| `explainer.py` | LLM module for generating plain-English executive summaries of actions. |
| `app.py` | The Streamlit executive dashboard. |
| `policy.json` | The founder-defined rule configuration (caps, schedules, allowlists). |

## ⚙️ Prerequisites

1. **Foundry**: Contract compilation and testing (`curl -L https://getfoundry.sh | bash`)
2. **Python 3.10+**: Off-chain agent and dashboard
3. **Base Sepolia ETH**: Faucet-provided test ETH for the Agent and Owner wallets to cover gas. *(Must use a faucet that does not require holding mainnet funds).*

## 🚀 Setup & Installation

**1. Clone and Install Dependencies:**
```bash
git clone <your-repo-link>
cd <repo-folder>
pip install web3 python-dotenv streamlit pandas altair openai
```

**2. Environment Configuration:**
Copy the example environment file and populate it with your testnet keys.
```bash
cp .env.example .env
```
Inside `.env`, you will need:
*   `BASE_SEPOLIA_RPC`: e.g., `https://sepolia.base.org`
*   `OWNER_PRIVATE_KEY`: Founder key for contract deployment and approvals.
*   `AGENT_PRIVATE_KEY`: Agent hot key for autonomous transactions.
*   `OPENAI_API_KEY`: For the LLM explainer (or use `OPENAI_BASE_URL` for local models).

**3. Deploy the Smart Contracts:**
```bash
# Terminal 1: (If testing locally via Anvil fallback)
make anvil

# Terminal 2: Deploy to Base Sepolia (or Anvil)
make deploy-base-sepolia
make seed-base-sepolia
```
*This deploys the Treasury, mints 4,000,000 zero-value mUSDC, and syncs the agent.*

## 🏃 Running the Agent

The agent operates in three distinct modes.

**1. Simulated Test Suite (Debug Mode)**
Runs the 7 core PRD scenarios locally without spending gas, including the 60% vault cap logic and the $0.96 depeg emergency exit.
```bash
python3 engine.py --debug
```

**2. Live On-Chain Execution**
Connects to Base Sepolia, evaluates the current contract state, processes the founder's `policy.json`, and broadcasts real transactions if actions are required (e.g., Yield Sweep).
```bash
python3 engine.py --live
```

**3. Adversarial Security Suite**
Forces prompt-injection and out-of-bounds payment attacks onto Base Sepolia to generate verifiable, reverted on-chain execution evidence.
```bash
python3 engine.py --live --attacks
```

## 📊 Launching the Dashboard

Open a separate terminal to run the interactive UI. The dashboard automatically syncs with the blockchain telemetry and reads the agent's SQLite `decisions.db`.

```bash
streamlit run app.py
```

## 🛡️ Security & Testing

The security of the Treasury is guaranteed on-chain. Run the Foundry unit and invariant test suite:

```bash
forge test
```
*   **C1-C12 Unit Tests:** Asserts all specific access controls, daily caps, and approval thresholds.
*   **Invariant Fuzzing:** Simulates a fully compromised agent making 25,600 random calls to prove funds cannot be extracted to unauthorized addresses. 
*   **Audit Reconciliation:** Running the Python engine automatically exports `audit_decisions.csv` and `reconciliation_report.csv` to ensure 100% parity between off-chain intent and on-chain BaseScan logs.
