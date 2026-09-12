# BTEN deployment record

## Mainnet identities

- Coin type: `0x31c6c71184b08a574bd62fa8edd9a75aab9a986427484cf765a1890ce00aece0::bten::BTEN`
- Current package (v15): `0x6d94dc303e9cff1f6ce26444e300b4b1f78dd93fb1d53ac2500051fb74c79230`
- Emission state: `0x22face12e4a73bc38171c5a2dd62a1cef8650bac3abc95eb5d3852ee36544253`
- Pool registry: `0xc78a803d7acc6e9740911802e382a45c347e0fb012613a908eb0738c4957d133`
- LP programme (finalized, active): `0x9e9fb23df5d54146a7ace1712cb8e4bcd1dd99dcec93c7f60f323d50d1a1acb0`
- Native BTEN staking farm: `0x49fcdc714509043ac3ead1ce1d4fbd72ab3f2060f60a50d1db7c5bc289ef4e58`

## Automation model

The contract enforces emission, settlement eligibility, registry membership, minimum outputs, and reward accounting. It does not run itself: a public router, a permissionless settlement keeper, and a separately audited sponsor co-signer submit transactions when needed.

V15 was deployed in transaction `99172L13dxrsm3UoJ8eXQQFEKWtKGftRKupZjDfJcai7`. It adds the native BTEN staking farm, which keeps user principal and mining rewards separate and receives only post-stake block allocations through the permissionless keeper sync. Configure Block10 from `config/block10_integration.json` and `config/bten_staking_farm.json`; sponsorship remains disabled for wallet-paid routes and the package remains upgradeable.
