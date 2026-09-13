# BTEN v19 scope

Target: mainnet package after live v18 (`0x57be4e19…4098`).

## Emission gate (product, locked)

**Gated means emission-block release**, not live-tape labeling.

- `MIN_TRADES_PER_BLOCK` is **1**. Each gated receipt can unlock one pending
  ten-minute block, capped by `pending_blocks` and `MAX_SETTLE_BLOCKS` (100).
- Receipts that count: package adapter `RouteRecorded` and
  `ExternalCetusRouteAttested` (both call `record_atomic_route`).
- External Cetus/aggregator volume on registered BTEN pools is emission-gated
  via `attest_external_cetus_route` / `attest_external_cetus_routes`.
- One emission-gate receipt per transaction digest (multi-pool aggregator
  PTBs still one receipt).
- Do not block transactions. Do not treat tape-only labels as the gate.

## Also in v19

- `attest_external_cetus_routes` batch entrypoint (Compatible addition).
- Keeper `ROUTES_PER_BLOCK = 1`; configs clarify emission-unlock wording.
- Permissionless vault movement after settle: `settle_and_distribute`,
  `sync_route_treasury`, `accrue_lp_program`, `sync_bten_staking_farm_rewards`.

## Not in this upgrade

- `make_immutable` / destroying UpgradeCap. Package stays Compatible (0).
- Inventing Magma/Bluefin native CLMM adapters.
