---
name: key-inventory-audit
description: Inventories every SSH key, Git signing key, GPG key, and Keychain credential on a macOS machine and reports weak, stale, unprotected, duplicated, mislabeled, or orphaned entries without printing any secret value. Use when auditing a developer laptop, preparing for or completing offboarding, deciding which keys to rotate or delete, hunting legacy RSA keys, finding private keys that have no passphrase, checking file permissions on ~/.ssh, or answering "what keys do I have" and "which of these can I safely remove". Reports metadata only - fingerprints, key types, bit sizes, comments, dates, and permissions.
---

# Auditing keys and secrets on macOS

Run the inventory, then triage. Every command here reads **metadata only** - no private key
material and no secret values are ever printed. That is deliberate: an audit that dumps secrets
into a log is a bigger problem than the drift it found.

## 1. SSH key inventory

```bash
for pub in ~/.ssh/*.pub; do
  [ -f "$pub" ] || continue
  ssh-keygen -lf "$pub"
done
```

Output is `<bits> SHA256:<fingerprint> <comment> (<TYPE>)`.

Read it for three things:

- **Type.** `ED25519` is current. `RSA` is legacy - fine at 4096, replace at 2048.
- **Comment.** Should say what the key is for. A placeholder like `your_email@example.com`,
  `seu_email@example.com`, or a hostname from a machine you no longer own means the key was made
  by pasting a tutorial and nobody has audited it since.
- **Count.** More than about five keys on one laptop usually means old keys were never removed.

## 2. Private keys with no passphrase

The highest-value check in this skill. An unprotected private key is a plaintext credential.

```bash
for key in ~/.ssh/*; do
  case "$key" in *.pub|*known_hosts*|*authorized_keys|*config) continue ;; esac
  [ -f "$key" ] || continue
  head -1 "$key" | grep -q 'PRIVATE KEY' || continue
  if ssh-keygen -y -P '' -f "$key" >/dev/null 2>&1; then
    echo "NO PASSPHRASE: $key"
  else
    echo "protected:    $key"
  fi
done
```

`ssh-keygen -y` derives the public key from the private one. With `-P ''` it succeeds only when
the key has an empty passphrase. Output is discarded, so nothing sensitive is printed.

Anything reported as `NO PASSPHRASE` should be given one immediately, without regenerating:

```bash
ssh-keygen -p -f ~/.ssh/id_ed25519_example
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_example
```

`-p` changes the passphrase in place, so the public key and every server that trusts it are
unaffected.

## 3. Permissions

```bash
find ~/.ssh -maxdepth 1 -type f -print0 | while IFS= read -r -d '' f; do
  perm=$(stat -f '%Lp' "$f")
  case "$f" in
    *.pub) want=644 ;;
    *)     want=600 ;;
  esac
  [ "$perm" = "$want" ] && continue
  echo "PERMS $perm (want $want): $f"
done
stat -f '%Lp %N' ~/.ssh
```

`stat -f '%Lp'` is the BSD/macOS form. GNU `stat -c '%a'` does not exist here. `~/.ssh` itself
should be `700`.

## 4. Orphans and duplicates

```bash
# private keys with no matching .pub
for key in ~/.ssh/*; do
  case "$key" in *.pub|*known_hosts*|*authorized_keys|*config) continue ;; esac
  [ -f "$key" ] || continue
  head -1 "$key" | grep -q 'PRIVATE KEY' || continue
  [ -f "$key.pub" ] || echo "no .pub for: $key"
done

# .pub with no private half - safe to delete, but tells you a key was moved or lost
for pub in ~/.ssh/*.pub; do
  [ -f "$pub" ] || continue
  [ -f "${pub%.pub}" ] || echo "orphan public key: $pub"
done

# duplicate key material under different filenames
for pub in ~/.ssh/*.pub; do
  [ -f "$pub" ] || continue
  ssh-keygen -lf "$pub" | awk '{print $2}'
done | sort | uniq -d
```

A repeated fingerprint means the same key exists twice. Keep one.

## 5. What the agent is holding

```bash
ssh-add -l
```

Fingerprints only. Cross-reference against section 1 - a fingerprint in the agent that is not on
disk came from a Keychain-stored key whose file was deleted, or from an external agent.

Stored passphrases live in the login Keychain as generic passwords with service `SSH:`:

```bash
security dump-keychain 2>/dev/null \
  | awk -F'"' '/"svce"<blob>="SSH: /{print $4}' | sort -u
```

## 6. Git signing configuration

```bash
git config --global --get-regexp '^(gpg|commit\.gpgsign|tag\.gpgsign|user\.(email|signingkey))'
```

Check that:

- `user.signingkey` under `gpg.format ssh` points at a `.pub` that still exists
- `gpg.ssh.allowedSignersFile` is set, and the file it names exists
- `commit.gpgsign` is `true` if you believe you are signing

```bash
sf=$(git config --global --get gpg.ssh.allowedSignersFile)
[ -n "$sf" ] && [ -f "${sf/#\~/$HOME}" ] && echo "allowed_signers present" || echo "allowed_signers MISSING"
```

## 7. GPG keys and expiry

```bash
gpg --list-secret-keys --with-colons 2>/dev/null \
  | awk -F: '$1=="sec"{printf "%s %s %s %s %s\n", $5, $3, $4, $6, ($7==""?"none":$7)}' \
  | while read -r keyid bits algo created expires; do
      c=$(date -r "$created" +%Y-%m-%d 2>/dev/null || echo '?')
      if [ "$expires" = none ]; then
        e=never
      else
        e=$(date -r "$expires" +%Y-%m-%d 2>/dev/null || echo '?')
        [ "$expires" -lt "$(date +%s)" ] && e="$e EXPIRED"
      fi
      printf 'keyid=%s bits=%s algo=%s created=%s expires=%s\n' "$keyid" "$bits" "$algo" "$c" "$e"
    done
```

Do **not** reach for `awk`'s `strftime` here. macOS ships BWK awk (`awk version 20200816`), which
has no `strftime` - it fails with `calling undefined function strftime`. That function is a gawk
extension. `date -r <epoch>` is the BSD equivalent and is what the loop above uses.

Field 3 is the key length, 4 the algorithm, 6 the creation timestamp, and 7 the expiry timestamp,
empty when the key never expires. Expired keys still appear in this listing, which is why the loop
compares against `date +%s` and tags them. Extend rather than replace when a key is still trusted:

```bash
gpg --quick-set-expire <FINGERPRINT> 2y
```

## 8. Inbound access

```bash
# who can log into THIS machine
[ -f ~/.ssh/authorized_keys ] && ssh-keygen -lf ~/.ssh/authorized_keys
# how many hosts this machine has talked to
wc -l < ~/.ssh/known_hosts 2>/dev/null
```

`authorized_keys` is the one people forget. Every line is a key that can log in as you. On a
laptop that never accepts inbound SSH, the correct content is usually no file at all.

## Triage rules

Delete or rotate, in this order:

1. **No passphrase** - add one now (section 2). Never leave this.
2. **RSA 2048 or smaller** - rotate to ed25519.
3. **Placeholder or tutorial comment** - you do not know what trusts this key. Rotate it and
   re-register deliberately.
4. **Orphan public keys** - delete the file.
5. **Duplicate fingerprints** - keep one filename, delete the rest.
6. **Keys older than your rotation window** with no known consumer - remove the public key from
   providers first, confirm nothing breaks, then delete locally.
7. **`authorized_keys` entries you cannot attribute** - remove them.

Removing a private key locally does **not** revoke access. The public key registered with GitHub,
GitLab, or a server is what grants it. Always remove from the provider first, verify, then delete
locally. Full rotation sequence is in `ssh-keygen-macos`.

## Reporting

Report fingerprints, types, sizes, comments, dates, and paths. Never report private key
contents, passphrases, or Keychain values, and never run `security dump-keychain -d`. If an audit
needs to prove two secrets match, compare truncated SHA-256 digests instead - see
`secret-capture`.

## Checklist

- [ ] every private key has a passphrase
- [ ] no RSA key under 3072 bits remains in use
- [ ] every key comment states its purpose
- [ ] `~/.ssh` is `700`, private keys `600`, public keys `644`
- [ ] no orphan or duplicate keys
- [ ] agent contents match on-disk keys
- [ ] signing config points at files that exist
- [ ] no GPG key silently expired
- [ ] `authorized_keys` is empty or fully attributed
- [ ] no secret value appears anywhere in the report
