# BTEN v30 scope — ops interaction fee (0.5 SUI)

Compatible upgrade. Charge **0.5 SUI** (`500_000_000` MIST) once per trader-facing
BTEN swap / OpsBuyDesk buy, paid with a separate `Coin<SUI>` and transferred to
the ops wallet.

## Ops recipient (documented)

`0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a`

(Constant `OPS_FEE_RECIPIENT`; also UpgradeCap owner. Admin may retarget via
`set_ops_interaction_fee_recipient`.)

## Fee amount

- Default constant: `OPS_INTERACTION_FEE_MIST = 500_000_000`
- Shared `OpsInteractionFeeConfig { recipient, fee_mist }` created once with
  `create_ops_interaction_fee_config` (RegistryAdminCap)
- Admin setters: `set_ops_interaction_fee`, `set_ops_interaction_fee_recipient`
- Collect helper: `collect_ops_interaction_fee` — aborts `E_OPS_INTERACTION_FEE` (46)
  if coin value &lt; fee; remainder returned to payer; emits `OpsInteractionFeePaid`

## Entrypoints that charge (new `*_ops_fee` variants)

Compatible cannot change existing public signatures, so fee-taking clones were
added and **legacy free entries abort** `E_OPS_FEE_REQUIRED` (47):

### Cetus BTEN adapters
- `cetus_swap_to_bten_ops_fee` / `cetus_swap_from_bten_ops_fee`
- `cetus_swap_to_bten_b2a_ops_fee` / `cetus_swap_from_bten_a2b_ops_fee`

### Registered-pool adapters (incl. WAL/SUI + rebate)
- `cetus_swap_registered_a2b_ops_fee` / `cetus_swap_registered_b2a_ops_fee`
- `cetus_swap_registered_a2b_rebate_ops_fee` / `cetus_swap_registered_b2a_rebate_ops_fee`

### Any-coin / SUI→BTEN→asset buy paths
- `cetus_sui_to_asset_via_bten_a2b_ops_fee` / `b2a_ops_fee`
- `cetus_sui_to_asset_via_bten_rebate_a2b_ops_fee` / `b2a_ops_fee`

### Turbos BTEN adapters
- `turbos_swap_to_bten_ops_fee` / `turbos_swap_from_bten_ops_fee`
- `turbos_swap_to_bten_b_first_ops_fee` / `turbos_swap_from_bten_a_first_ops_fee`

### OpsBuyDesk
- `buy_with_sui_ops_fee` / `buy_with_sui_posted_price_ops_fee`
  (legacy buys abort local `E_OPS_FEE_REQUIRED` = 11)

Each takes `fee_config: &OpsInteractionFeeConfig` + `ops_fee: Coin<SUI>` and calls
`collect_ops_interaction_fee` once before the swap/buy body.

## Not charged (by design)

- Permissionless / Cap-gated WAL/SUI **attest** keepers (`attest_wal_sui_*`,
  `attest_external_cetus_*`) — gas-only; no trader `Coin<SUI>` fee
- `pay_wal_sui_trader_rebates`, farm stake/withdraw/claim, settle/distribute
- Protocol LP deploy (`deploy_protocol_liquidity_*`), managed vault, admin creates
- Composable `*_return` hop helpers (fee belongs on outer entry / PTB once)

## Safeties

- UpgradeCap stays **Compatible** — never `make_immutable` / destroy
- Do **not** touch Cetus vault `0x539079f8c0b0055e334307d472fe693a2c0ae545d4f3c9752e1e6ceddb446bc0`
- Keep BTEN/SUI, BTEN/CETUS, BTEN/WAL open conceptually
- Do **not** edit Bandbot app/UI in this upgrade (callers must switch to `*_ops_fee`
  before or with live publish)

## Post-upgrade ops (Michael)

1. `create_ops_interaction_fee_config` with RegistryAdminCap → record shared object id
2. Update Block10 / Bandbot PTBs to `*_ops_fee` + pass 0.5 SUI fee coin (split from gas)
3. Update `Published.toml` / configs to v30 package id
4. Confirm UpgradeCap still Compatible

## Tests

- Defaults = 0.5 SUI / ops recipient
- Collect happy path + remainder return
- Underpay → abort 46
- Admin `set_ops_interaction_fee`
- OpsBuyDesk buy with fee; legacy buy → abort 11


## Fee waive (ops / protocol wallets) — added before live

`collect_ops_interaction_fee` waives the 0.5 SUI fee when `tx_context::sender(ctx)` is
on the hard-coded allowlist. After scanning `sources/*.move` for `address = @0x…`
wallet constants, only:

- `OPS_FEE_RECIPIENT` = `0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a`

is included (`WAL_SUI_POOL_ID` is a pool, not a wallet). Waived path returns the
optional `ops_fee` coin fully to sender (zero-value allowed); traders still pay.
