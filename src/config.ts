import type { Address } from "viem";

/** Runtime config, fetched from /config.json — edit that file (and rebuild the image)
 *  to point the page at a deployed Faucet contract. No VITE_* baking involved. */
export interface FaucetConfig {
  chainId: number;
  chainName: string;
  rpcUrl: string;
  explorerUrl: string;
  /** Deployed contracts/Faucet.sol address; empty string = not deployed yet. */
  faucetAddress: Address | "";
  /** Where users get native Base Sepolia ETH for gas (drip() needs a funded caller). */
  gasFaucetUrl: string;
}

export async function loadConfig(): Promise<FaucetConfig> {
  const res = await fetch("/config.json", { cache: "no-store" });
  if (!res.ok) throw new Error(`config.json: HTTP ${res.status}`);
  return (await res.json()) as FaucetConfig;
}
