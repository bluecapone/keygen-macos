# Multiple SSH accounts on one machine

Level-3 detail for `ssh-keygen-macos`. Load this only when more than one identity is in play.

## The problem

Two GitHub accounts, or GitHub plus GitLab plus a client's Bitbucket. Symptoms:

- pushes land on the wrong account
- `git push` succeeds but commits show a different author avatar
- one repo works, another gets `Permission denied (publickey)`
- GitHub says `You cannot push to this repository using the key you provided`

Root cause is almost always ssh offering all known keys and the server accepting whichever
authenticates first.

## One key per identity

```bash
ssh-keygen -t ed25519 -C "gh-personal 2026-08"  -f ~/.ssh/id_ed25519_gh_personal
ssh-keygen -t ed25519 -C "gh-work 2026-08"      -f ~/.ssh/id_ed25519_gh_work
ssh-keygen -t ed25519 -C "gitlab-work 2026-08"  -f ~/.ssh/id_ed25519_gitlab_work

for k in ~/.ssh/id_ed25519_gh_personal ~/.ssh/id_ed25519_gh_work ~/.ssh/id_ed25519_gitlab_work; do
  ssh-add --apple-use-keychain "$k"
done
```

## Host aliases

The alias in `Host` is a local name. `HostName` is where it actually connects.

```
# ~/.ssh/config

Host *
  IgnoreUnknown UseKeychain
  AddKeysToAgent yes
  UseKeychain yes
  ServerAliveInterval 60

Host gh-personal
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_gh_personal
  IdentitiesOnly yes

Host gh-work
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_gh_work
  IdentitiesOnly yes

Host gitlab-work
  HostName gitlab.com
  User git
  IdentityFile ~/.ssh/id_ed25519_gitlab_work
  IdentitiesOnly yes
```

`Host *` goes first for shared defaults. Host-specific blocks that follow add to it; for
single-valued keywords the **first** value wins, which is why `IdentityFile` must live in the
specific block and not be preceded by a global one.

Remotes then use the alias in place of the hostname:

```bash
git remote set-url origin git@gh-work:acme/service.git
```

## Matching git identity to ssh identity

An ssh key controls *who you authenticate as*. `user.email` controls *who the commit says wrote
it*. They are independent, and mismatching them is how you get verified-but-wrong-author
commits. Bind them by directory with `includeIf`.

```
# ~/.gitconfig

[user]
  name = Your Name
  email = personal@example.com

[includeIf "gitdir:~/work/"]
  path = ~/.gitconfig-work

[includeIf "gitdir:~/oss/"]
  path = ~/.gitconfig-personal
```

```
# ~/.gitconfig-work
[user]
  email = you@acme.com
  signingkey = ~/.ssh/id_ed25519_gh_work.pub
```

The trailing slash on `gitdir:~/work/` is required - it means "this directory and everything
under it". Without it the pattern matches only an exact path.

Verify inside a repo:

```bash
git config --get user.email
git config --show-origin --get user.email    # which file supplied it
```

## Per-repo override without host aliases

If you would rather keep real hostnames in remotes, set the key per repo:

```bash
git -C ~/work/service config core.sshCommand \
  "ssh -i ~/.ssh/id_ed25519_gh_work -o IdentitiesOnly=yes"
```

This is the escape hatch for a repo you cannot re-point, and for CI checkouts. Host aliases are
cleaner for anything long-lived because they are declared once and apply to every tool, not
just git.

## Verifying each identity independently

```bash
ssh -T git@gh-personal   # "Hi personal-user! You've successfully authenticated"
ssh -T git@gh-work       # "Hi work-user! ..."
ssh -T git@gitlab-work   # "Welcome to GitLab, @work-user!"
```

GitHub returns exit status 1 on a successful `-T` because it allocates no shell. That is normal.
Read the greeting, not the exit code.

When the greeting names the wrong user, that host block is offering the wrong key:

```bash
ssh -vvv git@gh-work 2>&1 | grep -E 'Offering|Server accepts'
```

Exactly one `Offering public key:` line should appear per host when `IdentitiesOnly yes` is set.
More than one means the directive is missing or a `Host *` block is injecting extra
`IdentityFile` entries.

## Agent hygiene

With many keys loaded, some servers disconnect after too many failed offers
(`Too many authentication failures`). `IdentitiesOnly yes` prevents this. To inspect or reset:

```bash
ssh-add -l          # list loaded keys by fingerprint
ssh-add -d ~/.ssh/id_ed25519_gh_work   # drop one
ssh-add -D          # drop all (Keychain-stored passphrases reload on next use)
```
