# Bandbot WAL/SUI external attest keeper (v29)

Paste-ready config: `config/bandbot_wal_sui_keeper.json`

## Goal

Attest **all** external Cetus activity on the Bandbot WAL/SUI pool so each
qualifying digest increments `batch_trades` (emission gate). Michael runs this
on Bandbot. **GitHub BTEN keeper stays disabled** (do not re-enable schedule /
local settle).

## v29 permissionless path (Cap NOT required)

For `pool_id == WAL_SUI_POOL_ID` only:

| Entrypoint | Cap? |
|------------|------|
| `bten::attest_wal_sui_external_route` | **No** |
| `bten::attest_wal_sui_external_routes` | **No** |
| `bten::attest_wal_sui_external_route_rebate` | **No** |
| `bten::attest_wal_sui_external_routes_rebate` | **No** |

Any Bandbot gas-paying signer can call. Still enforced on-chain:

- verifier **not paused**
- `pool_id == 0x72f5…3f17`
- registered Cetus pool
- `fee_points > 0`
- digest length 32
- **replay protection** (`processed` table → abort 30 on double-attest)
- optional `daily_event_cap` (`0` = unlimited)

Existing `attest_external_cetus_route*` on **other** pools still require
`ExternalRouteVerifierCap` + keeper sender.

### Spam warning

Permissionless = anyone can submit. Double-counting is blocked by the processed
table. Gas griefing is possible; pause / daily cap remain admin controls. Prefer
Bandbot-owned signer with a modest gas budget.

### Cap note (secure)

Bandbot does **not** need the verifier Cap for WAL/SUI. If Michael later wants
Cap-gated attest on other pools, hold Cap only in Bandbot secrets / sponsored
keeper settings — **never** paste private keys into docs, repo JSON, or chat.

## Objects (mainnet)

| Object | ID |
|--------|----|
| Package v29 | `0x8f4ee2f47e61dd1f6657492020934e3fc06bec36da782c4ba02c5fd17ab37ca5` |
| EmissionState | `0x22face12e4a73bc38171c5a2dd62a1cef8650bac3abc95eb5d3852ee36544253` |
| PoolRegistry | `0xc78a803d7acc6e9740911802e382a45c347e0fb012613a908eb0738c4957d133` |
| ExternalRouteVerifierState | `0x32206a1e910973b54b1225969365f58601399d3611a712e3644ab52c334b26f3` |
| Clock | `0x6` |
| WAL/SUI pool | `0x72f5c6eef73d77de271886219a2543e7c29a33de19a6c69c5cf1899f729c3f17` |
| DistributionState (optional settle) | `0x155a879794ae0c251677c7c9937b621ed094087908bc804d9112c897aeddb9b6` |

## Cetus event types to watch

- Swap: `0x1eabed72…::pool::SwapEvent` → `event_kind = 1`
- Add: `…::AddLiquidityEvent` / `0xdb5c…::AddLiquidityV2Event` → `event_kind = 2`
- Remove: `…::RemoveLiquidityEvent` / `…::RemoveLiquidityV2Event` → `event_kind = 3`

Also emitted by BTEN after success:

- `{pkg}::bten::ExternalCetusRouteAttested` (unchanged)
- `{pkg}::bten::WalSuiExternalAttested` (v29 annotation with `event_kind`)

## Recommended PTB — batch attest

```
bten::attest_wal_sui_external_routes(
  EmissionState,
  PoolRegistry,
  ExternalRouteVerifierState,
  pool_ids[],          // each == WAL_SUI_POOL_ID
  transaction_digests[], // 32-byte digests
  event_sequences[],
  traders[],
  fee_points_vec[],    // use 1
  event_kinds[],       // 1|2|3
  Clock
)
```

Single-item variant: `attest_wal_sui_external_route` (same args minus vectors).

Rebate variants add `WalSuiTraderRebateState` and accrue 1-raw from `route_fee_vault`.

## Optional settle

Only when eligible: `eligible = min(pending_blocks, batch_trades/10, 100) >= 1`.

```
bten::settle_and_distribute(EmissionState, DistributionState, Clock)
```

Skip entirely if not eligible.

## Safety rules

- **Do not touch WAL/SUI LP positions** or idle wallet funds beyond attest/settle gas
- Gas cap suggestion: ≤ 30M mist per attest batch; ≤ 50M if settle appended
- Never embed private keys in Bandbot prompts / this repo
- GH `bten-keeper.yml` schedule must stay **off**
