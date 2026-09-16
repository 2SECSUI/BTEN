# BTEN v26 upgrade — EXECUTED

## Result

- **Status:** success
- **Upgrade tx:** 7U81cRhXeoiLNEMfCfbPmBT3NZvtwjXZP5d4hLzgLHdz
- **New package (v26):** 0xa3c678ade7baaa4a27ddd7176a750700d41cf5e7e8c0ebcff7112a23ca11f5ff
- **Previous package (v25):** 0xfd25d25c6367bdb9591805b9ded083f30a6c928944c11a8135bc61ab5c41d4ec
- **UpgradeCap:** 0x97744b65d7241a102c68016bc568eab7552e1d72a1a0583a054b9dff51b2c10c
- **UpgradeCap policy:** Compatible (0) — **still upgradeable**
- **UpgradeCap package version field:** 26
- **Gas (upgrade):** ~0.2815 SUI (281488140 MIST)
- **No** `make_immutable` / `destroy`.
- **Modules:** bten, ops_buy_desk

## New API

```move
public entry fun cetus_swap_registered_a2b<A, B>(...)
public entry fun cetus_swap_registered_b2a<A, B>(...)
public fun cetus_swap_registered_a2b_return<A, B>(...): (Coin<A>, Coin<B>)
public fun cetus_swap_registered_b2a_return<A, B>(...): (Coin<B>, Coin<A>)
```

Bandbot WAL/SUI `0x72f5…3f17` is `Pool<WAL,SUI>`:
- SUI→WAL buy: `cetus_swap_registered_b2a`
- WAL→SUI: `cetus_swap_registered_a2b`
- WAL→BTEN: existing BTEN-pair adapters

## Artifacts

- `artifacts/v26/`

## Follow-on

WAL/SUI 1-raw trader rebate shipped in **v27** (Compatible): see `V27_UPGRADE_RESULT.md`.
