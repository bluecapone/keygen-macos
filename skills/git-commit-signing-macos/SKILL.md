---
name: git-commit-signing-macos
description: Configures verified Git commit and tag signing on macOS, defaulting to SSH signing with ssh-keygen -Y and falling back to GPG only when a provider or policy requires OpenPGP. Covers gpg.format, user.signingkey, allowed_signers, commit.gpgsign, pinentry-mac wiring, and GPG_TTY. Use when commits show as Unverified on GitHub or GitLab, when enabling signing for the first time, when choosing between SSH and GPG signing, when signing breaks with "gpg failed to sign the data" or "Inappropriate ioctl for device", or when a signed commit shows the wrong author identity.
---

# Verified commit signing on macOS

Two mechanisms. Pick SSH unless something forces OpenPGP.

| | SSH signing | GPG signing |
|---|---|---|
| Setup | 4 git config lines | keyring, agent, pinentry, key expiry |
| Reuses | the SSH key you already have | a new keypair to manage |
| Git | 2.34+ | any |
| Needs | nothing extra | `gnupg` + `pinentry-mac` |
| Pick when | almost always | policy, web-of-trust, or a provider demands OpenPGP |

## SSH signing (default)

Use a **dedicated** signing key. Providers register authentication keys and signing keys
separately, and separating them means revoking one does not break the other.

```bash
ssh-keygen -t ed25519 -C "git-signing 2026-08" -f ~/.ssh/id_ed25519_git_signing
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_git_signing
```

Configure git to sign with it:

```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519_git_signing.pub
git config --global commit.gpgsign true
git config --global tag.gpgsign true
```

`user.signingkey` points at the **`.pub`** file. Pointing it at the private key is the usual
cause of `error: Load key ... invalid format`.

Then add the public key to the provider **as a signing key**:

```bash
cat ~/.ssh/id_ed25519_git_signing.pub | pbcopy
```

- GitHub: Settings, SSH and GPG keys, New SSH key, key type **Signing Key**
- GitLab: Preferences, SSH Keys, usage type **Signing**

Adding it as an authentication key instead leaves commits Unverified. This is the single most
common SSH-signing mistake.

### Local verification needs an allowed_signers file

`git log --show-signature` cannot verify anything without a map of identity to key. Git does not
build this from the provider.

```bash
mkdir -p ~/.config/git
printf '%s %s\n' "$(git config --get user.email)" \
  "$(cat ~/.ssh/id_ed25519_git_signing.pub)" >> ~/.config/git/allowed_signers
git config --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers
```

Each line is `principal keytype keydata`, so the file contains the email followed by the full
public key text. Verify:

```bash
git commit --allow-empty -m "signing test"
git log --show-signature -1
```

Expect `Good "git" signature for you@example.com with ED25519 key SHA256:...`.

### Reading the verification output precisely

The three outcomes are distinguishable, and the difference is whether `for <email>` appears:

| Situation | `--show-signature` says | `%G?` | `git verify-commit` |
|---|---|---|---|
| signing key **is** in `allowed_signers` | `Good "git" signature for <email> with ED25519 key SHA256:...` | `G` | exit 0 |
| signing key **not** in `allowed_signers`, or the file is empty | `Good "git" signature with ED25519 key SHA256:...` then `No principal matched.` | `U` | exit 1 |
| `gpg.ssh.allowedSignersFile` unset or missing | `No signature` plus `error: gpg.ssh.allowedSignersFile needs to be configured and exist` | `N` | exit 1 |

So `No principal matched` means **the key that signed the commit is not listed in
`allowed_signers`** - add the key. It does *not* mean the emails disagree.

That distinction matters because of a real gotcha: **SSH signature verification does not bind the
signature to the commit author.** The principal git prints is the one paired with that key in
`allowed_signers`, not the commit's author field. A commit authored by `smoke@example.com` and
signed by a key listed under `other@example.com` verifies as
`Good "git" signature for other@example.com` with `%G? = G`. Git is answering "was this signed by
a key I trust", not "did the stated author sign this". If you need author-to-key correspondence
enforced, that is a server-side or CI check - GitHub and GitLab apply their own account-level
binding, which is why a commit can verify locally and still show Unverified on the provider.

## GPG signing (when required)

```bash
brew install gnupg pinentry-mac
gpg --full-generate-key
```

Choose `ECC (sign and encrypt)`, then `Curve 25519`, then a 2-year expiry. Expiry is a feature -
an expired key is a prompt to rotate, and you can always extend it.

Get the key ID:

```bash
gpg --list-secret-keys --keyid-format=long
```

Read the long hex ID after `sec   ed25519/`.

```bash
KEYID=<that-hex-id>
git config --global gpg.format openpgp
git config --global user.signingkey "$KEYID"
git config --global commit.gpgsign true
git config --global gpg.program "$(command -v gpg)"
```

`gpg.program` matters because git otherwise searches `PATH` and can find a different `gpg` than
the one holding your keys.

Wire up the macOS pinentry so the passphrase prompt is a native dialog:

```bash
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg
printf 'pinentry-program %s\n' "$(command -v pinentry-mac)" >> ~/.gnupg/gpg-agent.conf
gpgconf --kill gpg-agent
```

The agent is not reloaded until it is killed - `gpgconf --kill gpg-agent` is required, not
optional, and it restarts on next use.

Add to your shell rc:

```bash
export GPG_TTY=$(tty)
```

Export the public key for the provider:

```bash
gpg --armor --export "$KEYID" | pbcopy
```

Paste under GitHub Settings, SSH and GPG keys, New GPG key.

## Errors

**`gpg failed to sign the data`** - run the underlying command directly to see the real error,
which git swallows:

```bash
echo test | gpg --clearsign
```

**`Inappropriate ioctl for device`** - `GPG_TTY` is unset. `export GPG_TTY=$(tty)`.

**Commits still Unverified on the provider** - the commit author email must be an email
**verified on your provider account** and, for GPG, an identity on the key. Check:

```bash
git log -1 --format='%ae %GK %G?'
```

`%G?` returns `G` good, `B` bad, `U` good-with-unknown-trust, `N` no signature. `N` means
signing did not happen at all; recheck `commit.gpgsign`.

**`error: Load key ... invalid format`** - `user.signingkey` points at a private key under
`gpg.format ssh`. Point it at the `.pub`.

**Signed but wrong author** - `user.email` is per-directory when `includeIf` is in play. See
`ssh-keygen-macos` references for the directory-scoped identity pattern.

## Signing existing commits

Signing is applied at commit creation, so history has to be rewritten:

```bash
git rebase --exec 'git commit --amend --no-edit -S' -i <base>
```

This changes every rewritten commit's hash. Do not do it on a shared branch.

## Verify the whole setup

```bash
git config --get-regexp '^(gpg|commit|tag|user\.signingkey)' 
git commit --allow-empty -m "verify signing"
git log --show-signature -1
git verify-commit HEAD && echo "verify-commit: OK"
```

## Checklist

- [ ] SSH signing chosen unless OpenPGP is mandated
- [ ] dedicated signing key, separate from the authentication key
- [ ] `user.signingkey` points at `.pub` under `gpg.format ssh`
- [ ] key registered with the provider as a **Signing** key
- [ ] `allowed_signers` populated and `gpg.ssh.allowedSignersFile` set
- [ ] commit author email is verified on the provider account
- [ ] `git log --show-signature -1` reports a good signature
