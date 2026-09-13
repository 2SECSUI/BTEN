# BTEN v21 scope

Follow-on to live v20 (`0xc21ce53e…24fc`). Height 341 / minted supply stay.

## Product rule (locked)

**Bitcoin-style ~10-minute block cadence. One block about every 10 minutes.**

- `BLOCK_TIME_SECS = 600` unchanged — `advance_slots` creates a new pending slot only after 10 minutes.
- `MAX_SETTLE_BLOCKS = 1` — each `settle` / `settle_and_distribute` releases **at most one** block.
- No bulk multi-block catch-up dumps (v20's ~100-per-settle catch-up was wrong for this product).
- Trades / attestations still accrue trader points; they do **not** gate unlock.
- Cannot roll back height 341 — fix is going forward only.

## Keeper / configs

- `maximumBlocksPerRun = 1` / `MAX_SETTLE_BLOCKS = 1` in github_keeper and keeper_policy.

## Not in this upgrade

- `make_immutable` / destroying UpgradeCap. Package stays Compatible (0).
