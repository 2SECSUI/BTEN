# BTEN v18 upgrade dry-run

## Product note (ungated → gated)

Live tape on block10.grok.me treats **all shown trades as gated**. Ungated
Cetus/aggregator volume through registered BTEN pools (example digest
`8CzMG6mnfGMyWSNBER9FGmJMqwmDyLUoWDELnBUFkA7h`) is included via
`ExternalCetusRouteAttested` — not blocked. Configs use
`treatAllLiveTapeAsGated: true` / `blockTransactions: false`.

## Scope included in this dry-run candidate

- ManagedVault (already in tree)
- `register_additional_pool` post-finalize venue registration
- Attestation comment clarity (no signature breaks)
- No Magma/Bluefin Move swap deps (plan JSON only)
- Verifier digest-key normalization + live package event types

## Checklist

- [x] `sui move build`
- [x] `sui move test` (12/12 pass)
- [x] `sui client upgrade --dry-run` as ops `0x58189b…334d0a`
- [x] artifacts/v18/upgrade_dry_run_gated.txt
- [x] artifacts/v18/dry_run_summary.json
- [x] **Do not execute live upgrade**

## Results

- Status: **Success**
- Simulated package id: `0x269934d77c31c77c0b6ebadd68d0b8d9b2f1a5f5bac8cbc3ce4c8dbfe13a793f` (version 18)
- Estimated gas: **237664940 MIST** (~0.238 SUI)
- Magma/Bluefin native adapters: **not possible** (no vendor interfaces); see `config/magma_bluefin_adapter_plan.json`
- Verifier dry-run for `8CzMG6…`: candidate found (BTEN/SUI pool, one receipt per digest), no crash, no keys printed
