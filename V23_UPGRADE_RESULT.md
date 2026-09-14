# BTEN v23 upgrade — EXECUTED

## Result

- **Status:** success
- **Tx:** 5JcgCBKAKVEugBeaa8Fh2RS4Qeo8nrLAwBKdiZAum12W
- **New package (v23):** 0x193e41283f69201559581394b9bc8e9743e5411f9407b0609127421881843688
- **Previous package (v22):** 0x636c670a9454013ae7ea96046279b75821b339146598b68661b9b06a26eb61f6
- **UpgradeCap:** 0x97744b65d7241a102c68016bc568eab7552e1d72a1a0583a054b9dff51b2c10c
- **UpgradeCap owner:** 0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a
- **UpgradeCap policy:** Compatible (0) — **still upgradeable**
- **UpgradeCap package version field:** 23
- **Gas:** ~0.2718 SUI
- **No** `make_immutable` / `destroy`. authorize_upgrade used policy `0`.
- **Modules:** bten, ops_buy_desk

## OpsBuyDesk

- **deskObjectId:** 0xb0e9c4a61e204eb23cd408dd2e67e9da9b5c76cec76432843fb589d014fe15c1
- **adminCapId:** 0x5c4089420effa5b9963ee152311180e2b08578842a22519f2d4c134b8983d3c4
- **createTx:** DjpVx1mgZno15C15tMTeRaSg1Ya5W7wjAJTi886xfNmn
- **initialPriceMistSuiPerBten:** 428465615 (~0.4285 SUI/BTEN Cetus mid)
- **smoke deposit:** 1059820741 mist (~10.5982 BTEN) tx `Fs6jsx734MoJDbgRj3N9rj45etebHyzECSbEKGAuJYX8`

## Configs updated

- `Published.toml` → v23 / new published-at
- `config/ops_buy_desk.json`
- `config/block10_integration.json`
- `MAINNET_ROUTE_CONFIG.json` → v23 section

## Artifacts

- `artifacts/v23/` — build, test, dry-run, live upgrade, create, smoke deposit
