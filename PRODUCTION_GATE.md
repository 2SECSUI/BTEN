# BTEN mainnet release gate

The mainnet package is upgradeable. Run `node scripts/preflight_mainnet.mjs`
before any final immutability decision. It must pass only after all of the
following are true:

1. The legacy `RouterCap` receipt path remains disabled; only atomic adapters
   may create route receipts.
2. Cetus and Turbos atomic adapter functions are present and use a minimum
   output supplied by the user transaction.
3. Mainnet/testnet evidence covers: both pool creations, both directions of a swap,
   a routed reward receipt, automatic trader payment, a failed slippage test,
   and a failed unapproved-route test.
4. An independent audit has been completed and recorded in `AUDIT.md`.
5. `mainnet-release.json` fixes the chosen package, pool IDs, allocation, fee
   cap, sponsor wallet policy, and the 2.5 SUI per BTEN/SUI venue budget.

The proposed mainnet liquidity budget must be reviewed immediately before the
transaction. It is not encoded into the contract and no spending occurs from
this gate.
