# BTEN v22 upgrade — EXECUTED

## Result

- **Status:** success
- **Tx:** 37cfcJGcrNECdnmEHHdwN7jEuxGzsks9LAqBwkYL8bMf
- **New package (v22):** 0x636c670a9454013ae7ea96046279b75821b339146598b68661b9b06a26eb61f6
- **Previous package (v21):** 0xf036a39e2c97ba69b4610788d64319e8343248ff972d70273c9b735d24265896
- **UpgradeCap:** 0x97744b65d7241a102c68016bc568eab7552e1d72a1a0583a054b9dff51b2c10c
- **UpgradeCap owner:** 0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a
- **UpgradeCap policy:** Compatible (0) — **still upgradeable**
- **UpgradeCap package version field:** 22
- **Gas:** ~0.2402 SUI
- **No** `make_immutable` / `destroy`. authorize_upgrade used policy `0`.

## Bug fix shipped

`auto_pay_trader` payout math now uses a **u128 intermediate**:

```move
assert!(trader_round.total_points > 0, E_NOTHING_TO_PAY);
let amount = (
    ((points as u128) * (trader_round.reward_total as u128)
        / (trader_round.total_points as u128)) as u64
);
assert!(amount > 0, E_NOTHING_TO_PAY);
```

Previously `points * reward_total / total_points` in u64 overflowed (MoveAbort code 0) on Block10 “Swap · auto-pay” for large fee_points (e.g. round 1 ops).

Unit test: `auto_pay_trader_u128_avoids_u64_overflow` (17/17 tests pass).

## Autopay verification

| Round | Trader | Points | Result |
|------:|--------|-------:|--------|
| 1 | ops `0x58189b…334d0a` | 125983599233 | **Paid** `499761987` mist (~4.9976 BTEN). Tx `Ezto4r9LjFvDyBnA9GDXtQGiGwxxGjz2m4Z4fEjHFFAE`. Would overflow in u64. |
| 5 | `0x56a054…87a0` | 1 | **Still blocked** — truncates to amount 0 → abort code 7 (`E_NOTHING_TO_PAY`) |
| 7 | `0x56a054…87a0` | 1 | **Still blocked** — amount 0 / code 7 |
| 10 | `0x56a054…87a0` | 1 | **Still blocked** — amount 0 / code 7 |
| 21 | ops | ~4.139e9 | **Not sealed yet** (current open round; no `TraderRound` until settle) |

## Swap proof (gated Cetus SUI→BTEN)

- **Tx:** 5vSGbYyWQRHEjSTUHC2JrKawGMeyXqCM49p7auVBy3Xd
- **Amount:** 0.002 SUI → ~0.00397 BTEN
- **Entry:** `cetus_swap_to_bten_b2a` on package v22
- **RouteRecorded:** yes
- Gas stayed small (~0.0025 SUI + input)

## Emission / vault after upgrade + autopay

- `block_height` = **343**
- `pending_blocks` = **4** (cadence unchanged)
- `total_minted` = 1715000000000 (unchanged by upgrade)
- `max_settle_blocks()` = **1** (`MAX_SETTLE_BLOCKS = 1`)
- `trader_vault` remaining ≈ **1135.0000001 BTEN** (`113500000010` mist)
- Unpaid point rows remaining: 4 (3 dust + current open round)

## Configs updated

- `Published.toml` → v22 / new published-at
- `MAINNET_ROUTE_CONFIG.json` → currentPackage / livePackageId / v22 section
- `config/block10_integration.json` → currentPackage / publishedVersion 22

## Artifacts

- `artifacts/v22/` — build, test, dry-run, live upgrade, autopay, swap proof, emission snapshots
