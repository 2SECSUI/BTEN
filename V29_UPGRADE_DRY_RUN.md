# BTEN v29 upgrade dry-run

- [x] Move tests 29/29 (permissionless WAL/SUI happy path + wrong-pool abort)
- [x] `sui client upgrade --dry-run` as ops
- [x] Status success; Estimated gas ~0.313 SUI
- [x] Compatible policy retained (no make_immutable)
- Design: WAL/SUI attest entrypoints are **Cap-free**; other pools stay Cap-gated
- Simulated modules `bten`, `ops_buy_desk` version 29
