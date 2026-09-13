# BTEN v22 upgrade dry-run

## Fix

`auto_pay_trader` payout uses u128 intermediate; guard `total_points > 0`.

## Checklist

- [x] `sui move build`
- [x] `sui move test` (17/17 pass, including `auto_pay_trader_u128_avoids_u64_overflow`)
- [x] `sui client upgrade --dry-run` as ops `0x58189b…334d0a`
- [x] artifacts/v22/upgrade_dry_run_raw.txt

## Results

- Status: **Success**
- Simulated package id: `0x0588f0d4af5fc3502c560718003d589d8c2ce3a5f18e2c61cf58218c0d7af737` (version 22)
- Policy: Compatible (0) — UpgradeCap remains upgradeable
- Estimated storage-dominated gas: ~0.241 SUI
