---
name: ssh-keygen-macos
description: Generates and configures SSH keys on macOS, covering ed25519 key creation, passphrase storage in the login Keychain via ssh-add --apple-use-keychain, per-host ~/.ssh/config entries with IdentitiesOnly, hardware-backed ed25519-sk keys, file permissions, fingerprint verification, and rotation. Use when creating a new SSH key, adding a second key for a separate GitHub or GitLab account, fixing "Permission denied (publickey)" or pushes landing on the wrong account, stopping a passphrase prompt on every reboot, replacing a legacy RSA key, or deciding what comment and filename a key should use.
---

# SSH keys on macOS

## Generate

```bash
ssh-keygen -t ed25519 -C "github-personal 2026-08" -f ~/.ssh/id_ed25519_github_personal
```

- `-t ed25519` - small, fast, and the modern default. Use `rsa -b 4096` only when a server
  genuinely refuses ed25519.
- `-f` with a purpose-specific filename. One key per purpose, never one key everywhere. When a
  key leaks you revoke one relationship, not all of them.
- `-C` is a free-text label. Make it **purpose plus date**, not an email address. The email adds
  nothing you cannot get from the filename, and a stale placeholder like
  `your_email@example.com` is the tell that a key was made by pasting a tutorial. The date tells
  you at a glance what is old enough to rotate.

Always set a passphrase. The Keychain step below means you type it once, ever.

## Store the passphrase in the login Keychain

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_github_personal
```

`--apple-use-keychain` is the current flag; `-K` is the deprecated alias that still works. This
loads the key into the agent *and* saves the passphrase to the login Keychain, so it survives
reboots.

Verify what the agent holds - this prints fingerprints, never key material:

```bash
ssh-add -l
```

## Configure `~/.ssh/config`

```
Host github-personal
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github_personal
  IdentitiesOnly yes
  IgnoreUnknown UseKeychain
  AddKeysToAgent yes
  UseKeychain yes
```

Then `git remote set-url origin git@github-personal:you/repo.git`.

Three of those lines carry real weight:

**`IdentitiesOnly yes`** is the one that fixes "it pushed to the wrong account". Without it, ssh
offers every key it knows about, the server accepts the first one that authenticates, and you
silently act as whichever identity that key belongs to. With it, only the `IdentityFile` for
this host is offered.

**`IgnoreUnknown UseKeychain`** makes the config portable. `UseKeychain` is an Apple addition to
OpenSSH. Apple's `/usr/bin/ssh` accepts it; a Homebrew or Linux OpenSSH treats it as a fatal
config error and every ssh command in that shell dies. `IgnoreUnknown` downgrades the unknown
keyword to a no-op. Put it **before** `UseKeychain` - directives are processed in order.

**`AddKeysToAgent yes`** loads the key on first use instead of requiring a manual `ssh-add`.

Note that `ssh -G <host>` does not echo `usekeychain` even when it is accepted, so its absence
from that output is not evidence of a problem. To prove a keyword is accepted, check the exit
status: an unknown keyword exits 255 with `Bad configuration option`.

## Permissions

OpenSSH refuses to use keys with loose permissions.

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519_*        # private keys
chmod 644 ~/.ssh/id_ed25519_*.pub    # public keys
chmod 600 ~/.ssh/config
```

## Verify

```bash
ssh-keygen -lf ~/.ssh/id_ed25519_github_personal.pub   # fingerprint, compare to provider UI
ssh -T git@github-personal                             # GitHub greets you by username
ssh -G github-personal | grep -E '^(identityfile|identitiesonly|user|hostname)'
```

`ssh -G` resolves the config exactly as ssh will apply it, which beats reading the file when
`Host *` blocks or includes are involved.

When authentication still fails:

```bash
ssh -vvv git@github-personal 2>&1 | grep -E 'Offering|Server accepts|Authentications that can continue'
```

`Offering public key:` lines tell you which keys were tried and in what order. If the wrong key
is offered first, `IdentitiesOnly` is missing.

## Never print a private key

`cat ~/.ssh/id_ed25519` in an agent session writes the key into a permanent log. To prove a
private key exists and matches its public half, derive the public key instead:

```bash
ssh-keygen -y -f ~/.ssh/id_ed25519_github_personal   # prints the PUBLIC key
```

See the `secret-capture` skill for the general rule.

## Hardware-backed keys

For a FIDO2 security key (YubiKey and similar), the private key never leaves the device:

```bash
ssh-keygen -t ed25519-sk -O resident -O verify-required \
  -C "yubikey-primary 2026-08" -f ~/.ssh/id_ed25519_sk_yubikey
```

- `-O resident` stores a handle on the token so the key can be recovered onto a new machine with
  `ssh-keygen -K`.
- `-O verify-required` demands the PIN or a touch on every use, not just at load time.

Generation prompts you to touch the authenticator. Enroll a **second** token before relying on
this - a lost token with no backup is a lockout, and there is no export path by design.

## Rotation

1. Generate the replacement with a new date in the comment.
2. Add the new public key to the provider **first**, and confirm it works:
   `ssh -T git@github-personal`.
3. Remove the old public key from the provider.
4. Drop the old key from the agent: `ssh-add -d ~/.ssh/id_ed25519_old`.
5. Delete the key files: `rm ~/.ssh/id_ed25519_old ~/.ssh/id_ed25519_old.pub`.
6. Remove the stored passphrase. The Keychain item is a generic password whose service is
   `SSH:` and whose account is the key's absolute path:

   ```bash
   security find-generic-password -s "SSH:" -a "$HOME/.ssh/id_ed25519_old"    # metadata only
   security delete-generic-password -s "SSH:" -a "$HOME/.ssh/id_ed25519_old"
   ```

   If the item is not found, the passphrase was never saved to the Keychain and step 5 was
   sufficient. Keychain Access.app, searching for `SSH:`, shows the same items.

Order matters: adding the new key before removing the old one means you never lock yourself out.

## Multiple accounts on one machine

See [`references/multi-account-config.md`](references/multi-account-config.md) for the full
pattern - per-directory git identities, `includeIf`, and the config matrix for running personal
plus work GitHub plus GitLab side by side.

## Checklist

- [ ] `ed25519`, purpose-specific filename, purpose-plus-date comment
- [ ] passphrase set, stored with `ssh-add --apple-use-keychain`
- [ ] `IdentitiesOnly yes` on every host block
- [ ] `IgnoreUnknown UseKeychain` before `UseKeychain`
- [ ] `700` on `~/.ssh`, `600` on private keys
- [ ] fingerprint compared against the provider
- [ ] `ssh -T` succeeds as the expected identity
- [ ] private key never printed
