# Autonomous Treasury Agent — 2026 Shenzhen FinTechathon, Topic F

An autonomous treasurer for small crypto-native companies: it pays contributors and vendors on
schedule, keeps a protected buffer, moves only spare cash into a (simulated) yield vault, and exits
to safety on depeg or vault risk. It always acts inside a founder-signed policy that the wallet
contract enforces on-chain.

> **All transactions use zero-value testnet tokens; no real-value cryptocurrency or stablecoins were used.**

| Part | Where |
|---|---|
| On-chain vault: Treasury contract, mocks, Foundry tests C1–C12 and invariants, deploy scripts | [`contracts/`](contracts/README.md) |
| Deployed addresses and setup tx hashes (Base Sepolia, chain 84532) | [`deployments/`](deployments/base-sepolia-evidence.md) |
