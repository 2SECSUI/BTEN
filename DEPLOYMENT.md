# BTEN deployment record

## Mainnet identities

- Coin type: `0x31c6c71184b08a574bd62fa8edd9a75aab9a986427484cf765a1890ce00aece0::bten::BTEN`
- Current package (v9): `0x2bd9a906dd086696ca0e943401894b8d636c4efd19b518eba4e402e3d55375f0`
- Emission state: `0x22face12e4a73bc38171c5a2dd62a1cef8650bac3abc95eb5d3852ee36544253`
- Pool registry: `0xc78a803d7acc6e9740911802e382a45c347e0fb012613a908eb0738c4957d133`
- LP programme (finalized, active): `0x9e9fb23df5d54146a7ace1712cb8e4bcd1dd99dcec93c7f60f323d50d1a1acb0`

## Automation model

The contract enforces emission, settlement eligibility, registry membership, minimum outputs, and reward accounting. It does not run itself: a public router, a permissionless settlement keeper, and a separately audited sponsor co-signer submit transactions when needed.

V9 was deployed in transaction `8uzMxePBEGuAKQzHqjPfwicdNWZxXRxKS5G2jmbD5vMi` with verified dependencies. The LP programme was created and finalized in `CwYCyR6QrGXmqFckXdJkQfxKHdQ7tqpG78RByaJcgfFQ` and `7WHWwJycSpYp4iAHT5Fu1RV5uU7EZNs6GPn2JDs7AU3o`. Configure the Block10 dapp from `config/block10_integration.json`, keep sponsorship disabled for the wallet-paid phase, and only then consider package immutability.
