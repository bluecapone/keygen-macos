---
name: secret-capture
description: Captures command output containing credentials without leaking the value into terminal output, transcripts, or agent logs. Use whenever a command emits a token, API key, password, certificate, private key, session credential, or freshly generated secret - including gh auth token, glab token create, gcloud auth print-access-token, aws iam create-access-key, op item get, vault read, kubectl get secret, security find-generic-password, and openssl rand. Use when a secret must be passed from one command to another, when the user asks to be shown a credential, when deciding whether an exposed value needs rotation, or when a value has already been printed and the blast radius needs assessing.
---

# Capturing secrets without leaking them

An agent session is a permanent, often-shared log. Anything a command prints to stdout or
stderr lands in that log. Assume every printed byte is exfiltrated: pasted into a ticket,
synced to a transcript store, replayed in a summary.

So the rule is not "be careful with secrets". It is: **the value never reaches stdout.**

## The pattern

Capture into a shell variable, use it, unset it. Prove success with metadata, never the value.

```bash
SECRET=$(gh auth token)
echo "Captured. Prefix: ${SECRET:0:4}... (length: ${#SECRET})"
# ... use "$SECRET" ...
unset SECRET
```

`${SECRET:0:4}` plus `${#SECRET}` is enough to confirm you got the right shape of thing without
disclosing it. Four characters is plenty - it distinguishes `ghp_` from `gho_` from an empty
string. Do not print more than 6.

Run capture and use **in the same command block**. A variable set in one shell invocation is
gone in the next, and re-running the emitting command doubles the exposure window.

## Command substitution strips the trailing newline, which is the point

`$(...)` removes trailing newlines, so a captured token is usable directly. Where a tool
insists on a file, use a process substitution or a locked-down temp file, never a plain
`> token.txt`:

```bash
# preferred - no file ever exists
some-tool --token-file <(printf '%s' "$SECRET")

# when the tool must have a real path
umask 077
TOKEN_FILE=$(mktemp "${TMPDIR:-/tmp}/tok.XXXXXX")
trap 'rm -f "$TOKEN_FILE"' EXIT
printf '%s' "$SECRET" > "$TOKEN_FILE"
some-tool --token-file "$TOKEN_FILE"
```

`umask 077` before `mktemp` matters: it makes the file `0600` at creation rather than
chmod-ing it a moment later.

## Never put a secret on a command line

Command-line arguments are visible to every process on the machine via `ps`. This leaks:

```bash
curl -H "Authorization: Bearer $SECRET" https://api.example.com   # BAD
```

Pass through stdin or an environment variable scoped to the single command instead:

```bash
# header from a file descriptor
curl -H @<(printf 'Authorization: Bearer %s' "$SECRET") https://api.example.com

# or scope the env var to just this process
SECRET="$SECRET" some-tool          # visible in `ps` output? no - env is not in ps args
```

For `curl` specifically, `--netrc-file` or `-H @file` both avoid argv. Confirm what your tool
supports before assuming.

## Keep it out of shell history

A leading space keeps a command out of history when `HISTCONTROL` includes `ignorespace`
(bash) or `HIST_IGNORE_SPACE` is set (zsh). Do not rely on it - prefer never typing the literal
value at all. If a secret did get typed:

```bash
# zsh
LC_ALL=C sed -i '' '/SECRET_SUBSTRING/d' "${HISTFILE:-$HOME/.zsh_history}"
# then start a fresh shell so the in-memory history is discarded too
```

## When the user asks to see the value

Do not print it. Hand back a command they run themselves, so the value renders in their
terminal and not in the shared log:

> Run this yourself to see it: `gh auth token | pbcopy` - it goes straight to your clipboard.

`pbcopy` is the best answer on macOS: the value reaches the clipboard without ever rendering.

## When the value is not re-readable

Some credentials are shown exactly once - GitLab PATs, AWS secret access keys, most OAuth
client secrets. If one of those has been lost or leaked, there is no "show it again". The only
correct move is a rotate-equivalent that produces a fresh value:

| Credential | Rotate with |
|---|---|
| GitLab PAT | `glab token create` (revoke the old one after) |
| AWS access key | `aws iam create-access-key` then `aws iam delete-access-key` |
| GitHub PAT | regenerate in Developer settings, or `gh auth refresh` for CLI scopes |
| Keychain item | overwrite with `security add-generic-password -U` |

Tell the user plainly that the old value is unrecoverable and rotation is the path. Do not
offer to "try to find it".

## If a secret has already been printed

Treat it as compromised. Do not reason about whether the log is private.

1. Rotate immediately - see the table above.
2. Revoke the old credential explicitly; creating a new one rarely invalidates the old.
3. Check what the credential could reach, and whether it was used between exposure and
   revocation. Provider audit logs are the source of truth here.
4. Only then clean the log, and treat cleanup as hygiene, not remediation.

Rotation is remediation. Deleting the message is not.

## Verifying a captured secret without echoing it

```bash
# non-empty?
[ -n "$SECRET" ] && echo "present (${#SECRET} chars)" || echo "EMPTY - capture failed"

# right shape?
printf '%s' "$SECRET" | grep -Eq '^gh[pousr]_[A-Za-z0-9]{16,}$' \
  && echo "looks like a GitHub token" || echo "unexpected format"

# checksum for comparing two values without revealing either
printf '%s' "$SECRET" | shasum -a 256 | cut -c1-12
```

That last one is genuinely useful: to check whether the secret in your Keychain matches the one
in CI, compare 12 hex characters of the SHA-256 of each. Equal digests mean equal secrets, and
the digest discloses nothing usable.

## Checklist

- [ ] value captured with `$(...)`, never printed
- [ ] confirmation is prefix + length only
- [ ] not passed as a command-line argument
- [ ] temp files created under `umask 077` with a `trap` cleanup
- [ ] `unset` after use
- [ ] user shown a copy-paste command instead of the value
- [ ] already-printed values rotated, not just deleted
