# BTEN v28 scope — turn off ExternalRouteVerifier daily attest cap

Compatible upgrade so receipts can keep rising without the practical daily cap.

## Behaviour

- `daily_event_cap == 0` means **unlimited**: skip the `events_today` assert in
  `attest_external_cetus_route_internal`.
- `create_external_route_verifier` accepts `0` (unlimited) or `1..=MAX_EXTERNAL_EVENTS_PER_DAY`.
- New `set_external_route_verifier_daily_cap(verifier, admin, daily_event_cap)`:
  same validation; sets cap and **resets `events_today = 0`** so today unblocks immediately.
- Limited mode (`> 0`) unchanged aside from the setter.

## Not in this upgrade

- No `make_immutable` / UpgradeCap destroy
- No struct layout changes (Compatible)
- Keeper script + configs updated for `0 = unlimited`

## Post-upgrade ops

1. Call `set_external_route_verifier_daily_cap(..., 0)` with RegistryAdminCap
2. Confirm on-chain `daily_event_cap=0` and attest no longer blocked by cap
