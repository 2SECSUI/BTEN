# Bandbot → BTEN/WAL sink + settle-when-ready

Paste-ready settings: `config/bandbot_bten_integration.json`  
Dry-run (read-only): `scripts/bandbot_harvest_sink_settle_dryrun.mjs`

## Goal

After Bandbot harvests fees on WAL/SUI (or holds WAL/SUI):

1. Optional: SUI → WAL via registered adapter on `Pool<WAL,SUI>`
2. WAL → BTEN via BTEN/WAL adapters only
3. Cetus `addLiquidity` on BTEN/WAL (sink)
4. If settle-eligible (`pending_blocks >= 1` **and** `batch_trades + 1 >= 10`), append `settle_and_distribute`

## PTB order (recommended)

```
[optional] bten::cetus_swap_registered_b2a(+_rebate)   # SUI→WAL on WAL/SUI
          bten::cetus_swap_to_bten                     # WAL→BTEN on Pool<WAL,BTEN>
          Cetus addLiquidity (BTEN + remaining WAL)    # sink into BTEN/WAL
[if eligible] bten::settle_and_distribute              # EmissionState + DistributionState + Clock
```

Eligibility (v16/v24 gate, live through v28):

- `eligible_blocks = min(pending_blocks, batch_trades / 10, 100)`
- After this route would add ~1 receipt: treat as settle-ready when  
  `pending_blocks >= 1 && (batch_trades + 1) >= 10`
- **Do not** call settle if not eligible (wastes gas / no-op or abort depending on path)

## Objects (mainnet)

| Object | ID |
|--------|----|
| Package v28 | `0x6e46f9b9fb500882f69ed96d370fc61153ff39b1056aef2a86485bc81b17324c` |
| EmissionState | `0x22face12e4a73bc38171c5a2dd62a1cef8650bac3abc95eb5d3852ee36544253` |
| DistributionState | `0x155a879794ae0c251677c7c9937b621ed094087908bc804d9112c897aeddb9b6` |
| PoolRegistry | `0xc78a803d7acc6e9740911802e382a45c347e0fb012613a908eb0738c4957d133` |
| Cetus GlobalConfig | `0xdaa46292632c3c4d8f31f23ea0f9b36a28ff3677e9684980e4438403a67a3d8f` |
| Clock | `0x6` |
| BTEN/WAL pool | `0xa9f12a204ac1cb778c015e77a88fc8eb5926599ece17b2a8841753c7712544c7` |
| WAL/SUI pool | `0x72f5c6eef73d77de271886219a2543e7c29a33de19a6c69c5cf1899f729c3f17` |

### Coin types

- BTEN: `0x31c6c71184b08a574bd62fa8edd9a75aab9a986427484cf765a1890ce00aece0::bten::BTEN`
- WAL: `0x356a26eb9e012a68958082340d4c4116e7f55615cf27affcff209cf0ae544f59::wal::WAL`
- SUI: `0x2::sui::SUI`

## Safety

- **Non-custodial:** wallet signs every PTB; funds return to sender on success; full revert on abort
- **Gas caps:** set budget (e.g. 50–80M mist for multi-hop + LP + optional settle)
- **Never embed keys** in Bandbot settings / prompts / this repo config
- **No settle if not eligible**
- Sink **only** BTEN/WAL — do not open side BTEN LPs; do not unregister BTEN/SUI
- Dry-run script: read-only eligibility + print recommended PTB — **NO execute / NO spend**

## Republish

After wiring, republish **bandbot.grok.me** with `config/bandbot_bten_integration.json` and this doc.  
Block10 Buy/Swap uses `docs/BUY_VIA_WAL.md` + `config/block10_integration.json` on **block10.grok.me**.

## Dry-run

```bash
node scripts/bandbot_harvest_sink_settle_dryrun.mjs
# optional: --wal-raw 1000000  --sui-raw 0
```

Refuses `--execute` / `--sign`.
