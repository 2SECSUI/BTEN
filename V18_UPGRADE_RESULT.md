# BTEN v18 upgrade — EXECUTED

## Result

- **Status:** success
- **Tx:** 3gBGpjAa9hxJGpSo8mcSAwjr5hTyrBDXzmgkuWtRSQDR
- **New package (v18):** 0x57be4e19af4806285d00fb199f6221e0446c585dacb0593ee1e646de1a8d4098
- **Previous package (v17):** 0x7239537d82dcf0643b653020d138a4fedff419391bc6f0d34e23dee0f5bd8b3e
- **UpgradeCap:** 0x97744b65d7241a102c68016bc568eab7552e1d72a1a0583a054b9dff51b2c10c
- **UpgradeCap owner:** 0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a
- **UpgradeCap policy:** Compatible (0) — **still upgradeable**
- **UpgradeCap package version field:** 18
- **Gas:** ~0.2366 SUI (236576940 MIST)
- **No** `make_immutable` / `destroy` / immutable policy. authorize_upgrade used policy `0`.

## ManagedVault (created)

- **Tx:** 5LsU2Wkxe42hQp11wQK8BmoTNVXshek9rEQFcJukvx1A
- **ManagedVaultState (shared):** 0xf0b602704c571f73f77b478c58cf6b35ce4725650fde6524b631b6f15c03bd76
- **ManagedVaultOperatorCap (ops):** 0x828200e82d6448255fb6bb83e42dcff88b53f87039dfc0bbf19b88658cc8c58b
- **RegistryAdminCap used:** 0x950ef4d2afc672d684e54e39204b6d7f328d76f47590da73463f525e531973e9
- **ops_wallet:** 0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a
- **paused:** false

## External verifier

- State 0x32206a1e910973b54b1225969365f58601399d3611a712e3644ab52c334b26f3
- **paused=false** (confirmed on-chain after upgrade)

## What shipped

- ManagedVault (create / enroll / update / withdraw / operator take-return / settle exit)
- `register_additional_pool` post-finalize venue registration
- Live-tape rule: treat all shown volume as gated; do not block txs
- Verifier digest-key normalization + live package event types (already in source)

## Configs enabled (dapp reads GitHub main)

- `treatAllLiveTapeAsGated: true`, `blockTransactions: false`
- managedRebalance **live** with object IDs
- externalCetusVerifier **enabled/active**, paused false
- register_additional_pool / turbos plans **ready-for-use** (Turbos `enabled` stays false until a pool is registered)
- magma/bluefin: registration path ready-for-use; native CLMM adapters still plan-only (no vendor interfaces)
- sponsorship **enabled** (`v18-enabled-capped`); feeSubsidy left **false** (needs dedicated SUI sponsor budget / FeeSubsidyState)

## Follow-ups

1. Register a Turbos BTEN pool via `register_additional_pool` (bucket=3) when a pool exists
2. Optional: verifier `--execute` only if `BTEN_KEEPER_PRIVATE_KEY` is already in env
3. Block10 dapp refresh against GitHub main configs
