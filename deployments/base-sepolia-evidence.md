# Base Sepolia deployment evidence

All transactions use zero-value testnet tokens; no real-value cryptocurrency or stablecoins were used.

Network: Base Sepolia (chain 84532). Owner `0x1eCCba43133d590E85F682B059bF328697e8033b`, agent `0xAEEd18B3485578fAf9262E4548ba139bC672182D`.

## Contracts

| Contract | Address |
|---|---|
| Treasury | [0xF265BbC1bdFeEa96e745225B7dd3f8E0e895c727](https://sepolia.basescan.org/address/0xF265BbC1bdFeEa96e745225B7dd3f8E0e895c727) |
| MockUSDC | [0xc637acDe7e58A35510080e0544B3a731db8A509c](https://sepolia.basescan.org/address/0xc637acDe7e58A35510080e0544B3a731db8A509c) |
| MockYieldVault | [0x65Ce1bB77186BeC362Ca165787487404ddFba843](https://sepolia.basescan.org/address/0x65Ce1bB77186BeC362Ca165787487404ddFba843) |
| MockPriceFeed | [0x77681210D03afc2eD793CEB21A597CDC1CED3309](https://sepolia.basescan.org/address/0x77681210D03afc2eD793CEB21A597CDC1CED3309) |

## Setup transactions

| # | Action | Block | Status | Tx |
|---|---|---|---|---|
| 1 | `deploy MockUSDC` | 48197134 | ok | [0x327db032…](https://sepolia.basescan.org/tx/0x327db0323b74bf62140eb129c5552275cc38a2c47bd120a9eb20cf6a74a8e354) |
| 2 | `deploy MockPriceFeed` | 48197134 | ok | [0x61177136…](https://sepolia.basescan.org/tx/0x611771360fea34a9c915df85de8358ee0f9ca239705b1ab78b1f532dc186f329) |
| 3 | `deploy MockYieldVault` | 48197134 | ok | [0x23cff79d…](https://sepolia.basescan.org/tx/0x23cff79d9b18e1dba556b6c2983281e3cc9e30733345a3a3a2c63abacb3b576e) |
| 4 | `deploy Treasury` | 48197134 | ok | [0xe7a830c0…](https://sepolia.basescan.org/tx/0xe7a830c064c5eafb6dd44a6e36356a3ab498eee1b6a0534ff7e8c67ce8b81c13) |
| 5 | `MockUSDC.setMinter` | 48197134 | ok | [0x169af025…](https://sepolia.basescan.org/tx/0x169af025d64a4dbd8d20fcb518fb4ad8edd1371b29e4e4a47094e54ef11eab45) |
| 6 | `Treasury.setVault` | 48197134 | ok | [0x9cd76224…](https://sepolia.basescan.org/tx/0x9cd762245f5f4e7bae60e7ea635bf21d8293b1d61c8da0ca07c62ca68eeed9b5) |
| 7 | `MockUSDC.mint` | 48197134 | ok | [0xcb6279ba…](https://sepolia.basescan.org/tx/0xcb6279bad240751a5d839da2aadc3621b3204eb87158b4eb171b4ea7b224d9c4) |
| 8 | `Treasury.setCaps` | 48197148 | ok | [0xd20fd931…](https://sepolia.basescan.org/tx/0xd20fd931f2d06369bb1ca6366506fb237efba29364d18cd0f490e5b015d828d8) |
| 9 | `Treasury.setMaxVaultShareBps` | 48197148 | ok | [0xa9809a6b…](https://sepolia.basescan.org/tx/0xa9809a6b2496c65668dc2bc5b0e4b6c22cd01d45dd0ac3596e973fdf37e4afcf) |
| 10 | `Treasury.setPayees` | 48197148 | ok | [0x0da21173…](https://sepolia.basescan.org/tx/0x0da21173fc70e689d5419dad7429a9d8ff4d78ea718767a1d00fee43750a352d) |
| 11 | `Treasury.setPayees` | 48197148 | ok | [0xa62cd657…](https://sepolia.basescan.org/tx/0xa62cd6571bfa7ca1e7cdebd2828c44a8c7be4302ef8479890e3acb50c96e267e) |
