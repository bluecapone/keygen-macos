---
name: keychain-secrets
description: Reads, writes, updates, and deletes secrets in the macOS login Keychain from the shell using the security command and generic-password items scoped by service and account. Use when a script needs an API key without hardcoding it, when migrating credentials out of .env files or shell history, when retrieving a stored password for a command, when listing what a keychain item holds without revealing it, or when deleting a stale credential. Use when a secret must not appear in argv or process listings, and when deciding between the login keychain and a dedicated keychain file.
---

# macOS Keychain secrets from the shell

The login Keychain is already on every Mac, already encrypted at rest, already unlocked at
login, and already excluded from most backup and sync paths that leak `.env` files. For
developer credentials on a single machine it beats a dotfile.

Interface is `security`, and the item type you want is `generic-password`, keyed by a
**service** plus an **account**.

## Write

```bash
security add-generic-password -s "acme-api" -a "$USER" -U -w
```

Omitting a value after `-w` makes `security` prompt for it interactively. **Prefer this form.**
The secret never appears in argv, so it cannot be seen in `ps` output or recovered from shell
history.

- `-s` service - the logical name of the credential. Pick a stable convention such as
  `<vendor>-<purpose>`.
- `-a` account - who or what the credential is for. `$USER` is fine for personal tokens; use the
  actual account identifier when a service has several.
- `-U` update if it already exists. Without `-U`, a second add fails with
  `already exists in the keychain`.
- `-w` the password. Bare `-w` prompts.

Non-interactive form, for when a script generates the value and no human is present:

```bash
SECRET=$(openssl rand -hex 32)
security add-generic-password -s "acme-api" -a "$USER" -U -w "$SECRET"
echo "stored (${#SECRET} chars)"
unset SECRET
```

This does put the value in argv for the lifetime of the process. That is an accepted tradeoff on
a single-user machine; on anything shared, use the interactive form or pipe through a file
descriptor. See the `secret-capture` skill.

Useful extras:

- `-j "note"` a comment stored with the item, visible in Keychain Access.
- `-l "label"` the display label. Defaults to the service name.
- `-T ""` pre-authorize **no** applications, forcing a prompt on every access. `-T /path/to/app`
  pre-authorizes one binary. `-A` allows every application without prompting - avoid it.

## Read

```bash
security find-generic-password -s "acme-api" -a "$USER" -w
```

`-w` prints only the password. Drop it to get metadata with no secret:

```bash
security find-generic-password -s "acme-api" -a "$USER"
```

That prints the attribute dump - service, account, label, creation date, class - and no value.
This is the form to use when you only need to confirm an item exists.

In a script, capture rather than print:

```bash
API_KEY=$(security find-generic-password -s "acme-api" -a "$USER" -w) || {
  echo "credential 'acme-api' not in keychain" >&2
  exit 1
}
```

`security` exits non-zero when the item is missing, so `||` is a real check. Exit status 44 is
`The specified item could not be found in the keychain`.

## Update and delete

```bash
# update in place - -U is what makes add behave as upsert
security add-generic-password -s "acme-api" -a "$USER" -U -w

# delete
security delete-generic-password -s "acme-api" -a "$USER"
```

There is no `update-generic-password` subcommand. `add ... -U` is the update path.

## Which keychain

Default target is the login keychain, `~/Library/Keychains/login.keychain-db`. Be explicit with
`-k` when it matters:

```bash
security add-generic-password -k ~/Library/Keychains/login.keychain-db -s "acme-api" -a "$USER" -U -w
security list-keychains
security default-keychain
```

A dedicated keychain is worth it when you want a **different lock lifetime** than login - for
example credentials that should re-lock after 5 minutes rather than staying open all session:

```bash
security create-keychain -p "" ci-secrets.keychain     # prompts if -p omitted
security set-keychain-settings -t 300 -l ci-secrets.keychain   # lock after 300s idle
security unlock-keychain ci-secrets.keychain
```

`security create-keychain` with `-p ""` gives the new keychain an empty password, which defeats
the purpose. Omit `-p` and let it prompt.

## Locking

```bash
security lock-keychain                 # lock the default keychain now
security unlock-keychain               # prompts
security show-keychain-info            # current lock settings
```

Locking the login keychain mid-session causes prompts from unrelated apps. Prefer a dedicated
keychain when you actually want aggressive locking.

## Migrating a `.env` file into the Keychain

```bash
# read KEY=VALUE pairs, store each, then shred the file
while IFS='=' read -r key value; do
  case "$key" in ''|\#*) continue ;; esac
  value="${value%\"}"; value="${value#\"}"
  security add-generic-password -s "myapp-$key" -a "$USER" -U -w "$value"
  echo "stored myapp-$key (${#value} chars)"
done < .env

rm .env
git rm --cached .env 2>/dev/null
printf '.env\n' >> .gitignore
```

Then read them back at runtime:

```bash
export ACME_API_KEY=$(security find-generic-password -s "myapp-ACME_API_KEY" -a "$USER" -w)
```

If `.env` was ever committed, deleting it does not remove it from history. Rotate every
credential it contained - see `secret-capture`.

## Listing what exists

`security dump-keychain` without `-d` prints attributes only and does not decrypt anything, so
it is safe for inventory:

```bash
security dump-keychain 2>/dev/null | awk -F'"' '/"svce"<blob>=/ {print $4}' | sort -u
```

Adding `-d` decrypts and triggers a GUI authorization prompt per item. Do not use `-d` in an
agent session - it both prompts and prints secrets.

## Checklist

- [ ] `-w` used bare so the value is prompted, not in argv
- [ ] `-U` present so re-running updates instead of failing
- [ ] service/account naming is a convention, not ad hoc
- [ ] reads capture into a variable and check exit status
- [ ] metadata reads omit `-w`
- [ ] `dump-keychain` used without `-d`
- [ ] source `.env` removed, gitignored, and its secrets rotated if ever committed
