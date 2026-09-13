# BTEN v17 scope

Target: mainnet package version 17. Live chain remains v16 until upgrade.

## Included

1. **Composable Cetus return adapters** with `ComposableRouteTicket`
   - `open_composable_route`
   - `cetus_swap_to_bten_return` / `cetus_swap_from_bten_return`
   - `cetus_swap_to_bten_b2a_return` / `cetus_swap_from_bten_a2b_return`
   - `seal_composable_route` — **one receipt per finished multi-hop route**
2. **Atomic via_bten + rebate entries** remain the fixed two-hop paths (already in v16 source).
3. **Block10 integration** — net-cheaper selection, composable entrypoints, sponsorship flags, managed vaults, Turbos plan (`config/block10_integration.json`).
4. **Gas sponsorship** — capped, allowlisted BTEN routes only (`config/sponsor_policy.json`), enabled for v17.
5. **External Cetus verifier** — already unpaused on-chain; Block10 config marked active.
6. **Managed rebalance vaults** — import pools, we rebalance, **2% of realized profits** (`config/managed_rebalance_policy.json`).
7. **Turbos adapters** — included in v17 plan (`config/turbos_adapter_plan.json`); Move flash-swaps land with vendored Turbos CLMM interface in the same upgrade bundle.

## Block10 (block10.grok.me)

Reads GitHub `main` configs. After merge/push, refresh the Grok dapp so it picks up the new contract.

## Publish checklist

- [ ] `sui move test` / build with `--dependencies-are-root`
- [x] Dry-run upgrade (V17_UPGRADE_DRY_RUN.md) — success, not executed
- [ ] Small-value mainnet proofs (single hop, composable seal, via_bten, rebate)
- [ ] Sponsor authorizer live with caps
- [x] Turbos interface vendored/adapters wired; [ ] at least one Turbos pool registered
- [ ] Verification zip + Published.toml version 17
- [ ] Push configs to `2SECSUI/BTEN` main for the live dapp

## Managed vaults (confirmed)

- **All Block10 / managed-vault transactions are BTEN-gated** (protected adapters or composable seal; no ungated shortcuts).
- **Imported pools share BTEN LP rewards** while enrolled (separate from the **2% realized-profit** fee to **ops wallets**).


