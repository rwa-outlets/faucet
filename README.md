# RWA Outlets — Faucet

Test-token faucet for the Base Sepolia demo, live at **faucet.rwaoutlet.club**.

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
[Base Sepolia gas faucet](https://docs.base.org/base-chain/tools/network-faucets), and the
recipient field lets any funded wallet (e.g. a teammate) drip to a fresh address.

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
