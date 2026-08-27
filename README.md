# keygen-macos

Agent skills for generating, handling, and auditing cryptographic keys and secrets on macOS.

Six skills, written to the open `SKILL.md` format, installable as one repo into Claude Code,
Codex, or any agent that reads markdown instructions.

## Why this repo exists

The rule these skills are built on: **move rules out of `CLAUDE.md` and into a skill.**

`CLAUDE.md` and `AGENTS.md` are always-on. Every line in them is context you pay for on every
single turn, whether or not the turn has anything to do with the topic. A skill is on-demand:
the agent reads a one-line description, and only loads the body when the description matches
what it is actually doing.

Secret handling is the textbook case. A detailed "never let a token reach stdout" policy is
critical maybe two percent of the time and dead weight the other ninety-eight. It belongs in
`skills/secret-capture/SKILL.md`, not in your always-on instructions.

So this repo is the refactor, applied: `AGENTS.md` here is four sentences that point at
`skills/`. Everything operational lives in a skill.

## Skills

| Skill | Fires when | Core surface |
|---|---|---|
| [`secret-capture`](skills/secret-capture/SKILL.md) | a command emits a token, key, password, or cert | capture-to-variable, prefix+length proof, rotation-instead-of-reveal |
| [`ssh-keygen-macos`](skills/ssh-keygen-macos/SKILL.md) | creating an SSH key, adding a second account, `permission denied (publickey)` | ed25519, `--apple-use-keychain`, `IdentitiesOnly`, `ed25519-sk` |
| [`git-commit-signing-macos`](skills/git-commit-signing-macos/SKILL.md) | commits show Unverified, enabling signing | SSH signing first, GPG only when required |
| [`keychain-secrets`](skills/keychain-secrets/SKILL.md) | storing or reading a credential for a script | `security` generic-password items |
| [`random-secrets`](skills/random-secrets/SKILL.md) | a new secret, password, or token is needed | `openssl rand`, encoding and length selection |
| [`key-inventory-audit`](skills/key-inventory-audit/SKILL.md) | auditing a laptop, offboarding, deciding what to rotate | metadata-only inventory across `~/.ssh`, git config, Keychain |

Every skill is scoped to macOS and every documented command was executed on macOS 26.6 with
Apple OpenSSH 10.3p1, OpenSSL 3.6.3, GnuPG 2.5.18, and git 2.53.0. See
[Verification](#verification).

## Install

### Claude Code plugin (recommended for teams)

One repo, installed once, available in every project:

```bash
/plugin marketplace add bluecapone/keygen-macos
/plugin install keygen-macos
```

### npx skills

```bash
npx skills add bluecapone/keygen-macos
```

### Manual symlink (any agent)

Clone once, symlink into whichever agent directories you use. This is the portable path -
`SKILL.md` is a plain markdown format, so anything that reads markdown instructions can
consume it.

```bash
git clone https://github.com/bluecapone/keygen-macos.git
cd keygen-macos
./scripts/install.sh              # links into ~/.claude/skills and ~/.agents/skills
./scripts/install.sh --project    # links into ./.agents/skills for a single repo
```

`install.sh` only ever creates symlinks and never overwrites a real directory.

## Verification

```bash
./scripts/check-skills.sh
```

The validator enforces the conventions this repo claims to follow, so a skill that drifts
fails CI rather than quietly rotting:

- frontmatter opens on line 1 and carries `name` and `description`
- `name` is lowercase-hyphen, 64 characters or fewer, and matches its directory
- `description` is third person, 1024 characters or fewer, and states *when* to fire
- body is 500 lines or fewer
- no credential-shaped strings anywhere in the tree

## Authoring conventions

[`docs/authoring-conventions.md`](docs/authoring-conventions.md) records the rules and why each
one exists, including the three-level progressive disclosure the `ssh-keygen-macos` skill
demonstrates by pushing multi-account detail into `references/`.

## Scope

These skills generate and manage **your own** cryptographic keys and credentials: SSH keys,
Git signing keys, Keychain items, and random secrets. Nothing here defeats, forges, or
bypasses anyone else's licensing, DRM, or authentication.

## License

MIT. See [LICENSE](LICENSE).
