# OpsBuyDesk

Public users can buy BTEN from **ops inventory** at the **WAL-implied BTEN mid** (BTEN/WAL home book × WAL/SUI). **No −2% discount** (discountBps = 0).

## Pricing source (WAL path)

| Field | Value |
|-------|-------|
| Home book | Cetus `Pool<WAL, BTEN>` `0xa9f12a204ac1cb778c015e77a88fc8eb5926599ece17b2a8841753c7712544c7` |
| WAL→SUI leg | Cetus `Pool<WAL, SUI>` `0x72f5c6eef73d77de271886219a2543e7c29a33de19a6c69c5cf1899f729c3f17` |
| Formula | `price_mist_sui_per_bten = UNIT * sqrt_wal_sui² / sqrt_wal_bten²` (UNIT = 1e8) |
| Ops | `0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a` |

### Legacy BTEN/SUI pool (LEFT OPEN)

| Field | Value |
|-------|-------|
| Cetus pool | `0x7f46bdbd74d2f162617376e4cecccb2c603bb9459766226d1359b38a605a2950` |
| Type | `Pool<BTEN, SUI>` |
| Role | Optional / legacy display only. **Do not unregister or destroy.** Ops LP may be closed; the pool object stays as-is. |

## How buys settle

1. **Primary (preferred):** `ops_buy_desk::buy_with_sui_posted_price` uses keeper field `price_mist_sui_per_bten`. Keeper `scripts/ops_buy_desk_sync_price.mjs` reads WAL/BTEN + WAL/SUI off-chain and posts mist SUI per 1 full BTEN (**equal to WAL-implied mid**, discountBps=0). **Keeper must stay running** for fair posted-price / UI quotes.

2. **Legacy (optional):** `buy_with_sui` still takes `&Pool<BTEN, SUI>` and prices at that pool’s in-tx mid. Not the desk pricing source after the WAL rewire; do not rely on it for home-book pricing.

No package upgrade was required for the WAL rewire: posted-price path already accepts keeper mist without reading a SUI-denominated BTEN pool on-chain.

## Module

`bten::ops_buy_desk` (new in v23). Shared object `OpsBuyDesk` holds `Balance<BTEN>` inventory.

### Admin (`OpsBuyDeskAdminCap`)

| Entry | Purpose |
|-------|---------|
| `create` | One-time; needs `RegistryAdminCap`; shares desk; transfers admin cap to operator |
| `deposit_bten` | Fund inventory |
| `withdraw_bten` | Remove inventory |
| `set_paused` | Pause public buys |
| `set_sui_recipient` | Where buyer SUI is sent |
| `set_pool_id` | Expected Cetus pool id (legacy `buy_with_sui` assert only) |
| `set_price_updater` | Address allowed to push keeper prices |
| `set_price_mist_sui_per_bten_admin` | Manual posted mid |

### Keeper

| Entry | Purpose |
|-------|---------|
| `set_price_mist_sui_per_bten` | Sender must be `price_updater`; sets posted mid = WAL-implied mid |

### Public

| Entry | Purpose |
|-------|---------|
| `buy_with_sui_posted_price` | Pay `Coin<SUI>`, get BTEN at **keeper-posted WAL-implied mid**; `min_bten_out` slippage |
| `buy_with_sui` | Legacy: pay at in-tx `Pool<BTEN,SUI>` mid |

Buyer SUI is transferred to `sui_recipient`. BTEN comes from desk inventory (not minted).

## Keeper

```bash
node scripts/ops_buy_desk_sync_price.mjs            # dry-run
node scripts/ops_buy_desk_sync_price.mjs --execute  # posts price (env BTEN_OPS_BUY_DESK_UPDATER_KEY)
```

## Related

- One price story + any-coin → WAL → BTEN buy path: `docs/BUY_VIA_WAL.md`
- Bandbot harvest sink: `docs/BANDBOT_BTEN_INTEGRATION.md` + `config/bandbot_bten_integration.json`

## Config

- `config/ops_buy_desk.json`
- `config/block10_integration.json` → `opsBuyDesk` + `publicSwap` (Grok App Builder checklist)

## Safety

- `neverEmbedPrivateKeys`
- Does not touch UpgradeCap / emission mint path / incentive bots
- **Does not unregister or destroy the Cetus BTEN/SUI pool**
- Pause flag for emergencies
