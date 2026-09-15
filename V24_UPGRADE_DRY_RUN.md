# BTEN v24 upgrade dry-run

## Scope

Restore v16 emission rules (`MIN_TRADES_PER_BLOCK=10`, `MAX_SETTLE_BLOCKS=100`,
trade-gated settle). Keep ManagedVault, OpsBuyDesk, auto_pay u128, external attest.
Compatible UpgradeCap retained.

## Checklist

- [x] `sui move build`
- [x] `sui move test` (22/22 pass)
- [x] `sui client upgrade --dry-run` as ops `0x58189b…334d0a`
- [x] artifacts/v24/upgrade_dry_run_raw.txt

## Results

- Status: **Success**
- Simulated package id: `0x7a433ffbb5abc63839c5423ae937e45b44d0d4256917e692768dd425d8630927` (version 24)
- Modules: bten, ops_buy_desk
- Policy: Compatible (0) — UpgradeCap remains upgradeable
- Estimated gas: ~0.273 SUI (273149740 MIST)
