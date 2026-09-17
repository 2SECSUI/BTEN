# BTEN v30 upgrade — EXECUTED (ops interaction fee + ops waive)

## Result

- **Status:** success
- **Upgrade tx:** `Ebi51YT32ycRuodWk2CU5uMYGpwKZTFiNbXjuyAzzeFM`
- **New package (v30):** `0x5a26ec01ee35959a00dfd684b9551c77b33e37f62596dc59196651129dbf06d6`
- **Previous (v29):** `0x8f4ee2f47e61dd1f6657492020934e3fc06bec36da782c4ba02c5fd17ab37ca5`
- **Original package:** `0x31c6c71184b08a574bd62fa8edd9a75aab9a986427484cf765a1890ce00aece0`
- **UpgradeCap:** `0x97744b65d7241a102c68016bc568eab7552e1d72a1a0583a054b9dff51b2c10c`
- **UpgradeCap policy:** Compatible (0) — retained / still upgradeable
- **Gas (upgrade):** ~0.316 SUI (`315508900` MIST)
- **No** `make_immutable` / UpgradeCap destroyed

## OpsInteractionFeeConfig (created once)

- **Tx:** `7dGi4Ku3MhJMLq3MFF99zCqCw5kAke8V6Po4ZbYp8MNV`
- **Object id:** `0xef706ead1654afa2276f94ffda82b4193a50c0bdeb6e497354f20712d72949e6`
- **Shared initial version:** `1001408738`
- **Defaults on-chain:** `fee_mist = 500_000_000` (0.5 SUI), `recipient = OPS_FEE_RECIPIENT`

## Fee waive allowlist

Hard-coded wallet address constants scanned in `sources/*.move`:

| Constant | Address | Waived? |
|----------|---------|---------|
| `OPS_FEE_RECIPIENT` | `0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a` | **yes** |
| `WAL_SUI_POOL_ID` | `0x72f5c6eef73d77de271886219a2543e7c29a33de19a6c69c5cf1899f729c3f17` | no (pool id, not a wallet) |

Keeper / treasury / farm recipients are runtime-configured (not compile-time `address = @0x…` wallet constants) and are **not** on the allowlist.

When waived: optional `ops_fee: Coin<SUI>` accepted (including zero); full coin returned to sender; no transfer to ops; no `OpsInteractionFeePaid` event. External traders still pay ≥ 0.5 SUI.

## Tests

- `sui move test` — **37/37 PASS** (ops sender waived + random sender charged added)

## Bandbot

- **Untouched** in this upgrade (no Bandbot app/config/script edits for this publish).

## Published.toml

- mainnet `published-at` / `version = 30` updated to new package id.
