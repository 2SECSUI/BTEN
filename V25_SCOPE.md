# BTEN v25 scope

Add admin `unregister_pool` so finalized PoolRegistry entries can be removed
(table::remove). Used to drop bleed / unused Cetus BTEN pools:

- BTEN/USDT
- BTEN/USDC
- BTEN/DEEP
- BTEN/NS

Compatible UpgradeCap retained (never make_immutable). Close any remaining ops
Cetus LPs on those pools before unregister.
