# BTEN v24 scope — restore v16 emission rules

User cancelled v19 work and asked to “go back to v16”. This Compatible upgrade
restores **v16 emission rules** only (not a literal wipe of later modules).

## Live baseline

- Package v23: `0x193e41283f69201559581394b9bc8e9743e5411f9407b0609127421881843688`
- UpgradeCap: `0x97744b65d7241a102c68016bc568eab7552e1d72a1a0583a054b9dff51b2c10c` (ops)
- Policy: Compatible (0) — **never** `make_immutable` / destroy UpgradeCap

## Emission change (commit reference `2f18c31` / package `0xc71c7ab8…bcc41`)

- `MIN_TRADES_PER_BLOCK = 10`
- `MAX_SETTLE_BLOCKS = 100`
- Trade-gated settle:
  - `advance_slots(...)`
  - `trade_supported = batch_trades / MIN_TRADES_PER_BLOCK`
  - `blocks = min(pending_blocks, trade_supported, MAX_SETTLE_BLOCKS)`
  - `assert!(blocks > 0, E_NO_ELIGIBLE_BLOCKS)`
  - existing mint / allocate / round seal + clear `batch_trades` / `fee_points`

Undo Bitcoin-style `MAX_SETTLE=1` and trade-bar-free settle from v20/v21.

## Keep (do not delete)

- ManagedVault
- OpsBuyDesk
- `auto_pay_trader` u128 intermediate
- External attest (incl. liquidity-add verifier script)
- Compatible UpgradeCap

## Config / keeper

- `github_keeper` eligible = `min(pending, batch_trades/10, 100)`
- `keeper_policy` / `MAINNET_ROUTE_CONFIG` / `block10_integration` notes aligned

## Not in this upgrade

- Settles / attests / LP bots beyond the upgrade tx
- Immutable package / UpgradeCap destroy
