# Buy / price via WAL (one price story)

Block10 Buy/Swap and OpsBuyDesk share **one** pricing + purchase policy.

## Price truth (WAL-implied BTEN)

| Leg | Pool | Role |
|-----|------|------|
| BTEN/WAL home book | `0xa9f12a204ac1cb778c015e77a88fc8eb5926599ece17b2a8841753c7712544c7` (`Pool<WAL,BTEN>`) | Mid used for BTEN in WAL |
| WAL/SUI | `0x72f5c6eef73d77de271886219a2543e7c29a33de19a6c69c5cf1899f729c3f17` (`Pool<WAL,SUI>`) | Converts WAL mid → mist SUI |
| Formula | `price_mist_sui_per_bten = UNIT * sqrt_wal_sui² / sqrt_wal_bten²` (UNIT = 1e8) | Same as OpsBuyDesk keeper |

**Do not** use Cetus BTEN/SUI, BTEN/CETUS, or other side pairs as pricing truth.

OpsBuyDesk already posts this mid via `scripts/ops_buy_desk_sync_price.mjs` → `buy_with_sui_posted_price`. Keep that.

## Buy path (any coin → WAL → BTEN)

1. Convert input coin → **WAL** (registered adapters / quotes; for SUI use `bten::cetus_swap_registered_b2a` on WAL/SUI, optionally `*_rebate`).
2. Convert **WAL → BTEN** only on BTEN/WAL:
   - `bten::cetus_swap_to_bten` (WAL is coin A → a2b), or
   - `bten::cetus_swap_to_bten_b2a` if coin order ever flips.
3. Never use BTEN/SUI, BTEN/CETUS, BTEN/NAVX, etc. as the **BTEN purchase leg**.

## Legacy BTEN/SUI (OPEN, demoted)

| Field | Value |
|-------|-------|
| Pool | `0x7f46bdbd74d2f162617376e4cecccb2c603bb9459766226d1359b38a605a2950` |
| Role | Legacy / display / compare-only |
| Rules | **Do not unregister.** Not pricing. Not primary Buy. Do not open new side BTEN LPs for Buy. |

## Package

Live package **v28**: `0x6e46f9b9fb500882f69ed96d370fc61153ff39b1056aef2a86485bc81b17324c`  
(`Published.toml`, `currentPackage`, `livePackageId`, `publicSwap.packageId`).

## Config pointers

- `config/block10_integration.json` → `priceTruth`, `buyPath`, `publicSwap`, `opsBuyDesk`, `routeSelection`
- `config/ops_buy_desk.json`
- `MAINNET_ROUTE_CONFIG.json` → `priceTruth`, `buyPath`
- `docs/OPS_BUY_DESK.md`

## Safety

- Wallet-signed; `neverEmbedPrivateKeys`
- No live harvest/settle/swap from this doc alone — use Bandbot dry-run for planning
