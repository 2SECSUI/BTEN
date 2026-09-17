# BTEN v29 scope — permissionless WAL/SUI external attest

Compatible upgrade. Michael approved the **risky** option: anyone may attest
WAL/SUI digests **without** `ExternalRouteVerifierCap`. Bandbot runs the keeper;
do **not** re-enable the GitHub BTEN keeper schedule or local settle routine.

## Behaviour

- New **permissionless** entrypoints (no Cap; any gas-paying signer):
  - `attest_wal_sui_external_route` / `attest_wal_sui_external_routes`
  - `attest_wal_sui_external_route_rebate` / `attest_wal_sui_external_routes_rebate`
- Still require: `pool_id == WAL_SUI_POOL_ID`
  (`0x72f5c6eef73d77de271886219a2543e7c29a33de19a6c69c5cf1899f729c3f17`),
  verifier not paused, replay protection (`processed` table), daily_event_cap
  rules (`0` = unlimited), `fee_points > 0`, registered Cetus pool.
- Still take `&mut ExternalRouteVerifierState` for processed / events_today.
- **Do not** enforce keeper-sender identity on this path.
- Existing `attest_external_cetus_route*` keep Cap + keeper-sender for all other pools.
- New event `WalSuiExternalAttested { pool_id, trader, digest, event_sequence, event_kind, fee_points }`
  emitted after unchanged `ExternalCetusRouteAttested` (Compatible).
- `event_kind`: **1=swap**, **2=add**, **3=remove**.

## Risk note

Permissionless WAL/SUI attest can be spammed for gas griefing; double-count is
blocked by the processed table (abort 30). Pause / daily cap remain admin controls.

## Not in this upgrade

- No `make_immutable` / UpgradeCap destroy (policy stays Compatible).
- No WAL/SUI LP position or idle-wallet moves beyond upgrade gas.
- No GitHub BTEN keeper re-enable; no local settle routine re-enable.

## Tests

- Wrong pool → abort `E_WAL_SUI_POOL_MISMATCH` (44)
- Happy path from non-keeper signer → one gate receipt

## Post-upgrade ops

1. Publish `Published.toml` / configs to v29 package id
2. Bandbot keeper pack: Cap **not** required for WAL/SUI path
3. Update `external_cetus_verifier.mjs` to use WAL/SUI entrypoints when pool matches
4. Keep GH `bten-keeper.yml` schedule **disabled**
