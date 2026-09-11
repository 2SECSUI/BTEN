# BTEN deployment record

## Mainnet identities

- Coin type: `0x31c6c71184b08a574bd62fa8edd9a75aab9a986427484cf765a1890ce00aece0::bten::BTEN`
- Package: `0x5a15d97c6466448b0e4960c8f0a61e7a2d9d8cc9397542fe26ceacad3cf066f0`
- Emission state: `0x22face12e4a73bc38171c5a2dd62a1cef8650bac3abc95eb5d3852ee36544253`
- Pool registry: `0xc78a803d7acc6e9740911802e382a45c347e0fb012613a908eb0738c4957d133`

## Automation model

The contract enforces emission, settlement eligibility, registry membership, minimum outputs, and reward accounting. It does not run itself: a public router, a permissionless settlement keeper, and a separately audited sponsor co-signer submit transactions when needed.

Before public activation: verify source, audit the Move package and sponsor service, deploy the public UI, enable sponsorship at the seed cap, and only then consider package immutability.
