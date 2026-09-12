# BTEN deployment record

## Mainnet identities

- Coin type: `0x31c6c71184b08a574bd62fa8edd9a75aab9a986427484cf765a1890ce00aece0::bten::BTEN`
- Current package (v14): `0x9095d30a16f0d5e173e4539b38c7942dc2222e97f116b6f8e07c343a85349e49`
- Emission state: `0x22face12e4a73bc38171c5a2dd62a1cef8650bac3abc95eb5d3852ee36544253`
- Pool registry: `0xc78a803d7acc6e9740911802e382a45c347e0fb012613a908eb0738c4957d133`
- LP programme (finalized, active): `0x9e9fb23df5d54146a7ace1712cb8e4bcd1dd99dcec93c7f60f323d50d1a1acb0`
- First protocol-owned Cetus BTEN/SUI position: `0xd0c77b541d13b5eece8224dfcc78ecaa64b1f3b43f8df3c4367e1f0e2a786415`

## Automation model

The contract enforces emission, settlement eligibility, registry membership, minimum outputs, and reward accounting. It does not run itself: a public router, a permissionless settlement keeper, and a separately audited sponsor co-signer submit transactions when needed.

V14 was deployed in transaction `EPY8xhbhnkrMkCG3vdqpaSNdYFSc1G17rp3TfH9cHHnc`. It adds a narrow, paused direct-Cetus verifier with permanent digest/event replay protection, a 25-event daily cap, and public attestation events. The ten-pool registry was then frozen and verifier state created in `D2NAhbH27axXY2aibTe69UuWKvmarJd2ZMAr177AE7Sw`. The verifier capability is held only by the dedicated GitHub keeper; it has no upgrade, treasury, LP, mint, or registry authority. Configure the Block10 dapp from `config/block10_integration.json`, keep sponsorship disabled for the wallet-paid phase, and only then consider package immutability.
