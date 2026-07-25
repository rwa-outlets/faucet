import { useEffect, useMemo, useState } from "react";
import { isAddress, type Address, type Hex } from "viem";
import { loadConfig, type FaucetConfig } from "./config";
import {
  connectWallet,
  fetchNextClaimAt,
  fetchTokens,
  hasWallet,
  sendDrip,
  type TokenInfo,
} from "./faucet";

type Status =
  | { kind: "idle" }
  | { kind: "busy"; message: string }
  | { kind: "done"; hash: Hex }
  | { kind: "error"; message: string };

export default function App() {
  const [config, setConfig] = useState<FaucetConfig | null>(null);
  const [configError, setConfigError] = useState<string | null>(null);
  const [tokens, setTokens] = useState<TokenInfo[]>([]);
  const [account, setAccount] = useState<Address | null>(null);
  const [target, setTarget] = useState("");
  const [nextClaimAt, setNextClaimAt] = useState<bigint | null>(null);
  const [status, setStatus] = useState<Status>({ kind: "idle" });

  useEffect(() => {
    loadConfig()
      .then((cfg) => {
        setConfig(cfg);
        return fetchTokens(cfg).then(setTokens);
      })
      .catch((e: unknown) => setConfigError(e instanceof Error ? e.message : String(e)));
  }, []);

  const targetAddress: Address | null = useMemo(() => {
    const t = target.trim();
    if (t && isAddress(t)) return t;
    if (!t && account) return account;
    return null;
  }, [target, account]);

  useEffect(() => {
    if (!config || !targetAddress) {
      setNextClaimAt(null);
      return;
    }
    fetchNextClaimAt(config, targetAddress)
      .then(setNextClaimAt)
      .catch(() => setNextClaimAt(null));
  }, [config, targetAddress, status]);

  const cooldownActive =
    nextClaimAt !== null && nextClaimAt > BigInt(Math.floor(Date.now() / 1000));

  async function onConnect() {
    if (!config) return;
    try {
      setStatus({ kind: "busy", message: "Connecting wallet…" });
      setAccount(await connectWallet(config));
      setStatus({ kind: "idle" });
    } catch (e) {
      setStatus({ kind: "error", message: e instanceof Error ? e.message : String(e) });
    }
  }

  async function onDrip() {
    if (!config || !account || !targetAddress) return;
    try {
      setStatus({ kind: "busy", message: "Confirm in your wallet, then waiting for inclusion…" });
      const hash = await sendDrip(config, account, targetAddress);
      setStatus({ kind: "done", hash });
    } catch (e) {
      const raw = e instanceof Error ? e.message : String(e);
      const message = raw.includes("CooldownActive")
        ? "Cooldown active for this address — try again later."
        : raw.split("\n")[0];
      setStatus({ kind: "error", message });
    }
  }

  if (configError) return <main className="card">Failed to load config.json: {configError}</main>;
  if (!config) return <main className="card">Loading…</main>;

  const notDeployed = !config.faucetAddress;

  return (
    <main className="card">
      <h1>RWA Outlets faucet</h1>
      <p className="sub">
        Demo tokens for {config.chainName}. Claims are fully onchain — the page has no backend.
      </p>

      {notDeployed ? (
        <div className="banner">
          Faucet contract not deployed yet — set <code>faucetAddress</code> in{" "}
          <code>config.json</code> once <code>contracts/Faucet.sol</code> is live.
        </div>
      ) : (
        <>
          <section>
            <h2>Each claim mints</h2>
            {tokens.length === 0 ? (
              <p className="dim">No tokens configured on the faucet contract yet.</p>
            ) : (
              <ul className="tokens">
                {tokens.map((t) => (
                  <li key={t.address}>
                    <span className="amount">{t.amount}</span> {t.symbol}
                    <a
                      className="dim mono"
                      href={`${config.explorerUrl}/token/${t.address}`}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {t.address.slice(0, 8)}…
                    </a>
                  </li>
                ))}
              </ul>
            )}
            <p className="dim">
              Plus the ComplianceNFT KYC pass and a native gas top-up when configured.
            </p>
          </section>

          <section>
            {account ? (
              <p className="mono">
                Connected: {account.slice(0, 6)}…{account.slice(-4)}
              </p>
            ) : (
              <button onClick={onConnect} disabled={!hasWallet()}>
                {hasWallet() ? "Connect wallet" : "No wallet detected"}
              </button>
            )}

            <label>
              Recipient (optional — defaults to the connected wallet; use this to fund a fresh
              wallet with no gas)
              <input
                placeholder="0x…"
                value={target}
                onChange={(e) => setTarget(e.target.value)}
                spellCheck={false}
              />
            </label>

            <button
              className="primary"
              onClick={onDrip}
              disabled={!account || !targetAddress || cooldownActive || status.kind === "busy"}
            >
              {cooldownActive ? "Cooldown active" : "Drip"}
            </button>

            {cooldownActive && nextClaimAt !== null && (
              <p className="dim">
                This address can claim again at{" "}
                {new Date(Number(nextClaimAt) * 1000).toLocaleString()}.
              </p>
            )}
          </section>

          {status.kind === "busy" && <p className="dim">{status.message}</p>}
          {status.kind === "done" && (
            <p className="ok">
              Dripped!{" "}
              <a href={`${config.explorerUrl}/tx/${status.hash}`} target="_blank" rel="noreferrer">
                View transaction
              </a>
            </p>
          )}
          {status.kind === "error" && <p className="err">{status.message}</p>}
        </>
      )}

      <footer>
        <p className="dim">
          Need gas first? Calling <code>drip()</code> costs a little ETH —{" "}
          <a href={config.gasFaucetUrl} target="_blank" rel="noreferrer">
            get {config.chainName} ETH here
          </a>
          , or ask someone funded to use the recipient field for you.
        </p>
      </footer>
    </main>
  );
}
