# BTEN v29 upgrade — EXECUTED (permissionless WAL/SUI attest)

## Result

- **Status:** success
- **Upgrade tx:** 4kpc4Z3tf8oXnH2pb9AS5PrVJKwXYQMhkudK19Af31YR
- **New package (v29):** 0x8f4ee2f47e61dd1f6657492020934e3fc06bec36da782c4ba02c5fd17ab37ca5
- **Previous (v28):** 0x6e46f9b9fb500882f69ed96d370fc61153ff39b1056aef2a86485bc81b17324c
- **UpgradeCap policy:** Compatible (0) — still upgradeable
- **Gas (upgrade):** ~0.313 SUI (313386620 MIST)
- **No** make_immutable

## Behaviour

- Permissionless WAL/SUI entrypoints (no Cap, any signer):
  - `bten::attest_wal_sui_external_route` / `routes`
  - `bten::attest_wal_sui_external_route_rebate` / `routes_rebate`
- Cap-gated `attest_external_cetus_route*` unchanged for other pools
- New event `WalSuiExternalAttested` with `event_kind` 1=swap, 2=add, 3=remove
- GH keeper schedule **disabled**; Bandbot pack published

## Tests

- 29/29 pass (non-keeper happy path + wrong-pool abort 44)

## Bandbot paste paths

- `docs/BANDBOT_WAL_SUI_KEEPER.md`
- `config/bandbot_wal_sui_keeper.json`
