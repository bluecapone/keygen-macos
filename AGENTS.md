# AGENTS.md

This repo is a skills library for macOS key and secret handling. Operational rules live in
`skills/<name>/SKILL.md` and load on demand - do not restate them here.

Before editing or adding a skill, read `docs/authoring-conventions.md`, then run
`./scripts/check-skills.sh` and make it pass.

Never commit a real credential, key, fingerprint, or Keychain dump. Examples must be
synthetic. `check-skills.sh` scans for credential-shaped strings and will fail the tree.
