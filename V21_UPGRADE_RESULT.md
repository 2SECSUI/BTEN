# BTEN v21 upgrade — EXECUTED

## Result

- **Status:** success
- **Tx:** Hffs2p4ptgFpcGr5zW7JWpRj4NNXGgxQrgy3GJxgzL4N
- **New package (v21):** 0xf036a39e2c97ba69b4610788d64319e8343248ff972d70273c9b735d24265896
- **Previous package (v20):** 0xc21ce53ebc5509aca282d42f4a3a6b950a051e6b39eccb114c9596cb25b124fc
- **v20 upgrade tx:** 4aRdUQqshwnmU1c7shC84Foq8pmska6zzYWcR4QfUv4s
- **UpgradeCap:** 0x97744b65d7241a102c68016bc568eab7552e1d72a1a0583a054b9dff51b2c10c
- **UpgradeCap owner:** 0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a
- **UpgradeCap policy:** Compatible (0) — **still upgradeable**
- **UpgradeCap package version field:** 21
- **Gas:** ~0.2400 SUI
- **No** `make_immutable` / `destroy`. authorize_upgrade used policy `0`.

## Emission rule shipped (going forward)

- Bitcoin-style ~10-minute cadence
- `BLOCK_TIME_SECS = 600` — `advance_slots` creates pending only every 10 minutes
- `MAX_SETTLE_BLOCKS = 1` — each settle releases **at most one** block
- No bulk multi-block catch-up dumps (v20's ~100/settle catch-up was wrong for product)
- No trade bar — trades/attestations accrue points only
- Height **341** / minted supply **unchanged** (no rollback)

## On-chain confirmation

- `bten::max_settle_blocks()` dev-inspect → **1**
- UpgradeCap `policy: 0` (Compatible), `version: 21`, package points at v21 id
- EmissionState after upgrade: `block_height=341`, `pending_blocks=0`

## Keeper / configs

- `github_keeper.mjs` / `keeper_policy.json`: `maximumBlocksPerRun = 1`
- Docs/comments updated for Bitcoin-style cadence
