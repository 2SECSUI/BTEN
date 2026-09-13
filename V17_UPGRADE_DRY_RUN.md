# BTEN v17 upgrade dry-run

Generated from local worktree on branch codex/v17-composable-routes @ 7f02d79.

## Result

- **Dry-run status:** success (not executed on-chain)
- **From:** package v16 0xc71c7ab810ba15ea337dc7722e8eaac4e3c7e631cf3557f70167783f1f3bcc41
- **To:** package v17 (simulated PackageID 0xda1dbc8a8cb35d6afdfb9ebe95458eb4e4d8fe47b4bcff2321931bdad6d2abe4)
- **UpgradeCap:** 0x97744b65d7241a102c68016bc568eab7552e1d72a1a0583a054b9dff51b2c10c owned by ops 0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a
- **Policy:** compatible
- **Estimated gas:** 208593340 MIST (~0.208593 SUI)
- **Package digest (hex):** 0x95a042e3d57e57387448f28d04a7178dec202ca5ec674273701426c061334ff9

## Preconditions checked

- [x] sui move build succeeds with Cetus + Turbos stubs
- [x] sui move test composable_route → 3/3 pass
- [x] UpgradeCap on ops wallet, version field 16
- [x] sui client upgrade --dry-run succeeds

## Execute for real (ops wallet only)

`ash
sui client switch --env mainnet
sui client active-address   # must be 0x58189b...334d0a
sui client upgrade --upgrade-capability 0x97744b65d7241a102c68016bc568eab7552e1d72a1a0583a054b9dff51b2c10c --gas-budget 500000000
`

After success:

1. Update Published.toml mainnet published-at + ersion = 17
2. Refresh config/block10_integration.json package pointers if any
3. Small mainnet proofs: single Cetus hop, composable seal, one Turbos hop (after pool registry)
4. Verification zip for explorers

## Artifacts

- rtifacts/v17/upgrade_dry_run.txt — full CLI dry-run output
- rtifacts/v17/upgrade_cap.json — on-chain UpgradeCap snapshot
- rtifacts/v17/package_dump.clean.json — modules/deps/digest dump
- rtifacts/v17/dry_run_summary.json — machine-readable summary

## Scope landed in this upgrade candidate

- Composable Cetus ticket + seal (one receipt)
- Turbos: 	urbos_swap_to_bten, 	urbos_swap_from_bten, *_b_first / *_a_first, composable *_return
- Block10 configs already on GitHub main
