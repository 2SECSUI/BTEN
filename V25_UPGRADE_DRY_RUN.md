# BTEN v25 upgrade dry-run

## Checklist

- [x] `sui move build`
- [x] `sui move test` (22/22 pass)
- [x] `sui client upgrade --dry-run` as ops
- [x] artifacts/v25/upgrade_dry_run_raw.txt

## Results

- Status: **Success**
- Simulated package id: `0xab110cd3ade91dbfb3b20ce5e2f5c55abddb8f0fda95cf856d6590c8bdfece1a` (version 25)
- Modules: bten, ops_buy_desk
- Policy: Compatible (0)
- Estimated gas: ~0.274 SUI (273689340 MIST)
- New API: `bten::unregister_pool`
