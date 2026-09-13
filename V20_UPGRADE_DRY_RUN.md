# BTEN v20 upgrade dry-run

## Product rule

1. Catch-up backlog: `settle` releases `min(pending_blocks, MAX_SETTLE_BLOCKS)`
   with **no trade bar**.
2. Steady-state: `advance_slots` / `BLOCK_TIME_SECS` (600s) creates new pending
   slots once the backlog is drained.

## Checklist

- [x] `sui move build`
- [x] `sui move test` (15/15 pass, including `pending_slots_release_without_trades`)
- [x] `sui client upgrade --dry-run` as ops `0x58189b…334d0a`
- [x] artifacts/v20/upgrade_dry_run_raw.txt

## Results

- Status: **Success**
- Simulated package id: `0x13ed194be6326140970824ee08f5e527c5e1864125a73d54c2f7ecd22b4d862d` (version 20)
- Policy: Compatible (0) — UpgradeCap remains upgradeable
