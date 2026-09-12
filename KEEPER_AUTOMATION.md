# BTEN GitHub keeper

The keeper is the dedicated address `0xd833a2ffe167e0bd56205b6b4e4a4bd78e035ff899a788fc892b5be713b76474`.
It is funded with 4 SUI for operational gas only. It owns no package upgrade
capability, registry administration capability, farm capability, LP position,
or treasury asset.

## GitHub configuration

Create the `mainnet-automation` Actions environment in `2SECSUI/BTEN`, limit
deployment branches to `main`, then create its secret named
`BTEN_KEEPER_PRIVATE_KEY`. The secret value must be the Sui private-key string
for the keeper address above. Do not put a key in repository variables, files,
issues, logs, the Block10 dapp, or a pull request.

The workflow runs every ten minutes and may only call the permissionless
`settle_and_distribute` and `sync_route_treasury` functions. It is serialized
to prevent duplicate submissions. Scheduled and manually dispatched runs are
blocked outside `main`; pull requests receive no secret.

## Explicit limits

This keeper cannot run sponsor, swap, zap, LP distribution, farm funding, or
upgrade paths. Enabling those requires a separately audited on-chain delegated
keeper capability with fixed allowlists and caps. Until that release, those
treasury balances remain accounted for on-chain and untouched.
