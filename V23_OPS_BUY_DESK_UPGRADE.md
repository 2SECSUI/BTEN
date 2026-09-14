# BTEN v23 — OpsBuyDesk (code ready; do not auto-execute live)

## Scope

- New module `bten::ops_buy_desk`: shared inventory desk selling BTEN for SUI at **Cetus BTEN/SUI pool mid** (pool `0x7f46bd…2950`).
- **No −2% discount** (`discountBps = 0`).
- Events, pause, `min_bten_out` slippage, unit tests, keeper sync script, Block10 configs + docs.
- Public Cetus/Turbos swap adapters unchanged (already live on v22).

## Not in this upgrade

- Live mainnet upgrade execution (ops runs Compatible upgrade when ready)
- Destroy / `make_immutable` UpgradeCap — **forbidden**; keep `0x97744b65d7241a102c68016bc568eab7552e1d72a1a0583a054b9dff51b2c10c`
- Stopping incentive bots
- Embedding private keys

## Pre-upgrade checklist

- [ ] `sui move build --dependencies-are-root`
- [ ] `sui move test --dependencies-are-root`
- [ ] `sui client upgrade --dry-run` as ops `0x58189b…334d0a` with UpgradeCap above, policy Compatible (0)
- [ ] Confirm UpgradeCap remains upgradeable after dry-run

## Post-upgrade ops steps (Michael)

1. Update `Published.toml`, `config/ops_buy_desk.json#packageId`, `config/block10_integration.json` package fields to new v23 package id.
2. Create desk: `ops_buy_desk::create` (RegistryAdminCap) → record `deskObjectId` / `adminCapId`.
3. `deposit_bten` inventory.
4. Run / schedule `scripts/ops_buy_desk_sync_price.mjs --execute` (posted-price path + UI quotes). Prefer dapp `buy_with_sui` (in-tx mid) for fills.
5. Republish Grok App Builder Swap/Buy UI for block10.grok.me (may 404 until republish). Follow `publicSwap.grokAppBuilderChecklist` in `config/block10_integration.json`.

## Pricing reminder

Posted and in-tx prices must track Cetus mid only. Do not apply −2% or any other desk discount.
