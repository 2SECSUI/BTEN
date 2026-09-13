# BTEN v18 scope

Target: mainnet package after live v17.

## Managed vaults (user-facing on block10.grok.me)

Users on **https://block10.grok.me**:
1. Connect wallet and **import any Cetus LP Position** (any pool/pair).
2. Set **parameters**: max deviation bps, slippage bps, recenter, allow OOR close (+ cost basis for fee accounting).
3. **Add / remove anytime** (`enroll_cetus_position` / `withdraw_enrolled_position`), or settle exit after a close with **2% fee on realized profit** above basis.
4. Update parameters anytime via `update_enrollment_params` without withdrawing.

BTEN operator rebalances enrolled positions using those params; fee goes to ops wallets only.

## Also in v18 (related)

- `register_additional_pool` for Turbos/Bluefin/Haedal after finalize (optional same upgrade).

## Not blocking UX

- Full operator daemon extension for enrolled positions can ship after vault object is live.
- Managed-vault UI on the dapp reads `config/managed_rebalance_policy.json` + entrypoints from `block10_integration.json`.
