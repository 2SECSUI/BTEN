# BTEN v20 scope

Follow-on to live v19 (`0xd439e5d4…ed7e`).

## Emission (product, locked)

**Block release is not trade-gated.**

- After `advance_slots`, `settle` releases `min(pending_blocks, MAX_SETTLE_BLOCKS)`.
- `batch_trades == 0` is fine. Quiet time still unlocks due slots.
- Trades / `attest_external_cetus_route` still accrue trader points for the
  sealed round; they do not gate unlock.
- Keeper eligibility is `pending > 0` after time advance, not `batch_trades / N`.

## Not in this upgrade

- `make_immutable` / destroying UpgradeCap. Package stays Compatible (0).
