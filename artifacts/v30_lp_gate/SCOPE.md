# LP add + remove gated transactions (v30 package, verifier/config)

Live package remains **v30** `0x5a26ec01ee35959a00dfd684b9551c77b33e37f62596dc59196651129dbf06d6`.
No Compatible Move upgrade — on-chain attest paths already accept add/remove.

## Already gated (pre-change)
- External verifier matches Swap + AddLiquidity(+V2) + RemoveLiquidity(+V2)
- WAL/SUI permissionless `attest_wal_sui_external_route*` kinds 1/2/3
- Cap-gated `attest_external_cetus_route*` on other registered pools (kind-agnostic)
- `gatedEventKinds` already listed liquidity_remove

## Gaps closed
- MAINNET `cetusEventTypes` omitted RemoveLiquidity(+V2) — added
- Docs/notes only mentioned adds — updated
- Missing Move/JS tests for add+remove gating — added
- Stale package ids in keeper/bandbot_wal_sui configs → v30
- Shared `scripts/lib/cetus_lp_gate.mjs` + unit tests

## Ops fee
- No trader-facing BTEN LP entrypoints; protocol `deploy_protocol_liquidity_*` uncharged
- Attest keepers uncharged; trader `*_ops_fee` swaps still 0.5 SUI (ops waived)
