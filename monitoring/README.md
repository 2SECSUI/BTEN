# BTEN monitoring records

This directory holds only public, reviewable operational records for BTEN.

- `schema.json` defines the public status shape.
- `latest.template.json` is the checked-in starting point for a manually reviewed status snapshot.
- `live/` is ignored because it may contain operational timestamps, local endpoint details, or incomplete data.

Never store recovery phrases, private keys, sponsor tokens, local keystores, or wallet-level transaction payloads here. The public site can read a reviewed `latest.json` after launch.
