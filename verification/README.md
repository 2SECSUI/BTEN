# BTEN V15 verification artifacts

`BTEN-mainnet-v15-verification.zip` is the public reproducibility bundle for
the deployed V15 package. It includes the source, compiled module, lockfile,
logo, and published-address data used by the repository build.

`BTEN-mainnet-v15-suiscan-source.zip` is the source-only submission bundle for
Suiscan. Its `Move.toml` resolves the Cetus interface through the immutable
Git dependency required by Suiscan rather than the repository's local build
override. Building either source configuration produces the same BTEN V15
module bytecode:

`C1C218A0386C170B3E8B3A7E1AB1EB77F0F34171184D1C9C4535959223658A79`

Neither archive contains a private key, capability, sponsor credential, or
runtime ledger.
