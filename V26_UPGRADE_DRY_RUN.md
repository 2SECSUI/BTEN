# BTEN v26 upgrade dry-run

## Checklist

- [x] `sui move build`
- [x] `sui move test` (23/23 pass)
- [x] `sui client upgrade --dry-run` as ops
- [x] artifacts/v26/upgrade_dry_run_raw.txt

## Results

- Status: **Success**
- Simulated package id: `0x4ee431e80b0e5512943be31b54afaa2df28992f79a6276629b46716b2903681b` (version 26)
- Modules: bten, ops_buy_desk
- Policy: Compatible (0)
- Estimated gas: ~0.283 SUI (282576140 MIST)
- New API: `cetus_swap_registered_a2b` / `b2a` (+ composable `*_return`)
