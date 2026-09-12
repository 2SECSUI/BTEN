# BTEN next-upgrade scope

The live package is V13. This document describes the next candidate upgrade;
none of the features below are live until separately tested, deployed, and
recorded in `Published.toml`.

## Verified direct-Cetus activity

Block10's protected adapters remain the canonical, trust-minimised route:
they create a BTEN receipt in the same transaction as the completed swap.

The optional direct-Cetus path will be intentionally different. An indexer
will read public Cetus `SwapEvent` records and may submit an attestation only
when all of the following are true:

- The event belongs to one of the finalized pool IDs in
  `MAINNET_ROUTE_CONFIG.json`.
- The event contains a BTEN leg and meets the published per-pool minimum.
- The `(transaction digest, event sequence)` pair has never been processed.
- The event and route detail are written to the public verifier log before a
  BTEN gate receipt is requested.
- The verifier is within a hard daily cap and is not paused.

The proposed on-chain state records processed digest/event pairs permanently.
It will accept attestations only from a narrowly scoped verifier capability;
that capability must have no upgrade, LP, treasury, mint, or registry power.
Because Sui Move cannot inspect an unrelated historical Cetus event directly,
this path has a trusted-indexer assumption and must never be described as
equivalent to the atomic adapter.

## Treasury execution

Before any automated external deposits are enabled, the package must use
explicit allowlists for the destination pool/farm/position IDs and enforce:

- a per-call amount cap;
- a rolling daily cap;
- atomic minimum-output protection for every swap;
- a fall back that leaves funds as BTEN LP support if the external action
  fails; and
- public execution events with the destination and amount.

The final Aftermath farm object and any external recipient must be supplied
and independently checked before this capability is built. No user wallet or
arbitrary destination is an eligible executor target.
