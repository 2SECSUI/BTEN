# BTEN v24 upgrade — EXECUTED

## Result

- **Status:** success
- **Tx:** AwfnPvTxo1Fv7hYgE1bhjHy84VSRoGsEQRFBBR37PzLH
- **New package (v24):** 0x541218960bce9fb0c1c8677691687bea9d4d64d9cc868c28e06aab1381ed797f
- **Previous package (v23):** 0x193e41283f69201559581394b9bc8e9743e5411f9407b0609127421881843688
- **UpgradeCap:** 0x97744b65d7241a102c68016bc568eab7552e1d72a1a0583a054b9dff51b2c10c
- **UpgradeCap owner:** 0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a
- **UpgradeCap policy:** Compatible (0) — **still upgradeable**
- **UpgradeCap package version field:** 24
- **Gas:** ~0.2721 SUI (272061740 MIST)
- **Ops SUI left:** ~3.99 SUI
- **No** `make_immutable` / `destroy`. authorize_upgrade used policy `0`.
- **Modules:** bten, ops_buy_desk

## Emission restored (v16 rules)

- `MIN_TRADES_PER_BLOCK = 10`
- `MAX_SETTLE_BLOCKS = 100`
- Trade-gated settle: `min(pending, batch_trades/10, 100)`

## Kept

- ManagedVault, OpsBuyDesk, auto_pay u128, external attest, Compatible UpgradeCap

## Artifacts

- `artifacts/v24/` — build, test, dry-run, live upgrade
