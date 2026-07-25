#!/usr/bin/env bash
# Deploys the Faucet (and, unless you point it at existing tokens, three placeholder demo
# tokens) to Base Sepolia, wires everything up, and writes the faucet address into
# public/config.json. Idempotent per run — every run deploys a fresh faucet.
#
# Usage:
#   PRIVATE_KEY=0x... ./script/deploy-sepolia.sh
#
# Environment:
#   PRIVATE_KEY       required — deployer key; becomes the faucet owner (testnet-only key!)
#   RPC_URL           default https://sepolia.base.org (Base Sepolia)
#   COOLDOWN          default 21600 (6 h between claims per address)
#   GAS_STIPEND_WEI   default 2000000000000000 (0.002 ETH per claim; only paid while funded)
#   FUND_ETH          optional — ETH to send the faucet for gas stipends, e.g. 0.1
#   TEST_USDC, RWA_TBILL, RWA_CREDIT
#                     optional — existing token addresses. When set, no placeholder tokens
#                     are deployed; you must grant the faucet mint rights on them yourself.
#   COMPLIANCE_NFT    optional — soulbound KYC pass; faucet must be an operator on it.
set -euo pipefail
cd "$(dirname "$0")/.."

RPC_URL=${RPC_URL:-https://sepolia.base.org}
COOLDOWN=${COOLDOWN:-21600}
GAS_STIPEND_WEI=${GAS_STIPEND_WEI:-2000000000000000}
: "${PRIVATE_KEY:?set PRIVATE_KEY (testnet deployer key)}"

# amounts per claim: 1,000 USDC (6d) and 1,000 of each RWA (18d)
USDC_AMOUNT=1000000000
RWA_AMOUNT=1000000000000000000000

# compile from contracts/ (this repo has no foundry.toml — it's a vite app)
export FOUNDRY_SRC=contracts FOUNDRY_OUT=out FOUNDRY_CACHE_PATH=cache

SEND=(cast send --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY")
DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY")
CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
echo "deployer: $DEPLOYER   chain: $CHAIN_ID   rpc: $RPC_URL"

deploy() { # deploy <Contract.sol:Name> [constructor args...]
  local target=$1
  shift
  local out
  # NB: --constructor-args is greedy (swallows every following token), so it must come last
  if (($#)); then
    out=$(forge create "contracts/$target" --broadcast --json --rpc-url "$RPC_URL" \
      --private-key "$PRIVATE_KEY" --constructor-args "$@" 2>/dev/null)
  else
    out=$(forge create "contracts/$target" --broadcast --json --rpc-url "$RPC_URL" \
      --private-key "$PRIVATE_KEY" 2>/dev/null)
  fi
  # stdout may carry compiler notes around the (multi-line) JSON — slice { ... } out
  python3 -c "
import json, sys
s = sys.stdin.read()
print(json.loads(s[s.index('{'):s.rindex('}') + 1])['deployedTo'])
" <<<"$out"
}

echo "── deploying Faucet (cooldown ${COOLDOWN}s, stipend ${GAS_STIPEND_WEI} wei)"
FAUCET=$(deploy "Faucet.sol:Faucet" "$COOLDOWN" "$GAS_STIPEND_WEI")
echo "   Faucet: $FAUCET"

if [[ -z "${TEST_USDC:-}" ]]; then
  echo "── deploying placeholder demo tokens (faucet gets a minter role)"
  TEST_USDC=$(deploy "MintableERC20.sol:MintableERC20" "Test USD Coin" "USDC" 6)
  RWA_TBILL=$(deploy "MintableERC20.sol:MintableERC20" "RWA T-Bill" "rwaTBILL" 18)
  RWA_CREDIT=$(deploy "MintableERC20.sol:MintableERC20" "RWA Credit" "rwaCREDIT" 18)
  for t in "$TEST_USDC" "$RWA_TBILL" "$RWA_CREDIT"; do
    "${SEND[@]}" "$t" "setMinter(address,bool)" "$FAUCET" true > /dev/null
  done
else
  : "${RWA_TBILL:?set RWA_TBILL when TEST_USDC is set}"
  : "${RWA_CREDIT:?set RWA_CREDIT when TEST_USDC is set}"
  echo "── using existing tokens (grant the faucet mint rights on them yourself!)"
fi
echo "   TEST_USDC:  $TEST_USDC"
echo "   RWA_TBILL:  $RWA_TBILL"
echo "   RWA_CREDIT: $RWA_CREDIT"

echo "── configuring claim amounts on the faucet"
"${SEND[@]}" "$FAUCET" "setTokens((address,uint256)[])" \
  "[($TEST_USDC,$USDC_AMOUNT),($RWA_TBILL,$RWA_AMOUNT),($RWA_CREDIT,$RWA_AMOUNT)]" > /dev/null

if [[ -n "${COMPLIANCE_NFT:-}" ]]; then
  echo "── wiring ComplianceNFT $COMPLIANCE_NFT (faucet must be an operator on it)"
  "${SEND[@]}" "$FAUCET" "setComplianceNFT(address)" "$COMPLIANCE_NFT" > /dev/null
fi

if [[ -n "${FUND_ETH:-}" ]]; then
  echo "── funding gas stipends with ${FUND_ETH} ETH"
  "${SEND[@]}" "$FAUCET" --value "${FUND_ETH}ether" > /dev/null
fi

echo "── smoke test: reading token list back"
cast call --rpc-url "$RPC_URL" "$FAUCET" "allTokens()((address,uint256)[])"

echo "── writing faucetAddress into public/config.json"
FAUCET=$FAUCET python3 - <<'EOF'
import json, os
path = "public/config.json"
cfg = json.load(open(path))
cfg["faucetAddress"] = os.environ["FAUCET"]
json.dump(cfg, open(path, "w"), indent=2)
open(path, "a").write("\n")
EOF

cat <<EOF

Done.
  Faucet:     $FAUCET
  TEST_USDC:  $TEST_USDC
  RWA_TBILL:  $RWA_TBILL
  RWA_CREDIT: $RWA_CREDIT
$([[ "$CHAIN_ID" == "84532" ]] && echo "  Explorer:   https://sepolia.basescan.org/address/$FAUCET")

Next steps:
  1. Commit the updated public/config.json.
  2. Record the addresses in the root README deployed-addresses table.
  3. Ship the page: docker build --platform linux/amd64 \\
       -t registry.digitalocean.com/rwa-outlets/faucet:main . && docker push ... \\
       && kubectl rollout restart deployment/faucet
EOF
