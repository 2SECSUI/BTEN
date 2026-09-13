# BTEN vault → LP / destinations release (2026-09-13)

Ops wallet: `0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a`
Package v21: `0xf036a39e2c97ba69b4610788d64319e8343248ff972d70273c9b735d24265896`
UpgradeCap `0x97744b65…` policy **0 (compatible)** — still upgradeable.

## Interpretation
“Other bots” = venue/destination vaults (cetus/haedal/blue/magma/turbos/sui_gas/staking/trader), not teammate agents.

## BEFORE → AFTER (approx)
| Bucket | Before | After | Path |
|---|---:|---:|---|
| LP `protocol_liquidity` | 5885 BTEN | **0** | OOR Cetus POL by weights |
| Venue vaults (lp/cetus/haedal/blue/magma/sui_gas) | 0 | **0** | Already accrued; cannot enable direct destinations (redirected) |
| Staking vault | 20 BTEN | **20 BTEN** | Intentional leftover from 0-stake heights; farm sync cannot claim |
| Farm `reward_vault` | ~1434 BTEN | live (users claimable) | Synced through height 343 |
| Trader vault | ~1666 BTEN | ~1140 BTEN | Paid 17 sealed-round entries; 1 overflow-blocked + dust left |
| Route fee vault | ~7680 BTEN | ~7730 BTEN | Accounting only (sponsor/pol/rebate/safety); not LP deploy |

## Actions executed
1. Snapshot balances; confirmed LP programme unpaused; venue destinations **cannot** be unpaused (`configure_distribution_destination` asserts staking-only).
2. Gas top-up: swapped 8 BTEN → ~2.22 SUI (`51JiXJG3odnVYL8GZuA9fbFZDutveQ7Ee9kkfDJWEdZU`).
3. Deployed ~5885 BTEN POL in 60 PTB batches (≤50 BTEN/call) across 10 Cetus pools — digests in `digests.txt`.
4. Settled pending blocks + `accrue_lp_program` / farm sync / treasury sync; redeployed subsequent 15+15 BTEN accruals.
5. `auto_pay_trader_entry` for 17 overflow-safe sealed point entries (17/17 success).

## Still blocked / remaining
- **Non-staking distribution destinations**: permanently redirected to LP programme; `distribute_released_blocks` no-ops for them by design.
- **Staking vault 20 BTEN**: leftover from heights with `total_staked==0`; stays until governance/admin path.
- **Trader**: ops round-1 points `125983599233` blocked by on-chain `points * reward_total` **u64 overflow** in `auto_pay_trader` (needs Move fix). Three dust `points=1` entries pay 0.
- **Route reserve / trader residual / farm rewards**: not “stuck venues”; route is treasury accounting; farm rewards are for stakers; trader residual needs overflow fix + future rounds.
- Keeper GitHub key not in env; permissionless settle/sync done via ops instead.

## Key digests
- Gas swap: `51JiXJG3odnVYL8GZuA9fbFZDutveQ7Ee9kkfDJWEdZU`
- POL batches: see `digests.txt` (60) + remainders `C4mfM9zM7usE5Z5rj4XEihFGw7iCBdJSgSwtxpT15DdS`, `8fcZUbV3yQefNrjBAW3RYCNL1MJbsnV3g5Eaee6mwfwH`
- Settle: `EZnkJJvE4n3RxduGX18Y1PHfH5goHc1eEU26TFbDGVTb`, `B8GKZfGA9oUDyi66jkSzy3bnUFZADatDCba4oaQEZVv3`
