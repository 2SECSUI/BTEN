# BTEN v26 scope (adapters + WAL/SUI rebate)

Compatible upgrades:

1. **Registered-pool Cetus adapters** (on-chain package version 26):
   - `cetus_swap_registered_a2b` / `b2a` (+ `*_return`) for any registered `Pool<A,B>`
2. **WAL/SUI trader rebate** (next Compatible package version after 26):
   - 1 raw BTEN (`WAL_SUI_TRADER_REBATE_RAW = 1`) per qualifying trade from **`route_fee_vault` only** (no mint)
   - Accrue via `cetus_swap_registered_*_rebate` or `attest_external_cetus_route_rebate` when pool is Bandbot WAL/SUI
   - Flush via `pay_wal_sui_trader_rebates` — max **1000** pays/call; **pay-what-you-can** if vault empty mid-batch

UpgradeCap Compatible only. Never make_immutable.
