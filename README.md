# BTEN / BlockTen

This repository is the public source and verification record for BlockTen (BTEN) on Sui mainnet.

## Mainnet

- Coin: `0x31c6c71184b08a574bd62fa8edd9a75aab9a986427484cf765a1890ce00aece0::bten::BTEN`
- Package: `0x5a15d97c6466448b0e4960c8f0a61e7a2d9d8cc9397542fe26ceacad3cf066f0`
- Supply cap: 21,000,000 BTEN, eight decimals
- Initial subsidy: 50 BTEN, with a 10-route receipt gate per released block

## Verification

`verification/BTEN-mainnet-v6-verification.zip` contains the package manifest, lockfile, published package record, Move source, and compiled `bten.mv` bytecode. The SHA-256 and exact package identity are in `verification/manifest.json`.

Build locally after initializing submodules:

```powershell
git submodule update --init --recursive
sui move test
sui move build
```

## Public operations records

`MAINNET_ROUTE_CONFIG.json` lists the public pool and contract identities. `monitoring/` contains the public status schema used by the future site.

This public repository intentionally excludes wallet keys, recovery data, sponsor credentials, local runtime ledgers, private signing services, and operational execution scripts.
