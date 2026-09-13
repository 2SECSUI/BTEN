# BTEN v17 upgrade — EXECUTED

## Result

- **Status:** success
- **Tx:** 3TWJ7ch1DSUTCK65H3MrkdQV3xVpirdKzY4UaEcU3TP8
- **New package (v17):** 0x7239537d82dcf0643b653020d138a4fedff419391bc6f0d34e23dee0f5bd8b3e
- **Previous package (v16):** 0xc71c7ab810ba15ea337dc7722e8eaac4e3c7e631cf3557f70167783f1f3bcc41
- **UpgradeCap:** 0x97744b65d7241a102c68016bc568eab7552e1d72a1a0583a054b9dff51b2c10c (now version field 17)
- **Gas:** ~0.2075 SUI (207505340 MIST)
- **Checkpoint:** 322288471

## What shipped

- Composable Cetus return adapters + ComposableRouteTicket / seal_composable_route
- Turbos gated entry + composable return adapters (BUCKET_TURBOS)
- Existing via_bten / rebate paths retained

## Follow-ups

1. Small mainnet proofs (Cetus hop, composable seal; Turbos after pool registry)
2. Register at least one Turbos BTEN pool into PoolRegistry
3. Explorer verification zip if needed
4. Confirm Block10 dapp reads v17 package id from config/block10_integration.json


## Post-upgrade proofs

### Cetus gated SUI → BTEN (live)

- **Tx:** 2vD23DFGXoLsV2qyBfWMLFeTR8humxhmuZDGVEQhcBWw
- **Amount:** 0.002 SUI → ~0.0038 BTEN (est.)
- **Entry:** cetus_swap_to_bten_b2a on package v17
- **RouteRecorded:** yes

### Turbos

Blocked: PoolRegistry.finalized == true (11 pools). Adapters compile and are on-chain, but no new BUCKET_TURBOS registrations until registry policy is reopened in a later upgrade. No BTEN pool currently listed on Turbos public pool API.
