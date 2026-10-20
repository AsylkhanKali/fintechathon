[README.md](https://github.com/user-attachments/files/33705260/README.md)
# FourEyes: Autonomous Treasury Agent

**Team FourEyes (NYU Abu Dhabi) · 2026 Shenzhen International FinTechathon · International Track · Topic F: Agent Wallet**

> **Compliance declaration.** All transactions use zero-value test tokens (mUSDC) on the Base Sepolia testnet (chain 84532) or a local Anvil chain (chain 31337). No real-value cryptocurrency or stablecoin is used anywhere in this project.

FourEyes runs the treasury of a small crypto-native company. It pays the team and vendors on schedule, keeps a protected cash buffer, puts spare cash to work in a yield vault, and pulls everything back when the stablecoin or the vault looks risky. It does all of this on its own, but only inside limits the founder has signed and the smart contract enforces.

The name comes from the banking four-eyes principle: no money moves on one party's word.

- **The Planner** (`engine.py`, `engine_logic.py`) is the off-chain agent. It reads balances, prices and the payment schedule, decides what to do, and signs with a low-privilege agent key.
- **The Treasurer** (`contracts/src/Treasury.sol`) holds the funds and re-checks every call: who is calling, to whom, how much, how much today. Anything outside the rules reverts.
- **The founder** holds the owner key. They set the rules and approve large payments, and they can pause the agent or pull funds back at any time.
- **The LLM explainer** (`explainer.py`) writes a plain-English explanation of each decision after it is made. It has no key and cannot change any decision.

Even if the agent key, the engine or the LLM is fully compromised, funds cannot leave the founder-signed policy. The agent can only ask; the contract decides.

---

## Permission tiers

| Tier | When | Who acts |
|---|---|---|
| **0 · Autonomous** | Scheduled payroll and vendor runs, and any invoice under 40,000, to allowlisted payees within the 600,000 daily cap; vault sweeps up to the 60% limit; withdrawals | The agent alone |
| **1 · Post-payment review** | A Tier 0 payment more than 10% above that payee's usual amount, or any emergency exit | The founder reviews it in the dashboard afterwards |
| **2 · Founder approval** | Any payment from 40,000 to 100,000 | The agent calls `requestPayment`; nothing moves until the founder signs `approvePayment` |
| **3 · Hard rejection** | A payee not on the allowlist, more than 100,000, or a day total above 600,000 | Nobody: the contract reverts |

**Circuit breaker.** If the stablecoin price falls to $0.98 or below, or the vault pauses withdrawals, the agent calls `emergencyExit`. This works even while the Treasury is paused and always returns the full vault position to the Treasury.

---

## Live deployment (Base Sepolia, chain 84532)

| Component | Address |
|---|---|
| Treasury (the Treasurer) | [`0xF265BbC1bdFeEa96e745225B7dd3f8E0e895c727`](https://base-sepolia.blockscout.com/address/0xF265BbC1bdFeEa96e745225B7dd3f8E0e895c727) |
| MockUSDC (zero-value test token, 6 decimals) | [`0xc637acDe7e58A35510080e0544B3a731db8A509c`](https://base-sepolia.blockscout.com/address/0xc637acDe7e58A35510080e0544B3a731db8A509c) |
| MockYieldVault (simulated yield venue) | [`0x65Ce1bB77186BeC362Ca165787487404ddFba843`](https://base-sepolia.blockscout.com/address/0x65Ce1bB77186BeC362Ca165787487404ddFba843) |
| MockPriceFeed (Chainlink-style USDC/USD) | [`0x77681210D03afc2eD793CEB21A597CDC1CED3309`](https://base-sepolia.blockscout.com/address/0x77681210D03afc2eD793CEB21A597CDC1CED3309) |
| Owner key (founder) | [`0x1eCCba43133d590E85F682B059bF328697e8033b`](https://base-sepolia.blockscout.com/address/0x1eCCba43133d590E85F682B059bF328697e8033b) |
| Agent key (Planner, current) | [`0x2C778d095aEFcdd7EdBB925B4E460DA1695884D2`](https://base-sepolia.blockscout.com/address/0x2C778d095aEFcdd7EdBB925B4E460DA1695884D2) |

The agent key was rotated by the founder with `setAgent` at block 48,238,171. The deployment-time agent recorded in `deployments/base-sepolia.json` (`0xAEEd…182D`) is retired and has no authority.

Every on-chain transaction, including payroll, vault sweeps, the founder approval, the emergency exits and 15 reverted attacks, is listed with links in [`deployments/base-sepolia-evidence.md`](deployments/base-sepolia-evidence.md).

---

## Repository layout

| Path | What it is |
|---|---|
| `engine.py` | The Planner: reads the chain, routes each action to a tier, runs a pre-flight simulation, signs, logs to SQLite, exports audit and reconciliation CSVs |
| `engine_logic.py` | Deterministic treasury maths: obligations, buffer, sweep and restore, risk rules |
| `explainer.py` | LLM explanation layer (any OpenAI-compatible endpoint), with a template fallback when no model is reachable |
| `app.py` | Streamlit founder dashboard: overview, approvals, payroll, vendors, treasury, security, audit log |
| `policy.json` | The founder-signed policy: buffer, limits, risk thresholds, schedules and allowlisted payees. Its hash is stored on-chain |
| `requirements.txt` | Python dependencies |
| `.env.example` | Engine and dashboard settings; copy to `.env` |
| `contracts/src/Treasury.sol` | The Treasurer contract |
| `contracts/src/mocks/` | MockUSDC, MockYieldVault, MockPriceFeed (zero value, owner-controlled for demos) |
| `contracts/test/` | 75 Foundry tests (C1–C12, mocks) and the invariant suite |
| `contracts/script/` | Deployment and demo-seeding scripts |
| `contracts/abi/` | Contract ABIs used by the engine |
| `contracts/broadcast/` | Foundry records of the Base Sepolia deployment |
| `contracts/README.md` | Contract reference: every function, event, custom error and selector |
| `deployments/` | Deployed addresses (Base Sepolia and Anvil), demo payees, on-chain evidence |

---

## Quick start (no keys needed)

Requires **Python 3.10+**. Foundry is needed only for the contract tests and the local chain.

```bash
git clone https://github.com/AsylkhanKali/fintechathon.git
cd fintechathon
pip install -r requirements.txt
```

**1. Run the treasury scenarios in simulation.** Nothing is sent on-chain and no gas is spent. This runs payroll day, vendor day, an idle day, a yield sweep, the 60% vault limit, a buffer restore, a $0.96 depeg exit and an ad-hoc invoice.

```bash
python3 engine.py --debug
```

**2. Open the founder dashboard.** It reads live balances from the Base Sepolia deployment through the public RPC.

```bash
streamlit run app.py
```

**3. Run the contract tests** ([Foundry](https://getfoundry.sh) required).

```bash
cd contracts
make test        # forge test: 75 tests, including fuzzing and invariants
make coverage    # 100% line, statement, branch and function coverage of Treasury.sol
```

---

## Live mode (Base Sepolia)

Live runs sign with the registered agent key, which only the team holds. Without it, use the simulation above, the local chain below, or the on-chain evidence.

```bash
cp .env.example .env     # then set AGENT_PRIVATE_KEY (and optionally OPENAI_API_KEY)
python3 engine.py --live             # one live run: check the chain and policy, then act
python3 engine.py --live --attacks   # adversarial suite: attacks are broadcast on purpose and revert on-chain
```

Each live run checks that the chain is 84532 or 31337, that the hash of `policy.json` matches the fingerprint stored in the Treasury, and that every call passes a pre-flight simulation before it is signed. Payroll is idempotent: a payment reference that is already confirmed in the log or on-chain is never paid again.

> `python3 engine.py --live --test` runs every simulation scenario against the real chain. Use it only on purpose.

**Changing the policy.** If you edit `policy.json`, the live engine stops until the founder stores the new fingerprint on-chain:

```bash
# Hash printed by the engine at startup ("Local Policy Hash")
cast send 0xF265BbC1bdFeEa96e745225B7dd3f8E0e895c727 "setPolicyHash(bytes32)" <hash> \
  --private-key $OWNER_PRIVATE_KEY --rpc-url https://sepolia.base.org
```

---

## Offline fallback (local Anvil chain)

For a venue without internet, the whole system runs on a local chain, and the explainer can use a local model or its template fallback.

```bash
cd contracts
make anvil          # terminal 1: local chain on http://127.0.0.1:8545
make deploy-local   # terminal 2: deploy, writes ../deployments/anvil.json
make seed-local     # allowlist the demo payees
cd ..
```

Then point `.env` at the local deployment (addresses from `deployments/anvil.json`):

```bash
BASE_SEPOLIA_RPC=http://127.0.0.1:8545
TREASURY_ADDRESS=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
VAULT_ADDRESS=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
PRICE_FEED_ADDRESS=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
AGENT_PRIVATE_KEY=<Anvil account #1 key, printed by `anvil` at startup>
OPENAI_BASE_URL=http://localhost:11434/v1   # optional: a local model, e.g. Ollama
```

The Anvil keys are public, zero-value development keys. Use them only on the local chain.

---

## Contract rules

**Owner** is the founder key; **agent** is the service key. They must be different addresses (enforced by the constructor, `setAgent` and `transferOwnership`), and the agent can never be a payee.

| Function | Caller | Enforced on-chain (reverts otherwise) |
|---|---|---|
| `pay` | Agent | Not paused · payee allowlisted · amount below 40,000 · day total ≤ 600,000 |
| `payBatch` | Agent | Same checks for every item · daily cap on the batch total · all-or-nothing |
| `requestPayment` | Agent | Not paused · payee allowlisted · 40,000 ≤ amount ≤ 100,000 · moves no funds |
| `depositToVault` | Agent | Not paused · vault allowlisted · vault holdings stay ≤ 60% of total assets |
| `withdrawFromVault` | Agent | Not paused · vault allowlisted · funds always return to the Treasury |
| `emergencyExit` | Agent or owner | Works while paused · any vault ever allowlisted · full position returns to the Treasury |
| `approvePayment` | Owner | Request pending · payee still allowlisted · amount within the current cap · counts toward the daily cap |
| `rejectPayment` | Owner | Request still pending |
| `setCaps`, `setMaxVaultShareBps`, `setPayees`, `setVault`, `setAgent`, `setPolicyHash`, `pause`, `unpause`, `ownerWithdraw` | Owner | Owner only; `renounceOwnership` is disabled so the pause switch can never be lost |

The daily cap uses chain time (UTC day). The contract is built on OpenZeppelin Contracts 5.1.0 (`Ownable`, `ReentrancyGuard`, `SafeERC20`). Full reference: [`contracts/README.md`](contracts/README.md).

---

## Testing

| Suite | What it proves |
|---|---|
| **C1–C12** (`forge test`) | Access control, payee allowlist, approval threshold, per-payment and daily caps, vault allowlist, pause, emergency exit while paused or during a vault freeze, double approval, approval after a payee is removed, invalid caps, and full happy paths (60-person payroll, approvals, deposits, withdrawals, buffer restore) |
| **Invariant suite** | A simulated, fully compromised agent makes 25,600 random calls. After every call: every token is in the Treasury, the vault or an allowlisted payee; the daily cap was never exceeded; no rule, role or allowlist changed |
| **Engine scenarios** (`--debug`) | The Planner's decisions for each treasury situation, without spending gas |
| **Attack suite** (`--live --attacks`) | Prompt injection, non-allowlisted payee and over-cap payment, each broadcast on purpose with the pre-flight check skipped so the contract itself must revert |

---

## Keys and secrets

- `.env` files are git-ignored. No private key is stored in this repository.
- The **owner key** stays in the founder's own wallet and is used only for founder actions. The engine never loads it.
- The **agent key** is low-privilege by design and can be rotated by the founder with `setAgent`.
- **`FOUNDER_DEMO_PRIVATE_KEY`** lets the dashboard sign founder actions. It is for a local demo laptop only: never put it in the repository or in any hosted deployment's secrets. Without it, Approve and Deny are still recorded and the founder completes them from their own wallet. That is the default, and the safer setup.

---

## Team

| Member | Study | Contribution |
|---|---|---|
| Taib El Khatib | Electrical Engineering | Research, system design and architecture, reconciliation across workstreams, presentation |
| Adam Drai | Political Science | Ideation, research, system design and architecture, founder dashboard and demo |
| Wade'a Ahmad | Computer Science and Mathematics | The Planner agent (payouts, buffer, sweeps, exits), technical documentation |
| Asylkhan Kali | Computer Engineering | The Treasurer (Treasury.sol and its security rules), security self-assessment |
| Christian Sireau | Legal Studies | Ideation, research and architecture, regulatory analysis, coordination with the organizers |

Released under the MIT License (see `LICENSE`). Third-party components keep their own licenses (OpenZeppelin Contracts and forge-std: MIT).
