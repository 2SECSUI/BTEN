# BTEN GitHub keeper

The dedicated keeper address is `0xd833a2ffe167e0bd56205b6b4e4a4bd78e035ff899a788fc892b5be713b76474`.
It owns no UpgradeCap, RegistryAdminCap, farm cap, LP position, or treasury asset.

## Status (2026-09-16, v29)

**DISABLED.** Michael runs WAL/SUI external attest on Bandbot via permissionless
`attest_wal_sui_external_route*` (Cap not required for WAL/SUI). Do **not**
re-enable the `bten-keeper.yml` schedule or local settle routine without an
explicit OK.

See `docs/BANDBOT_WAL_SUI_KEEPER.md` and `config/bandbot_wal_sui_keeper.json`.

## Explicit limits (when/if re-enabled)

The GH keeper may only call permissionless `settle_and_distribute` /
`sync_route_treasury` and Cap-gated external attest for non-WAL/SUI pools. It
must never run sponsor, swap, zap, LP distribution, farm funding, or upgrade
paths.
