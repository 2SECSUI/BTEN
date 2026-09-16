# BTEN v27 scope (WAL/SUI trader rebate)

Completes the registered-adapter work from v26 with a 1-raw BTEN trader rebate
for qualifying WAL/SUI volume, funded only from `EmissionState.route_fee_vault`.

## Constants

- `WAL_SUI_TRADER_REBATE_RAW = 1` (0.00000001 BTEN)
- `MAX_WAL_SUI_REBATE_BATCH = 1000`
- `WAL_SUI_POOL_ID = 0x72f5…3f17`

## API

- `create_wal_sui_trader_rebate_state`
- `cetus_swap_registered_a2b_rebate` / `b2a_rebate` — swap + accrue when pool matches
- `attest_external_cetus_route_rebate` / `routes_rebate` — attest + accrue
- `pay_wal_sui_trader_rebates` — flush pending; **pay-what-you-can** if vault empty

No uncapped mint. Compatible UpgradeCap retained.
