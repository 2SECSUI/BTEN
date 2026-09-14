# Block10 dapp UI fix (v22 — no 10-hop trade bar)

## Where the frontend lives

**Not in this repo.** Live site https://block10.grok.me is a **Grok App Builder** app:

| Field | Value |
| --- | --- |
| URL | https://block10.grok.me |
| Host | Vercel (`x-vercel-cache`) behind Cloudflare on `grok.me` |
| Grok project id | `01a0925b-5bff-7bf1-bd90-f229738f4f52` |
| Meta | `grok-project-id` / `grok:app_id` in page HTML |
| Extensions | `https://grok.com/grok-app-builder/extensions.js` |

Likely local checkout (Windows laptop): sibling of `Desktop\10MinMine\laptop` — look for **`bten-public`**, **`bten`**, **`ops`**, or any BlockTen / Vite / TanStack app that builds the same routes (`/earn`, `/bot`, `/guide`).

GitHub `2SECSUI/BTEN` only supplies **JSON configs** the dapp already fetches (cache-busted with `?t=Date.now()`):

- `config/block10_integration.json`
- `MAINNET_ROUTE_CONFIG.json`
- `config/keeper_policy.json`
- etc. via `raw.githubusercontent.com/2SECSUI/BTEN/main` and jsDelivr.

## Root cause

Stale **hardcoded `10`** in client bundles (not JSON):

| Bundle | Stale copy / logic |
| --- | --- |
| `assets/earn-*.js` | “Ten filled hops…”, “10-route gate”, `batchTrades>=10`, `Math.max(0,10-batchTrades)`, `/10` |
| `assets/guide-*.js` | “needs ten filled hops”, “Fill the gate to 10/10”, settle locked until gate full |
| `assets/index-*.js` | Header `Live 10-route gate`, `Gate N/10` |
| `assets/routes-*.js` | “N filled hops to release”, “Need 10 filled receipts…”, Gate `/10` |
| `assets/bot-*.js` | `Gate N/10`, status **`Armed`** even when wallet disconnected (`Armed` vs `Idle` / `Watching` without connect check) |

On-chain `min_trades_per_block()` still returns **1** (Move constant), but settle already unlocks on time slots with `MAX_SETTLE_BLOCKS=1` and does not require 10 trades. Configs say `minTradesPerBlock=0`. **Prefer UI ignore** of the view for any progress bar; Move v23 only if something still binds UI to that view.

## Required UI behavior (v22)

1. **No 10-hop / 10-route gate** — remove trade bar and `N/10` gate chrome.
2. Show **Bitcoin-style ~10 minute blocks**; settle when a **due pending slot** exists (`MAX_SETTLE_BLOCKS=1`).
3. Trades/attestations **accrue rewards**; they are **not** required to release.
4. Live tape: **treat all shown rows as gated** (label only).
5. Guide: explain time-slot settle, not “fill 10/10”.
6. Bot: if wallet disconnected → **not** “Armed” (use “Connect wallet” / “Idle”).

## Config keys already published (this repo)

After the companion commit, `block10_integration.json` includes:

- `cacheBust` / `configRevision` / `uiRevision`
- `dappUiPolicy` (`hopsRequired: 0`, `tradeBar: false`, `botArmedRequiresWallet: true`, …)
- `gatePolicy.hopsRequired: 0`, `emissionGate.tradeBar: false`

The **current** live JS does **not** read `minTradesPerBlock` / `hopsRequired` for the bar (literals are `10`). Updating JSON alone will **not** clear stale copy until the Grok app is rebuilt/republished. When editing the app, prefer driving the bar from `dappUiPolicy` / `gatePolicy.emissionGate` so this does not regress.

## Verify after publish

```bash
curl -sL https://block10.grok.me/earn | rg -i 'filled hop|10-route|Waiting fill|Gate .*/10'
curl -sL https://block10.grok.me/guide | rg -i '10/10|ten filled|fill the gate'
curl -sL https://block10.grok.me/bot  | rg -i 'Armed'
# Also grep hashed /assets/*.js for the same strings — must be gone.
```

Residual: wallet connect still required for live tx tests.
