# BTEN v19 upgrade dry-run

## Emission-gate note

**Gated means emission-block release** (`batch_trades` / `settle` unlock of
`pending_blocks`). Live-tape labeling is not the gate.

## Checklist

- [x] `sui move build`
- [x] `sui move test` (14/14 pass)
- [x] JS policy tests pass
- [x] `sui client upgrade --dry-run` as ops `0x58189b…334d0a`
- [x] artifacts/v19/upgrade_dry_run_raw.txt
- [x] artifacts/v19/dry_run_summary.json

## Results

- Status: **Success**
- Simulated package id: `0x62e4ab323bfafe98121ba31fe89acd2039a3cb8e71166c61c89a0ec690272612` (version 19)
- Estimated gas: **240940740 MIST** (~0.240941 SUI)
- Policy: Compatible (0) — UpgradeCap remains upgradeable
- MIN_TRADES_PER_BLOCK: 1
