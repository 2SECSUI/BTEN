# V16 emission restore (shipped as Compatible v24)

See `V24_SCOPE.md`. This is a Compatible package upgrade that restores
`MIN_TRADES_PER_BLOCK=10`, `MAX_SETTLE_BLOCKS=100`, and trade-gated settle
from commit `2f18c31`, while retaining post-v16 modules (ManagedVault,
OpsBuyDesk, external attest, auto_pay u128).
