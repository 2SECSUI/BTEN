# BTEN v23 upgrade dry-run

## Scope

OpsBuyDesk module (`bten::ops_buy_desk`) — Cetus mid pricing, discountBps=0.

## Checklist

- [x] `sui move build` (CLI 1.79 has no `--dependencies-are-root` on build; used plain build per V9 note)
- [x] `sui move test` (22/22 pass, including ops_buy_desk tests)
- [x] `sui client upgrade --dry-run` as ops `0x58189b…334d0a`
- [x] artifacts/v23/upgrade_dry_run_raw.txt

## Results

- Status: **Success**
- Simulated package id: `0x19737dcd3fabfc75d7d12c3037acf7337a1226ec05c82623edb8c439dc6113f8` (version 23)
- Modules: bten, ops_buy_desk
- Policy: Compatible (0) — UpgradeCap remains upgradeable
- Estimated gas: ~0.273 SUI
