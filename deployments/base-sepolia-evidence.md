[base-sepolia-evidence.md](https://github.com/user-attachments/files/33705404/base-sepolia-evidence.md)
# Base Sepolia on-chain evidence

All transactions use zero-value testnet tokens (mUSDC) on Base Sepolia (chain 84532); no real-value cryptocurrency or stablecoins were used.

This is every transaction behind FourEyes: the 5 mock-contract setup transactions and all 38 transactions ever sent to the Treasury, checked on Blockscout. Reverted rows are deliberate attacks that the contract refused, plus one payroll attempt that ran out of gas without paying anyone.

- Owner (founder): [`0x1eCCba43133d590E85F682B059bF328697e8033b`](https://base-sepolia.blockscout.com/address/0x1eCCba43133d590E85F682B059bF328697e8033b)
- Agent (Planner, current): [`0x2C778d095aEFcdd7EdBB925B4E460DA1695884D2`](https://base-sepolia.blockscout.com/address/0x2C778d095aEFcdd7EdBB925B4E460DA1695884D2), registered with `setAgent` at block 48,238,171. The deployment-time agent `0xAEEd18B3485578fAf9262E4548ba139bC672182D` in `base-sepolia.json` is retired and never transacted.
- Before block 48,238,171 the current agent address was not yet registered, so its calls in rows 12–17 revert with `NotAgent`.

## Contracts

| Contract | Address |
|---|---|
| Treasury | [`0xF265BbC1bdFeEa96e745225B7dd3f8E0e895c727`](https://base-sepolia.blockscout.com/address/0xF265BbC1bdFeEa96e745225B7dd3f8E0e895c727) |
| MockUSDC | [`0xc637acDe7e58A35510080e0544B3a731db8A509c`](https://base-sepolia.blockscout.com/address/0xc637acDe7e58A35510080e0544B3a731db8A509c) |
| MockYieldVault | [`0x65Ce1bB77186BeC362Ca165787487404ddFba843`](https://base-sepolia.blockscout.com/address/0x65Ce1bB77186BeC362Ca165787487404ddFba843) |
| MockPriceFeed | [`0x77681210D03afc2eD793CEB21A597CDC1CED3309`](https://base-sepolia.blockscout.com/address/0x77681210D03afc2eD793CEB21A597CDC1CED3309) |

## All transactions

| # | Block | Time (UTC) | Signer | What | Function | Result | Transaction |
|---|---|---|---|---|---|---|---|
| 1 | 48,197,134 | 16 Oct 14:55 | Owner | Deploy MockUSDC | `deploy MockUSDC` | OK | [`0x327db032…74a8e354`](https://base-sepolia.blockscout.com/tx/0x327db0323b74bf62140eb129c5552275cc38a2c47bd120a9eb20cf6a74a8e354) |
| 2 | 48,197,134 | 16 Oct 14:55 | Owner | Deploy MockPriceFeed | `deploy MockPriceFeed` | OK | [`0x61177136…c186f329`](https://base-sepolia.blockscout.com/tx/0x611771360fea34a9c915df85de8358ee0f9ca239705b1ab78b1f532dc186f329) |
| 3 | 48,197,134 | 16 Oct 14:55 | Owner | Deploy MockYieldVault | `deploy MockYieldVault` | OK | [`0x23cff79d…cb3b576e`](https://base-sepolia.blockscout.com/tx/0x23cff79d9b18e1dba556b6c2983281e3cc9e30733345a3a3a2c63abacb3b576e) |
| 4 | 48,197,134 | 16 Oct 14:55 | Owner | Deploy Treasury | `deploy Treasury` | OK | [`0xe7a830c0…e8b81c13`](https://base-sepolia.blockscout.com/tx/0xe7a830c064c5eafb6dd44a6e36356a3ab498eee1b6a0534ff7e8c67ce8b81c13) |
| 5 | 48,197,134 | 16 Oct 14:55 | Owner | Allow the faucet to mint mUSDC | `MockUSDC.setMinter` | OK | [`0x169af025…f11eab45`](https://base-sepolia.blockscout.com/tx/0x169af025d64a4dbd8d20fcb518fb4ad8edd1371b29e4e4a47094e54ef11eab45) |
| 6 | 48,197,134 | 16 Oct 14:55 | Owner | Allowlist the vault | `setVault` | OK | [`0x9cd76224…8eeed9b5`](https://base-sepolia.blockscout.com/tx/0x9cd762245f5f4e7bae60e7ea635bf21d8293b1d61c8da0ca07c62ca68eeed9b5) |
| 7 | 48,197,134 | 16 Oct 14:55 | Owner | Fund the Treasury with 4,000,000 mUSDC | `MockUSDC.mint` | OK · 4,000,000.00 to the Treasury | [`0xcb6279ba…b224d9c4`](https://base-sepolia.blockscout.com/tx/0xcb6279bad240751a5d839da2aadc3621b3204eb87158b4eb171b4ea7b224d9c4) |
| 8 | 48,197,148 | 16 Oct 14:56 | Owner | Set the 40,000 / 100,000 / 600,000 limits | `setCaps` | OK | [`0xd20fd931…15d828d8`](https://base-sepolia.blockscout.com/tx/0xd20fd931f2d06369bb1ca6366506fb237efba29364d18cd0f490e5b015d828d8) |
| 9 | 48,197,148 | 16 Oct 14:56 | Owner | Set the 60% vault limit | `setMaxVaultShareBps` | OK | [`0xa9809a6b…37e4afcf`](https://base-sepolia.blockscout.com/tx/0xa9809a6b2496c65668dc2bc5b0e4b6c22cd01d45dd0ac3596e973fdf37e4afcf) |
| 10 | 48,197,148 | 16 Oct 14:56 | Owner | Allowlist payees (batch 1) | `setPayees` | OK | [`0x0da21173…750a352d`](https://base-sepolia.blockscout.com/tx/0x0da21173fc70e689d5419dad7429a9d8ff4d78ea718767a1d00fee43750a352d) |
| 11 | 48,197,148 | 16 Oct 14:56 | Owner | Allowlist payees (batch 2) | `setPayees` | OK | [`0xa62cd657…c96e267e`](https://base-sepolia.blockscout.com/tx/0xa62cd6571bfa7ca1e7cdebd2828c44a8c7be4302ef8479890e3acb50c96e267e) |
| 12 | 48,230,328 | 17 Oct 09:22 | Unregistered | Attack: unregistered key | `payBatch` | Reverted · NotAgent | [`0xb30382d3…9d57ad49`](https://base-sepolia.blockscout.com/tx/0xb30382d3a9190aedb6e36184573f2fad73caf87521e0fbbd402ced039d57ad49) |
| 13 | 48,230,430 | 17 Oct 09:25 | Unregistered | Attack: unregistered key | `payBatch` | Reverted · NotAgent | [`0x099835d5…fa27fe61`](https://base-sepolia.blockscout.com/tx/0x099835d5e1fd830b860504cd2172787962dfc5e9e21cdfa94b83087ffa27fe61) |
| 14 | 48,230,539 | 17 Oct 09:29 | Unregistered | Attack: unregistered key | `payBatch` | Reverted · NotAgent | [`0x9aee3c4b…4678061c`](https://base-sepolia.blockscout.com/tx/0x9aee3c4b1eff4206fb47846dc3b4f97e2acc020a4991ed366a99c55f4678061c) |
| 15 | 48,230,540 | 17 Oct 09:29 | Unregistered | Attack: unregistered key | `depositToVault` | Reverted · NotAgent | [`0xfe67eb20…b8d3ac81`](https://base-sepolia.blockscout.com/tx/0xfe67eb20e8afa57cdd06fce934450575a14203d4e6eb42f3f695d99ab8d3ac81) |
| 16 | 48,237,650 | 17 Oct 13:26 | Unregistered | Attack: unregistered key | `pay` | Reverted · NotAgent | [`0x72933288…4db25c53`](https://base-sepolia.blockscout.com/tx/0x7293328848fe1348b2f6b4d03a74da0bcd2679e42943e863925097da4db25c53) |
| 17 | 48,237,652 | 17 Oct 13:26 | Unregistered | Attack: unregistered key | `requestPayment` | Reverted · NotAgent | [`0x39970d13…6a8d3f72`](https://base-sepolia.blockscout.com/tx/0x39970d13ab4478a471788d78e54247934bc1c479609d1d16db04f7bb6a8d3f72) |
| 18 | 48,238,171 | 17 Oct 13:43 | Owner | Founder registers the agent key (rotation) | `setAgent` | OK | [`0x2d2da1e3…e053cc3b`](https://base-sepolia.blockscout.com/tx/0x2d2da1e36f57e51c4100d6e64da8db7ee38ece6d07ef9baf289c5b74e053cc3b) |
| 19 | 48,238,172 | 17 Oct 13:43 | Owner | Founder stores the policy fingerprint | `setPolicyHash` | OK | [`0x79a07de0…d55038f4`](https://base-sepolia.blockscout.com/tx/0x79a07de059a8b6ab9d99d2184e39cb238d244b6460082f7ccbca4a91d55038f4) |
| 20 | 48,238,192 | 17 Oct 13:44 | Agent | Vault sweep | `depositToVault` | OK · 2,400,000.00 | [`0x9729a87b…a1088357`](https://base-sepolia.blockscout.com/tx/0x9729a87b027f945e975fb2b4420fa8cd71a15e4ddff2aa588763821ca1088357) |
| 21 | 48,238,226 | 17 Oct 13:45 | Agent | Attack: prompt-injected invoice to a non-allowlisted address | `pay` | Reverted · PayeeNotAllowed | [`0x66fb4068…94721595`](https://base-sepolia.blockscout.com/tx/0x66fb4068bf96a69c16288f1c1d2e5f0a3edd620b164ba59d2b0ae4a994721595) |
| 22 | 48,238,227 | 17 Oct 13:45 | Agent | Attack: 150,000 request above the 100,000 cap | `requestPayment` | Reverted · ExceedsPerPaymentCap | [`0x4dbbd8f9…ccb7cee7`](https://base-sepolia.blockscout.com/tx/0x4dbbd8f9df4d50bc0d9147e9ac1243a080fe99bff399a7afdb485b7cccb7cee7) |
| 23 | 48,238,547 | 17 Oct 13:56 | Agent | Attack: prompt-injected invoice | `pay` | Reverted · PayeeNotAllowed | [`0x02a99ab9…aae9ad03`](https://base-sepolia.blockscout.com/tx/0x02a99ab946b56d40ea579a07cd2acd38565e1147ecee4577781ed477aae9ad03) |
| 24 | 48,238,549 | 17 Oct 13:56 | Agent | Attack: over-cap request | `requestPayment` | Reverted · ExceedsPerPaymentCap | [`0x55193af7…643450a9`](https://base-sepolia.blockscout.com/tx/0x55193af728ee184d4ea830b9e75dac417278da8008c961f01979557e643450a9) |
| 25 | 48,244,144 | 17 Oct 17:02 | Owner | Founder emergency exit | `emergencyExit` | OK · 2,400,045.30 | [`0xf0d58099…470e18d9`](https://base-sepolia.blockscout.com/tx/0xf0d58099e0311dd41912b3364094eef50bb761be179a60e3ae55faa6470e18d9) |
| 26 | 48,244,238 | 17 Oct 17:06 | Agent | Attack: prompt-injected invoice | `pay` | Reverted · PayeeNotAllowed | [`0x0137f29a…38461aec`](https://base-sepolia.blockscout.com/tx/0x0137f29aca434f4f98d6a9b31f00bdc960cf1d98bbd13da800e3108838461aec) |
| 27 | 48,244,239 | 17 Oct 17:06 | Agent | Attack: over-cap request | `requestPayment` | Reverted · ExceedsPerPaymentCap | [`0x1d30ae3a…bc723813`](https://base-sepolia.blockscout.com/tx/0x1d30ae3a52181dd6e7323da8e3d393af02546de515477ce69e89773fbc723813) |
| 28 | 48,271,307 | 18 Oct 08:08 | Agent | Vault sweep | `depositToVault` | OK · 2,400,026.18 | [`0xb7d70fcc…093aabc3`](https://base-sepolia.blockscout.com/tx/0xb7d70fcc4f8df396bae7febe92d8a9d9c2b6164436d4e814067bd23c093aabc3) |
| 29 | 48,271,324 | 18 Oct 08:08 | Agent | Attack: prompt-injected invoice | `pay` | Reverted · PayeeNotAllowed | [`0xa88d7c13…a621cc72`](https://base-sepolia.blockscout.com/tx/0xa88d7c13b1e48adc8095f4b577c929278f931b072481e0232f86de8aa621cc72) |
| 30 | 48,271,325 | 18 Oct 08:08 | Agent | Attack: over-cap request | `requestPayment` | Reverted · ExceedsPerPaymentCap | [`0xafd347a9…6cf128d1`](https://base-sepolia.blockscout.com/tx/0xafd347a9d01e01b7f874303aa0a34bbbecbf9330f05643e9ee8cd3556cf128d1) |
| 31 | 48,305,427 | 19 Oct 03:05 | Owner | Founder stores the updated policy fingerprint | `setPolicyHash` | OK | [`0xb5864a81…09ff1d3e`](https://base-sepolia.blockscout.com/tx/0xb5864a81936fac6f81c7cfa3895838b381351a03e86a264ceb17dfbe09ff1d3e) |
| 32 | 48,305,438 | 19 Oct 03:06 | Agent | Buffer restore (withdraw from vault) | `withdrawFromVault` | OK · 72,980.88 | [`0x57fb3313…88992fa1`](https://base-sepolia.blockscout.com/tx/0x57fb3313e1ff6fc407c26a31bf1c2ca6c63e6519e2d3f02dde43eac888992fa1) |
| 33 | 48,305,532 | 19 Oct 03:09 | Owner | Founder emergency exit | `emergencyExit` | OK · 2,327,305.74 | [`0x82afc565…fec0f8c2`](https://base-sepolia.blockscout.com/tx/0x82afc5652cef4ed4112c811526c2867dfb5927af900a7dc0bd971090fec0f8c2) |
| 34 | 48,305,616 | 19 Oct 03:12 | Agent | Payroll attempt: out of gas, all-or-nothing batch paid nobody; completed by the payroll below | `payBatch` | Reverted · out of gas, nothing paid; retried in tx 39 | [`0x1e86a180…63ecec7d`](https://base-sepolia.blockscout.com/tx/0x1e86a18078d016126fd9c7510c9385cb1d92b23589cfc8c81177ecfe63ecec7d) |
| 35 | 48,305,619 | 19 Oct 03:12 | Agent | Vault sweep | `depositToVault` | OK · 2,111,582.45 | [`0xcda055b4…2663c85f`](https://base-sepolia.blockscout.com/tx/0xcda055b4fa0c1f12f0d61b862471cd010199c2579d9be365216fa2da2663c85f) |
| 36 | 48,305,662 | 19 Oct 03:13 | Agent | Tier 2: agent parks a 45,000 invoice as request #1 (no funds move) | `requestPayment` | OK · 45,000.00 held as request #1 | [`0xd3cfdc1a…9bab2cc5`](https://base-sepolia.blockscout.com/tx/0xd3cfdc1a70f5d3a23f4916614fdacb23c9dda47a07ba2d83f5503ceb9bab2cc5) |
| 37 | 48,305,688 | 19 Oct 03:14 | Owner | Attack: founder approves a request ID that does not exist | `approvePayment` | Reverted · PaymentNotFound | [`0xbf118841…d0ecd56e`](https://base-sepolia.blockscout.com/tx/0xbf118841e9f38fc539fca45e2f015b1c46f4b21cfd76164503537da2d0ecd56e) |
| 38 | 48,307,058 | 19 Oct 04:00 | Owner | Tier 2: founder approves request #1; 45,000 paid | `approvePayment` | OK · 45,000.00 | [`0xafaa6a3f…7c2c3b53`](https://base-sepolia.blockscout.com/tx/0xafaa6a3f4e55f70f7940bf9390370c58262219c18d3557436ce20a8b7c2c3b53) |
| 39 | 48,307,402 | 19 Oct 04:11 | Agent | Payroll: 60 employees in one transaction | `payBatch` | OK · 481,000.00 in 60 transfers | [`0x96769ae5…74c76b30`](https://base-sepolia.blockscout.com/tx/0x96769ae5ec3313f105c30f4b56f59db6a57bff7db51a5cf9b9be69da74c76b30) |
| 40 | 48,322,955 | 19 Oct 12:49 | Agent | Autonomous emergency exit (simulated depeg, run 1) | `emergencyExit` | OK · 2,111,698.52 | [`0x08d39421…255380a7`](https://base-sepolia.blockscout.com/tx/0x08d39421a0dc65a6ef9552e6df0cc79b70960f3f289ce9ac51a05d3b255380a7) |
| 41 | 48,323,592 | 19 Oct 13:11 | Agent | Vault sweep | `depositToVault` | OK · 1,796,052.09 | [`0xe1ebaf4f…9b4c26f2`](https://base-sepolia.blockscout.com/tx/0xe1ebaf4fc14a881142cb5712dac0f9ec08a72aa54a0b4e92c64787d09b4c26f2) |
| 42 | 48,323,978 | 19 Oct 13:24 | Agent | Autonomous emergency exit (simulated depeg, run 2) | `emergencyExit` | OK · 1,796,054.29 | [`0x3f5a8089…b6a97315`](https://base-sepolia.blockscout.com/tx/0x3f5a8089643c5ec09ddeefe8d940520bfba16fe95f8716cb7089981ab6a97315) |
| 43 | 48,330,177 | 19 Oct 16:50 | Owner | Founder stores the final policy fingerprint (matches policy.json) | `setPolicyHash` | OK · 0x9178d81f…3def193481 | [`0x7b532a1d…a92d29d4`](https://base-sepolia.blockscout.com/tx/0x7b532a1d5f0fcbf6ade62c2b21960dd2535eaed3c9ce1a411d530ceda92d29d4) |

## Custom errors seen above

| Error | Selector |
|---|---|
| NotAgent | `0x0d9ab13f` |
| PayeeNotAllowed | `0xa0a30653` |
| ExceedsPerPaymentCap | `0x81898631` |
| PaymentNotFound | `0xbefcc57b` |
