# BTEN v18 scope

Target: mainnet package after live v17 (`0x7239537d…8b3e`).

## Live-tape rule (product, locked)

- **Do not block transactions.**
- Everything shown on the https://block10.grok.me live tape is treated as **gated**
  (`RouteRecorded`, `ExternalCetusRouteAttested`, or equivalent).
- Ungated Cetus/aggregator volume that hits registered BTEN pools is **auto-attested**
  so it counts as gated (one receipt per digest), not rejected.

Shared configs the dapp already reads (`config/block10_integration.json`,
`MAINNET_ROUTE_CONFIG.json`, `config/managed_rebalance_policy.json`,
`config/external_route_providers.json`) carry `treatAllLiveTapeAsGated: true`
and `blockTransactions: false`.

## Managed vaults (user-facing on block10.grok.me)

Users on **https://block10.grok.me**:
1. Connect wallet and **import any Cetus LP Position** (any pool/pair).
2. Set **parameters**: max deviation bps, slippage bps, recenter, allow OOR close (+ cost basis for fee accounting).
3. **Add / remove anytime** (`enroll_cetus_position` / `withdraw_enrolled_position`), or settle exit after a close with **2% fee on realized profit** above basis.
4. Update parameters anytime via `update_enrollment_params` without withdrawing.

BTEN operator rebalances enrolled positions using those params; fee goes to ops wallets only.
ManagedVault Move source is already on main at `3cabeb7` — deploy with this upgrade.

## Also in v18

- `register_additional_pool` for Turbos/Bluefin/Haedal (and new Cetus pairs) after finalize.
- Magma/Bluefin **native** CLMM adapters are **not** invented here (no vendor interfaces in-repo);
  see `config/magma_bluefin_adapter_plan.json`. Magma BTEN legs on Cetus stay attestation-gated.
- Keeper script fixes for attestation digest key normalization + live package event types.

## Not blocking UX

- Full operator daemon extension for enrolled positions can ship after vault object is live.
- Managed-vault UI on the dapp reads `config/managed_rebalance_policy.json` + entrypoints from `block10_integration.json`.
