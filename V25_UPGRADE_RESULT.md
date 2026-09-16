# BTEN v25 upgrade — EXECUTED

## Result

- **Status:** success
- **Upgrade tx:** FdGQDSwPsVH85gZNme1cSzAMpGixG5MFT26fxRW7fLsF
- **New package (v25):** 0xfd25d25c6367bdb9591805b9ded083f30a6c928944c11a8135bc61ab5c41d4ec
- **Previous package (v24):** 0x541218960bce9fb0c1c8677691687bea9d4d64d9cc868c28e06aab1381ed797f
- **UpgradeCap:** 0x97744b65d7241a102c68016bc568eab7552e1d72a1a0583a054b9dff51b2c10c
- **UpgradeCap policy:** Compatible (0) — **still upgradeable**
- **UpgradeCap package version field:** 25
- **Gas (upgrade):** ~0.2726 SUI (272601340 MIST)
- **No** `make_immutable` / `destroy`.
- **Modules:** bten, ops_buy_desk

## New API

```move
public fun unregister_pool(registry: &mut PoolRegistry, _admin: &RegistryAdminCap, pool_id: address)
```

Asserts `table::contains` then `table::remove`. Works after finalize.

## Unregister (live)

- **Tx:** F8GcLjB4DRJVykfu7pQ8m6roZixyLnfYLbLZbE9ztwEW
- Removed (4 dynamic fields deleted):
  - USDT `0x6b1d71d6…e19c`
  - USDC `0x26dd78ba…4b45`
  - DEEP `0x924c998e…d835`
  - NS `0x41ee9006…8c2c`
- Registry `pools.size` after: **7**
- Re-unregister dry-runs abort `E_POOL_NOT_REGISTERED` (12) for all four

## Ops LP closes (before unregister)

| Asset | Position | Digest |
|-------|----------|--------|
| NS | 0x7c25c5a5…ae49 | F85vUEv2VjjLaaoWoSrnxtAUTWxfcaV5EZmMYwVn4b4X |
| USDC | 0xa60d60b4…d6e4 | 6jCBZp2eBE4Aj4cuiwMBEZTrXPLsKBsSRyjKfRdnuZbc |
| USDT | (already zero) | — |
| DEEP | (already zero) | — |

## Artifacts

- `artifacts/v25/`
