# BTEN deployment record

## Mainnet identities

- Coin type: `0x31c6c71184b08a574bd62fa8edd9a75aab9a986427484cf765a1890ce00aece0::bten::BTEN`
- Current package (v8): `0xfb4a37274bc784bc31cd03bbb6ab3e176d077ce22722ca2d7a9ba7f08f814042`
- Emission state: `0x22face12e4a73bc38171c5a2dd62a1cef8650bac3abc95eb5d3852ee36544253`
- Pool registry: `0xc78a803d7acc6e9740911802e382a45c347e0fb012613a908eb0738c4957d133`

## Automation model

The contract enforces emission, settlement eligibility, registry membership, minimum outputs, and reward accounting. It does not run itself: a public router, a permissionless settlement keeper, and a separately audited sponsor co-signer submit transactions when needed.

Before public activation: verify the v9 source, audit the Move package and executor paths, configure the Block10 dapp from `config/block10_integration.json`, keep sponsorship disabled for the wallet-paid phase, and only then consider package immutability.
