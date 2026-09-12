# BTEN final upgrade scope

This is the single release candidate scope. No item below is enabled until the
package upgrade, dry-runs, and small-value mainnet tests all succeed.

## Gate-qualified routes

- Direct, protected Cetus `asset <-> BTEN` adapters for every approved BTEN
  pool.
- No multi-hop route qualifies in this release. Every qualifying route is a
  direct BTEN-pair swap with a user minimum output and one receipt per
  completed transaction.

## Emission and allocation delivery

- 10 successful qualified routes release an eligible time slot.
- Delivery is queued per released block, is permissionless to process, and has
  per-allocation pause controls.
- Trader rewards remain point-weighted and automatic after round settlement.
- The 25% BTEN LP allocation and all five 1% venue allocations are redirected
  into the v9 LP programme, including their paused-vault backlog. Every BTEN
  is protocol-owned registered-pool liquidity, weighted by
  `config/lp_program_policy.json`; there is no separate LP-reward hold.
- Staking rewards use the native single-sided BTEN farm. Users stake BTEN
  principal and receive principal plus accrued mined rewards when withdrawing.
  The farm starts at its first stake so no historic allocation is claimable.

## Route treasury

- 15% sponsor reserve, 15% protocol-owned BTEN/SUI liquidity, 10% verified
  route rebates, 5% direct registered-BTEN-LP support, 5% safety buffer.
- The external-zap plan is retired: no USDC/SUI, DEEP/SUI, or WAL/SUI treasury
  positions are created by the current policy.
- Sponsor conversion has fixed pool, destination, per-refill, and daily caps.
- A failed strategy is never force-sold. After 1,000 released blocks, its
  unspent BTEN allocation is routed to the registered BTEN LP distributor.
- The separate 5% route-reserve LP-support share is 100% protocol-owned
  liquidity; it never funds external LP claims.

## Operational safeguards

- Treasury LP positions held by a dedicated custody/multisig owner.
- Protected quote, min-output, price-impact, tick-range, simulation, and
  receipt checks before every broadcast.
- Events and monitoring for gate release, allocation delivery, payouts, sponsor
  refill, route failure, fallback, pause, LP health, and farm funding.
- Global and per-strategy emergency pauses.

## Release gates

1. Move unit tests and package build pass.
2. Every direct transaction passes simulation.
3. Small-value mainnet test confirms receipts, output guards, and distribution.
4. Monitoring reports are clean over a full block interval.
5. Verification artifacts are regenerated for the final package.
6. The verification archive includes `assets/bten-logo.jpg`, and the metadata
   update uses `https://raw.githubusercontent.com/2SECSUI/BTEN/main/assets/bten-logo.jpg`.
7. Upgrade, enable strategies gradually, then make immutable only after review.
