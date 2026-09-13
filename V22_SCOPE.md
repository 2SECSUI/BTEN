# BTEN v22 scope

Follow-on to live v21 (`0xf036a39e…5896`).

## Bug

`auto_pay_trader` computed `points * reward_total / total_points` in u64.
Large fee_points × reward_total overflowed before division → MoveAbort (code 0)
on Block10 “Swap · auto-pay”, leaving BTEN stuck in `trader_vault`.

## Fix

1. u128 intermediate for payout math; guard `total_points > 0`; keep `amount > 0`.
2. Unit test `auto_pay_trader_u128_avoids_u64_overflow` (50e9 points × 500e6 reward).
3. Compatible upgrade only — **no** `make_immutable` / UpgradeCap destroy.

## Not in this upgrade

- Emission cadence / MAX_SETTLE_BLOCKS (stays 1)
- Height / supply rollback
