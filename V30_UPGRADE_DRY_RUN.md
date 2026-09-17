# BTEN v30 upgrade dry-run

- [x] `sui move build` — OK (2026-09-17 UTC+1 / Europe/London)
- [x] `sui move test` — **35/35 PASS** (2026-09-17 UTC+1)
- [x] `sui client upgrade --dry-run` as ops — **success** (no live publish)
- [x] Compatible policy retained (UpgradeCap mutated, not destroyed / not immutable)
- Simulated modules `bten`, `ops_buy_desk` **version 30**
- Simulated PackageID (dry-run only; live id will differ): `0x05a47de01d56a1d39b88ddcd9c9cfa07a1b44322e5a77ce8ea91dbe306e294d8`
- Estimated gas ~0.336 SUI (`336461340` MIST)

## Package IDs (current mainnet — still v29 until Michael OK)

| Item | ID |
|------|-----|
| Original package | `0x31c6c71184b08a574bd62fa8edd9a75aab9a986427484cf765a1890ce00aece0` |
| Published-at (v29 live) | `0x8f4ee2f47e61dd1f6657492020934e3fc06bec36da782c4ba02c5fd17ab37ca5` |
| UpgradeCap | `0x97744b65d7241a102c68016bc568eab7552e1d72a1a0583a054b9dff51b2c10c` |
| UpgradeCap owner (ops) | `0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a` |
| Policy | Compatible (0) — **keep** |
| Ops fee recipient | `0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a` |

## Dry-run command used

```bash
cd /workspace/BTEN-work
sui client upgrade --dry-run \
  --upgrade-capability 0x97744b65d7241a102c68016bc568eab7552e1d72a1a0583a054b9dff51b2c10c \
  --silence-warnings
```

Raw log: `artifacts/v30/upgrade_dry_run_raw.txt`

## Post-upgrade (after Michael live OK — not done)

1. `create_ops_interaction_fee_config` → record shared object id
2. Migrate Bandbot / Block10 PTBs to `*_ops_fee` + 0.5 SUI fee coin
3. Update `Published.toml` / configs to new v30 package id
4. Confirm UpgradeCap still Compatible

## Live publish

**DONE** live after Michael OK + ops waive. See `V30_UPGRADE_RESULT.md`.
