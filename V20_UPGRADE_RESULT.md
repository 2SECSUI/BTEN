# BTEN v20 upgrade — EXECUTED

## Result

- **Status:** success
- **Tx:** 4aRdUQqshwnmU1c7shC84Foq8pmska6zzYWcR4QfUv4s
- **New package (v20):** 0xc21ce53ebc5509aca282d42f4a3a6b950a051e6b39eccb114c9596cb25b124fc
- **Previous package (v19):** 0xd439e5d4bff20efb36c62722ca999a229fcbde019cf3ddea74f0b526409bed7e
- **v19 upgrade tx:** aZXWoQssttz7N6EQSwziYdyuQKh3642R61rXYLxjXsB
- **UpgradeCap:** 0x97744b65d7241a102c68016bc568eab7552e1d72a1a0583a054b9dff51b2c10c
- **UpgradeCap owner:** 0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a
- **UpgradeCap policy:** Compatible (0) — **still upgradeable**
- **UpgradeCap package version field:** 20
- **Gas:** ~0.2397 SUI
- **No** `make_immutable` / `destroy`. authorize_upgrade used policy `0`.

## Emission rule shipped

- Catch-up: `min(pending_blocks, MAX_SETTLE_BLOCKS)` with no `batch_trades` requirement
- Steady-state: `advance_slots` still paces new slots at 600s
- Trades/attestations accrue trader points only

## Settle catch-up (ops, permissionless)

| tx | blocks | remaining_pending |
|---|---|---|
| J6swPJPPgjsrRaXP4w4oVwubvctjsCTYwgW4Z58if1pJ | 100 | 225 |
| 92jbBeDUNMHfwQfUMTN534NTKtQVpT8dC7JEz1ycbrvE | 100 | 125 |
| GhGir68TpeCxeq1VjL1ZHA9cH4XctkaWqWfQiAYKie2Q | 100 | 25 |
| s8XR4LxvvHzXdQFeS8cfstQ32UDmNcZictxxBtSko5q | 25 | 0 |

- block_height **16 → 341** (325 blocks)
- pending_blocks **319+elapsed → 0**
- total_minted **800 → 17,050 BTEN**

## Vault / destination movement

| action | tx | result |
|---|---|---|
| sync_route_treasury | 3Kso4Cx8mTSeTQekqviR6VbBbHjLgFNXwyMYmrej9C9X | 325 RouteTreasuryAccrued; next_height 341 |
| accrue_lp_program | 3oTqSnayWNpM1yXySCVnWcHTPbP1Aq8LcerwnYPFqyVq | 4,875 BTEN venue/LP vaults → LP programme |
| sync_bten_staking_farm_rewards | 3QC4PdUunKPY8EzSMcbnUtd3wmdBKkjot7hpdKHwr4Hn | 1,625 BTEN staking allocation → farm reward_vault |
| accrue_route_lp_support_to_program | 3CVDQMV2qBrTwALvFGGbsEQEHwmFd4ey6mBCML3anZAM | 845 BTEN route LP-support → LP programme |
| distribute_released_blocks | 3UJ5HjctRwAje4iZ7uwxXqQfXX4hirZxQN1cQaXdTKSj | no-op (paused non-staking destinations; already at 341) |

### Balances (raw, 8 decimals)

| field | before | after |
|---|---|---|
| route_fee_vault | 39,999,075,000 | 767,999,075,000 |
| trader_vault | 4,170,993,108 | 166,670,993,108 |
| staking_vault | 2,000,000,000 | 2,000,000,000 (historic pre-farm remainder) |
| LP/venue vaults | 0 | 0 (accrued out) |
| lp.protocol_liquidity | 16,500,000,000 | 588,500,000,000 |
| farm.reward_vault | 500,000,000 | 163,000,000,000 |
| treasury.next_height | 16 | 341 |
| farm.next_height | 16 | 341 |

Remaining route_fee_vault is the 50% route reserve (sponsor/POL/rebate/safety accounting). 
Trader vault pays via `auto_pay_trader_entry` to wallets with sealed-round points.
Distribution buckets other than staking remain paused by policy.
