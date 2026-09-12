# BTEN v9 launch runbook

This branch is a release candidate, not a deployment instruction. No key,
capability, LP position, or treasury balance is stored in GitHub.

## Contract setup

1. Build and independently review the Move package using the pinned Cetus
   interface. Use `--dependencies-are-root` only on the publish/upgrade command
   when supported by the installed Sui CLI.
2. Upgrade the current package; record the new package ID and digest in
   `Published.toml` and `verification/manifest.json`.
3. Create `LpProgramState` with the dedicated treasury-operator address,
   register each pool from `config/lp_program_policy.json`, finalize weights,
   and leave it paused.
4. Create the paused `KeeperConfig` for the funded GitHub keeper. Do not give
   it `RegistryAdminCap`, `UpgradeCap`, `LpProgramCap`, farm ownership, or LP
   positions.
5. Run a protected quote and low-value add-liquidity simulation for each
   registered pool. Execute only when the live quote, tick range, and paired
   asset requirement are satisfied.

## Activation sequence

1. Keep sponsorship disabled and use wallet-paid routes.
2. Run one protected direct route per enabled BTEN pair and confirm one receipt
   and one gate increment per successful transaction.
3. At ten eligible receipts, settle a single block; then call
   `accrue_lp_program` to move the 25% LP plus five 1% venue balances,
   including their historical backlog, into the 70/30 programme.
4. Use `accrue_route_lp_support_to_program` only after route-treasury syncing;
   it moves only the accounted LP-support share into protocol liquidity.
5. Use every programme balance only for protocol-owned liquidity in the
   registered pool set. Create the native BTEN staking farm, then let its
   permissionless sync move only newly released staking allocations.

## Verification and monitoring

- Run `npm run validate-launch` before publishing configuration.
- Create the verification archive from the exact built package, include the
  logo, Move sources, lock file, and manifest hashes, then submit that exact
  archive to Suiscan after the upgrade digest is known.
- Monitor gate receipts, released height, LP programme balances, Cetus funding
  events, native-farm stake/reward balances, route-treasury balances, sponsor cap,
  and emergency pauses.
- Do not make the package immutable until all enabled executors have passed
  independent review and live low-value tests.
