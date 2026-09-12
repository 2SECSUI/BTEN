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
The native BTEN staking-farm integration is in
[`config/bten_staking_farm.json`](config/bten_staking_farm.json); it is enabled
only after the package upgrade and farm-creation transaction are confirmed.
Run `npm run validate-launch` before consuming either file.

### Live mainnet data for Block10

The current package is v15 at
`0x6d94dc303e9cff1f6ce26444e300b4b1f78dd93fb1d53ac2500051fb74c79230`.
Grok should consume `config/block10_integration.json` first, then
`MAINNET_ROUTE_CONFIG.json` for the exact ten finalized Cetus pool IDs,
their BTEN-only adjacent-price position IDs, and the allocation status.
CERT is intentionally absent from that public pool list and is not in the
on-chain LP allowlist. These files contain only public chain data; they never
contain a private key, capability, or sponsor credential.

The direct-Cetus verifier is connected to a public, read-only pool-event
reader. It accepts at
most one fixed-point receipt per successful transaction on a frozen BTEN Cetus
pool, never treats a protected BTEN adapter route as a second receipt, and is
bounded by the on-chain daily cap. Its separate future treasury-executor work
is documented in [`docs/NEXT_UPGRADE_SCOPE.md`](docs/NEXT_UPGRADE_SCOPE.md).

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

Mainnet package version 15 is upgradeable at
`0x6d94dc303e9cff1f6ce26444e300b4b1f78dd93fb1d53ac2500051fb74c79230`.
It was upgraded in transaction `99172L13dxrsm3UoJ8eXQQFEKWtKGftRKupZjDfJcai7`.
V15 adds the native single-sided BTEN staking farm alongside the allowlisted
one-sided LP executors for both Cetus token orderings.
They create BTEN-only positions immediately outside the current price and
abort atomically if any paired asset would be required.

Block10 should compare a direct Cetus quote with its BTEN route and present the
BTEN route only when its final net output is higher. This prevents a subsidised
or lower-fee route from being selected when price impact would make it worse.

The next reviewed upgrade adds atomic SUI-to-asset paths through BTEN for both
Cetus pool type orderings. They complete `SUI -> BTEN -> asset` in one
transaction, enforce the final asset minimum output, and record one receipt
only after both flash-swap repayments succeed. The public route-choice rule is
implemented in [`scripts/public_route_selector.mjs`](scripts/public_route_selector.mjs):
direct output remains the default unless the BTEN path is net-better by the
configured threshold.

`config/route_rebate_policy.json` defines the optional, disclosed route-rebate
limits. It can draw only from the route treasury's separately accrued rebate
allocation; it cannot use LP, staking, trader, sponsor, protocol-liquidity, or
safety funds. A payout executor is intentionally not live until it can convert
the capped BTEN rebate into the trader's final output token atomically.

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

`MAINNET_ROUTE_CONFIG.json` is the live public mainnet route and liquidity
manifest. It contains the verified BTEN contract IDs, ten finalized
allowlisted Cetus pools, and the V13 position records. It does not expose a
sponsor key or grant any wallet permission.
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
