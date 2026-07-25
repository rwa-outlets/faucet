import {
  createPublicClient,
  createWalletClient,
  custom,
  defineChain,
  erc20Abi,
  formatUnits,
  http,
  type Address,
  type Chain,
  type Hex,
} from "viem";
import type { FaucetConfig } from "./config";

export const faucetAbi = [
  { type: "function", name: "drip", stateMutability: "nonpayable", inputs: [], outputs: [] },
  {
    type: "function",
    name: "dripTo",
    stateMutability: "nonpayable",
    inputs: [{ name: "to", type: "address" }],
    outputs: [],
  },
  {
    type: "function",
    name: "allTokens",
    stateMutability: "view",
    inputs: [],
    outputs: [
      {
        type: "tuple[]",
        components: [
          { name: "token", type: "address" },
          { name: "amount", type: "uint256" },
        ],
      },
    ],
  },
  {
    type: "function",
    name: "nextClaimAt",
    stateMutability: "view",
    inputs: [{ name: "to", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  { type: "function", name: "cooldown", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

export interface TokenInfo {
  address: Address;
  symbol: string;
  amount: string; // human units per claim
}

export function toChain(cfg: FaucetConfig): Chain {
  return defineChain({
    id: cfg.chainId,
    name: cfg.chainName,
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [cfg.rpcUrl] } },
    blockExplorers: { default: { name: "Explorer", url: cfg.explorerUrl } },
  });
}

export function publicClient(cfg: FaucetConfig) {
  return createPublicClient({ chain: toChain(cfg), transport: http(cfg.rpcUrl) });
}

/** Reads the faucet's token list and resolves each token's symbol/decimals onchain. */
export async function fetchTokens(cfg: FaucetConfig): Promise<TokenInfo[]> {
  if (!cfg.faucetAddress) return [];
  const client = publicClient(cfg);
  const raw = await client.readContract({
    address: cfg.faucetAddress,
    abi: faucetAbi,
    functionName: "allTokens",
  });
  return Promise.all(
    raw.map(async (t) => {
      const [symbol, decimals] = await Promise.all([
        client.readContract({ address: t.token, abi: erc20Abi, functionName: "symbol" }),
        client.readContract({ address: t.token, abi: erc20Abi, functionName: "decimals" }),
      ]);
      return { address: t.token, symbol, amount: formatUnits(t.amount, decimals) };
    }),
  );
}

export async function fetchNextClaimAt(cfg: FaucetConfig, who: Address): Promise<bigint> {
  if (!cfg.faucetAddress) return 0n;
  return publicClient(cfg).readContract({
    address: cfg.faucetAddress,
    abi: faucetAbi,
    functionName: "nextClaimAt",
    args: [who],
  });
}

// ---------------------------------------------------------------- wallet

type Eip1193 = { request: (args: { method: string; params?: unknown[] }) => Promise<unknown> };

declare global {
  interface Window {
    ethereum?: Eip1193;
  }
}

export function hasWallet(): boolean {
  return typeof window !== "undefined" && !!window.ethereum;
}

export async function connectWallet(cfg: FaucetConfig): Promise<Address> {
  const eth = window.ethereum;
  if (!eth) throw new Error("No wallet found — install MetaMask (or use the address field).");
  const accounts = (await eth.request({ method: "eth_requestAccounts" })) as Address[];
  await ensureChain(cfg, eth);
  return accounts[0];
}

async function ensureChain(cfg: FaucetConfig, eth: Eip1193): Promise<void> {
  const hexId = `0x${cfg.chainId.toString(16)}`;
  try {
    await eth.request({ method: "wallet_switchEthereumChain", params: [{ chainId: hexId }] });
  } catch {
    // unknown chain (4902) — offer to add it, then switch
    await eth.request({
      method: "wallet_addEthereumChain",
      params: [
        {
          chainId: hexId,
          chainName: cfg.chainName,
          rpcUrls: [cfg.rpcUrl],
          nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
          blockExplorerUrls: [cfg.explorerUrl],
        },
      ],
    });
    await eth.request({ method: "wallet_switchEthereumChain", params: [{ chainId: hexId }] });
  }
}

/** Sends drip() (self) or dripTo(target) and waits for inclusion. Returns the tx hash. */
export async function sendDrip(cfg: FaucetConfig, account: Address, target: Address): Promise<Hex> {
  if (!cfg.faucetAddress) throw new Error("Faucet contract not configured");
  const eth = window.ethereum;
  if (!eth) throw new Error("No wallet found");
  await ensureChain(cfg, eth);
  const wallet = createWalletClient({ chain: toChain(cfg), transport: custom(eth) });
  const self = account.toLowerCase() === target.toLowerCase();
  const hash = await wallet.writeContract({
    address: cfg.faucetAddress,
    abi: faucetAbi,
    functionName: self ? "drip" : "dripTo",
    args: self ? [] : [target],
    account,
    chain: toChain(cfg),
  } as never);
  await publicClient(cfg).waitForTransactionReceipt({ hash });
  return hash;
}
