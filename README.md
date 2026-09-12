# BTEN / BlockTen development package

This is the source package for the deployed BTEN routing-token concept.

## DApp

Use the public BlockTen interface at [block10.grok.me](https://block10.grok.me/).
The public source and verification materials are published through the
[BTEN GitHub repository](https://github.com/2SECSUI/BTEN).

The public machine-readable integration contract for Block10 is
[`config/block10_integration.json`](config/block10_integration.json). It has
only public package/state IDs and adapter entrypoints; it never contains a
wallet secret, capability, or sponsor key. The v9 LP programme policy and pool
weights are in [`config/lp_program_policy.json`](config/lp_program_policy.json).
Run `npm run validate-launch` before consuming either file.

## Implemented core

- 21,000,000 BTEN hard cap with eight decimals.
- A 50 BTEN genesis block at height zero, then a 50 BTEN initial subsidy that
  halves every 210,000 released heights.
- Ten-minute slots accumulate as pending blocks.
- A settlement requires 10 qualifying route receipts for every block released.
- Surplus trades do not pre-unlock future blocks; each settlement closes its batch.
- Fixed allocation: 50% route/gas vault, 10% traders, 25% BTEN LPs, 10% stakers, 1% each to Cetus, Blue, Turbos, and Haedal LP buckets, plus 1% to a SUI gas reserve.
- Setup-time pool registry for exact live pool IDs.
- The planned 10 SUI BTEN/SUI bootstrap pool is route liquidity, not the gas
  sponsor balance. The separate 1% SUI gas reserve funds sponsored gas.
- Sealed per-round trader points and permissionless keeper-paid trader payouts;
  users do not need to redeem their rewards themselves.
- Atomic Cetus adapters for both live pool orderings. They enforce an approved
  registry entry, exact Cetus flash-swap repayment, and a caller minimum output
  before recording a route receipt. The legacy RouterCap receipt function is
  retained only for ABI compatibility and always aborts.

## Current mainnet adapter status

Mainnet package version 9 is upgradeable at
`0x2bd9a906dd086696ca0e943401894b8d636c4efd19b518eba4e402e3d55375f0`.
It was deployed in transaction `8uzMxePBEGuAKQzHqjPfwicdNWZxXRxKS5G2jmbD5vMi`.
V9 adds an allowlisted LP programme; moving funds into a venue still requires
the matching protocol-owned LP transaction and paired asset.

Run the non-signing route check with:

```powershell
node .\scripts\dry_run_cetus_adapter.mjs
```

`--execute` performs a live proof and should be used deliberately. See
[`V9_LAUNCH_RUNBOOK.md`](V9_LAUNCH_RUNBOOK.md) for the staged release process.

Run local tests with:

```powershell
Set-Location .\bten
sui move test
```

## Testnet route probe

After a testnet BTEN coin is deployed, use the quote-only probe to see whether
the Cetus aggregator can find a route. It does not access a keystore or submit
a transaction:

```powershell
node .\scripts\quote_route.mjs --network testnet --from 0x2::sui::SUI --to <BTEN_COIN_TYPE> --amount-raw 100000000 --decimals-out 8
```

For direct Turbos pool discovery and a safe quote, use:

```powershell
node .\scripts\quote_turbos_route.mjs --network testnet --from 0x2::sui::SUI --to <BTEN_COIN_TYPE> --amount-raw 100000000
```

The supplied brand asset is at `assets/bten-logo.jpg`; the lightweight testnet
status page is `site/index.html`.

Do not make the package immutable until all remaining adapters and an
independent audit are complete.

The planned initial route pairs are BTEN/SUI and BTEN/WAL on both Cetus and
Turbos. Each venue's 2.5 SUI budget is split evenly: 1.25 SUI to BTEN/SUI and
1.25 SUI-equivalent to BTEN/WAL. See `POOL_PLAN.json` for the non-executable
liquidity plan.

`scripts/route_policy.mjs` is the deterministic eligibility check used by the
future route adapters: a path earns BTEN rewards only when it includes BTEN
and improves the trader's net output over the direct route.

`scripts/sponsor_policy.mjs` is the matching pure guard for the future SUI gas
sponsor. It enforces eligibility plus per-swap and daily SUI caps before a
signing service is ever asked to sponsor a transaction.

## Launch operations update

- `scripts/public_route_selector.mjs` selects the BTEN two-leg route only when
  its net output is at least 1 bp better than the direct route. Both routes
  must supply output-denominated costs; the selector never invents a gas-price
  conversion for a non-SUI token.
- `config/lp_eligibility.json` is the 10,000-bps LP incentive manifest. It
  includes only registered, adapter-tested pools and excludes vSUI plus
  out-of-range-only positions. `scripts/lp_rewards_plan.mjs --reward-raw <n>`
  creates a read-only allocation plan. Actual LP rewards remain gated on an
  in-range position indexer and farm activation.
- `scripts/sponsor_authorizer.mjs` is the whitelist and cap gate for the
  sponsor signer. It accepts only a structured attestation for a protected,
  registered BTEN route; it does not accept transaction bytes or expose a key.
  Sponsorship is deliberately still disabled until an independently reviewed
  co-signing service is deployed.
- `scripts/bten_monitor.mjs` reads mainnet state and the sponsor wallet. It
  alerts on an insufficient sponsor balance, pending block/receipt state and
  unexpected sponsorship activation. It never signs or submits a transaction.

`MAINNET_ROUTE_CONFIG.json` is the prepared, inactive mainnet route manifest.
It contains only the verified BTEN contract IDs and approved Cetus/Turbos
venues; it intentionally has no pools, genesis release, sponsor, or keeper
enabled.
## Public assets and supply policy

Official public assets for BlockTen (BTEN).

## Supply policy

- Maximum supply: 21,000,000 BTEN
- Decimals: 8
- Genesis block: 50 BTEN at height zero
- Normal block subsidy: 50 BTEN, trade-gated by ten-minute slots
- Halving: every 210,000 released heights

The currently deployed mainnet package is upgradeable and has zero circulating
supply. Genesis, liquidity, and public routing remain inactive until the final
atomic-routing implementation is ready.

Logo URL for coin metadata:

`https://raw.githubusercontent.com/2SECSUI/BTEN/main/assets/bten-logo.jpg`
