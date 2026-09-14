# OpsBuyDesk

Public users can buy BTEN from **ops inventory** at the **same price as the Cetus BTEN/SUI pool mid**. **No −2% discount** (discountBps = 0).

## Pool

| Field | Value |
|-------|-------|
| Cetus pool | `0x7f46bdbd74d2f162617376e4cecccb2c603bb9459766226d1359b38a605a2950` |
| Type | `Pool<BTEN, SUI>` |
| Ops | `0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a` |

## How price equals pool mid

1. **Primary (preferred):** `ops_buy_desk::buy_with_sui` takes `&Pool<BTEN, SUI>`, asserts `object::id(pool) == desk.pool_id`, reads `current_sqrt_price`, and computes:

   - `bten_out = sui_in * 2^128 / sqrt_price^2` (mist)
   - Equivalent posted price: `price_mist_sui_per_bten = sqrt_price^2 * 1e8 / 2^128` (mist SUI per 1 full BTEN)

   No fee, no discount — pure mid.

2. **Fallback:** `buy_with_sui_posted_price` uses admin/keeper field `price_mist_sui_per_bten`. Keeper script `scripts/ops_buy_desk_sync_price.mjs` reads the same Cetus mid off-chain and sets that field **equal to mid** (discountBps=0). **Keeper must stay running** for fair posted-price / UI quotes.

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
| `set_pool_id` | Expected Cetus pool id |
| `set_price_updater` | Address allowed to push keeper prices |
| `set_price_mist_sui_per_bten_admin` | Manual posted mid |

### Keeper

| Entry | Purpose |
|-------|---------|
| `set_price_mist_sui_per_bten` | Sender must be `price_updater`; sets posted mid = Cetus mid |

### Public

| Entry | Purpose |
|-------|---------|
| `buy_with_sui` | Pay `Coin<SUI>`, get BTEN at **in-tx pool mid**; `min_bten_out` slippage |
| `buy_with_sui_posted_price` | Same at keeper-posted mid |

Buyer SUI is transferred to `sui_recipient`. BTEN comes from desk inventory (not minted).

## Create + fund (ops)

1. Compatible package upgrade to v23 (keep UpgradeCap `0x97744b…c10c`; **do not** `make_immutable`).
2. Dry-run mid: `node scripts/ops_buy_desk_sync_price.mjs`
3. Call `ops_buy_desk::create` with `RegistryAdminCap`:
   - `operator` / `sui_recipient` / `price_updater` → ops (or dedicated updater)
   - `pool_id` → Cetus BTEN/SUI pool above
   - `initial_price_mist_sui_per_bten` → dry-run mid
4. Record `deskObjectId` + `adminCapId` into `config/ops_buy_desk.json` and `config/block10_integration.json#opsBuyDesk`.
5. `deposit_bten` from ops wallet.
6. Schedule `node scripts/ops_buy_desk_sync_price.mjs --execute` (env `BTEN_OPS_BUY_DESK_UPDATER_KEY`).
7. Republish Block10 Swap/Buy UI (site may 404 until republish).

## Config

- `config/ops_buy_desk.json`
- `config/block10_integration.json` → `opsBuyDesk` + `publicSwap` (Grok App Builder checklist)

## Safety

- `neverEmbedPrivateKeys`
- Does not touch UpgradeCap / emission mint path / incentive bots
- Pause flag for emergencies
