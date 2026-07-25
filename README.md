# RWA Outlets — Faucet

Test-token faucet for the RWA Outlets demo, served at **faucet.rwaoutlet.club**. Currently
deployed on **Ethereum Sepolia** (see [Deployed](#deployed--ethereum-sepolia-11155111));
the chain is runtime config, so retargeting (e.g. Base Sepolia) is a config + redeploy of the
contract, not a code change.

Built to the infra repo's contract (`terraform/terraform/faucet_app.tf`): a **static site** —
nginx on port 80, health check `GET /` — with **no backend and no server-side signer**. All
dripping happens onchain through [`contracts/Faucet.sol`](contracts/Faucet.sol); the page is a
small Vite + React + viem dApp that calls it.

## How it works

```
user wallet ──drip()──▶ Faucet.sol ──mint()──▶ TestUSDC, rwaTBILL, rwaCREDIT
                        │
                        ├─ mints ComplianceNFT (KYC pass) when the wallet has none
                        └─ sends a small ETH gas stipend while the faucet holds ETH
```

- `drip()` — claim for yourself (per-address cooldown, default set at deploy).
- `dripTo(address)` — claim **for a fresh wallet with no gas** (cooldown is keyed on the
  recipient, so this can't be used to farm around it).
- The token list, amounts, cooldown, NFT, and gas stipend are all owner-configurable onchain —
  the page reads everything live from the contract, so config changes need no redeploy.

Gas chicken-and-egg: calling `drip()` itself costs a little ETH. The page links a
[gas faucet](https://faucets.chain.link/sepolia), and the recipient field lets any funded
wallet (e.g. a teammate) drip to a fresh address.

## Deployed — Ethereum Sepolia (11155111)

| Contract | Address | Per claim |
| --- | --- | --- |
| **Faucet** | [`0xE78E87D994358D17aaf4653d8398f22C93fb758A`](https://sepolia.etherscan.io/address/0xE78E87D994358D17aaf4653d8398f22C93fb758A) | — |
| TestUSDC (`USDC`, 6d) | [`0x062b2F19C852e486b4b913933420957018d1db31`](https://sepolia.etherscan.io/token/0x062b2F19C852e486b4b913933420957018d1db31) | 1,000 |
| RWA T-Bill (`rwaTBILL`, 18d) | [`0x5456E52531085291a35CF0d902aE72D6616b665D`](https://sepolia.etherscan.io/token/0x5456E52531085291a35CF0d902aE72D6616b665D) | 1,000 |
| RWA Credit (`rwaCREDIT`, 18d) | [`0xFbca2B3334138C109D51f5101343DE0A35a0eDD9`](https://sepolia.etherscan.io/token/0xFbca2B3334138C109D51f5101343DE0A35a0eDD9) | 1,000 |

- Params: 6 h cooldown per address, 0.002 ETH gas stipend per claim (paid while the faucet
  holds ETH). Owner/deployer: `0x8b7699EddbdE63f199c9629Ec8C88e3F704100f7`.
- Verified end-to-end with a live claim:
  [drip tx](https://sepolia.etherscan.io/tx/0x4a2aa88de12fb65bf28a100e7ef73c5ca010353e2a65c6d9b073ed47fd01b270)
  → 1,000 USDC minted, cooldown armed.
- These tokens are this repo's [`MintableERC20`](contracts/MintableERC20.sol) placeholders,
  **not** the protocol's demo assets from `rwa-outlet-contracts-core/deployments/11155111.json`
  — to dispense those instead, point the faucet at them with `setTokens(...)` (the faucet
  needs mint rights on them) and no page redeploy is required.
- [`public/config.json`](public/config.json) already points the page at this deployment.

## Local dev

```bash
npm install
npm run dev      # http://localhost:5173
npm run check    # tsc --noEmit
npm run build    # dist/
```

Configuration is runtime, not build-time: edit [`public/config.json`](public/config.json)
(chain, RPC, explorer, `faucetAddress`). An empty `faucetAddress` renders a "not deployed yet"
banner instead of a broken page.

## Deploying the contract

From any Foundry checkout (the contract is dependency-free):

```bash
forge create contracts/Faucet.sol:Faucet \
  --rpc-url $TESTNET_RPC_URL --private-key $DEPLOYER_KEY \
  --constructor-args 21600 2000000000000000        # 6 h cooldown, 0.002 ETH stipend

cast send $FAUCET "setTokens((address,uint256)[])" \
  "[($TEST_USDC,1000000000),($RWA_TBILL,1000000000000000000000),($RWA_CREDIT,1000000000000000000000)]" \
  --rpc-url $TESTNET_RPC_URL --private-key $DEPLOYER_KEY   # 1000 USDC (6d) + 1000 of each RWA (18d)

cast send $FAUCET "setComplianceNFT(address)" $COMPLIANCE_NFT ...   # optional
cast send $FAUCET --value 0.5ether ...                              # fund gas stipends
```

**Mint rights**: the demo tokens are owner-mintable, so either deploy them with the faucet as
owner, transfer ownership to it, or give them a minter role that includes the faucet. For the
ComplianceNFT the faucet must be an operator. Then put the faucet address in
`public/config.json` and ship the image.

## Shipping (per the infra repo README)

```bash
docker build --platform linux/amd64 \
  -t registry.digitalocean.com/rwa-outlets/faucet:main .
docker push registry.digitalocean.com/rwa-outlets/faucet:main
kubectl rollout restart deployment/faucet
```

DNS (`faucet.rwaoutlet.club`), TLS, ingress, and probes are already provisioned by
`terraform/terraform/faucet_app.tf` — pushing the image is the only deploy step.
