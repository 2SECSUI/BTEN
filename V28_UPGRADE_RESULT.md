# BTEN v28 upgrade — EXECUTED (unlimited external attest cap)

## Result

- **Status:** success
- **Upgrade tx:** n1ocCrsNRwbX1AhCnaKf1SyV78h97fjMtKMBWZc71Rq
- **New package (v28):** 0x6e46f9b9fb500882f69ed96d370fc61153ff39b1056aef2a86485bc81b17324c
- **Previous (v27):** 0xd09ce79839cac09cb2bf8a24b223fb4580268045805863b29b6bcfcea043d703
- **UpgradeCap policy:** Compatible (0) — still upgradeable
- **Gas (upgrade):** ~0.301 SUI (300962820 MIST)
- **No** make_immutable

## Daily cap off

- **Setter tx:** 26NRdyGhtHuuAnBz9wNbkEeYvV44jwVmFbBzpy8CWTbE
- **Verifier:** 0x32206a1e910973b54b1225969365f58601399d3611a712e3644ab52c334b26f3
- **Confirmed on-chain:** `daily_event_cap=0`, `events_today=0`
- Semantics: `0` skips the events_today assert (unlimited)

## Added

- `bten::set_external_route_verifier_daily_cap`
- create/attest paths treat `daily_event_cap == 0` as unlimited
- Keeper script treats `0` as unlimited remaining daily

## Tests

- 27/27 pass (includes unlimited create + setter)
