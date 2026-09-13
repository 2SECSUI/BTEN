# BTEN v21 upgrade dry-run

## Product rule

1. Bitcoin-style ~10 min cadence: `advance_slots` / `BLOCK_TIME_SECS` (600s)
   creates new pending slots.
2. Each `settle` releases **at most 1** block (`MAX_SETTLE_BLOCKS = 1`).
3. No bulk multi-block catch-up dumps. No trade bar.

## Checklist

- [x] `sui move build`
- [x] `sui move test` (16/16 pass, including `settle_releases_at_most_one_when_pending_large`)
- [x] `sui client upgrade --dry-run` as ops `0x58189b…334d0a`
- [x] artifacts/v21/upgrade_dry_run_raw.txt

## Results

- Status: **Success**
- Simulated package id: `0xc658c0ae7bad0aea5f0104c23a0705dbf3d5afbfefa3ae8c937d94fc32840547` (version 21)
- Policy: Compatible (0) — UpgradeCap remains upgradeable
- Estimated net gas: ~0.241 SUI
