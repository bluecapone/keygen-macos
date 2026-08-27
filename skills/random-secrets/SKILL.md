---
name: random-secrets
description: Generates cryptographically strong random secrets, passwords, passphrases, and identifiers on macOS using openssl rand, /dev/urandom, and uuidgen, and selects the right encoding and length for the target system. Use when a script or service needs a new secret, signing key, webhook secret, database password, session token, or API credential; when choosing between hex, base64, and base64url; when a value must survive being pasted into a URL, an environment variable, or a YAML file; or when reviewing whether an existing generator has enough entropy. Use when auditing code that seeds randomness from $RANDOM, dates, timestamps, PIDs, or md5 of the current time.
---

# Generating random secrets on macOS

## The one-liners

```bash
openssl rand -hex 32            # 64 hex chars, 256 bits - default choice
openssl rand -base64 32         # 44 chars, 256 bits - denser
uuidgen                         # random UUIDv4, 122 bits - identifiers, not secrets
```

`openssl rand` reads the OS CSPRNG. On macOS that is the kernel's arc4random/getentropy path,
which is seeded from hardware and never blocks. It is the correct default.

## Pick the entropy first, then the encoding

Decide how many **bits** you need, then encode. Encoding changes the character count, never the
entropy.

| Bits | `-hex` chars | `-base64` chars | Use for |
|---|---|---|---|
| 128 | 32 | 24 | session IDs, CSRF tokens, non-critical API keys |
| 256 | 64 | 44 | signing keys, HMAC secrets, anything long-lived |
| 512 | 128 | 88 | key-derivation input, paranoid long-term secrets |

128 bits is unguessable. 256 bits is the default for anything that signs or persists. Above 512
you are adding characters, not security.

`openssl rand -base64 N` takes **N bytes**, not N characters, and emits ceil(N/3)*4 characters.
`-base64 32` gives 44 characters, not 32. Getting this backwards is the most common mistake -
`openssl rand -base64 16` looks like a fine password and is only 128 bits in 24 characters.

## Encoding decision rule

- **hex** - safe everywhere. Case-insensitive, no special characters, survives URLs, YAML, env
  vars, shell, and copy-paste. Costs 2 characters per byte. Default to this when in doubt.
- **base64** - denser, but contains `+`, `/`, and `=`. Those break URLs and query strings, and
  `=` padding trips naive parsers. Fine inside a Keychain item or a header value.
- **base64url** - base64 with `-`/`_` and no padding. The right choice for tokens that appear
  in URLs:

  ```bash
  openssl rand 32 | base64 | tr '+/' '-_' | tr -d '=\n'
  ```

- **alphanumeric only** - when a system rejects punctuation. Filter, never truncate a hash:

  ```bash
  LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 40; echo
  ```

  `LC_ALL=C` is required. Without it `tr` can choke on invalid multibyte sequences from random
  bytes and produce nothing or an error. This is a real failure on macOS, not a theoretical one.

## Human-typed passphrases

For anything a person types - SSH key passphrases, disk encryption, recovery codes - use words,
not characters. Six words from a large wordlist beats a 12-character symbol soup for both
strength and typeability.

```bash
# 6 words from the system dictionary, ~77 bits with the macOS word list
for i in $(seq 6); do
  LC_ALL=C awk 'BEGIN{srand()} length($0)>3 && length($0)<9 && $0 !~ /[^a-z]/' /usr/share/dict/words \
    | sed -n "$(( ( $(openssl rand -hex 4 | tr -d '\n' | sed 's/^/0x/' | xargs printf '%d') % 20000 ) + 1 ))p"
done | paste -sd- -
```

That is fiddly. If the machine has a real diceware tool, prefer it. If not, the honest simple
version is to generate the words with an explicit random index per word as above, or just use a
password manager's generator. Do **not** substitute `$RANDOM` to make it shorter - see below.

`/usr/share/dict/words` exists on macOS and has roughly 235,000 entries, but it includes
proper nouns and very long words, which is why the filter is there.

## Never use these

```bash
echo $RANDOM                                   # 15 bits, seeded from PID and time
date +%s | shasum                              # attacker knows the time
echo "$(date)$$" | md5                         # md5, plus predictable inputs
awk 'BEGIN{srand();print rand()}'              # srand() defaults to time-of-day seed
python3 -c 'import random;print(random.random())'  # Mersenne Twister, not a CSPRNG
```

Every one of these is predictable to someone who knows roughly when the secret was made.
`$RANDOM` in particular has only 32768 possible values.

The Python correct form, when you need it in a script:

```bash
python3 -c 'import secrets;print(secrets.token_hex(32))'
python3 -c 'import secrets;print(secrets.token_urlsafe(32))'
```

`secrets`, never `random`.

## Generating straight into storage

The best secret is one that is never displayed. Pipe generation directly into its destination -
see the `keychain-secrets` and `secret-capture` skills.

```bash
# generate and store, printing only a length proof
SECRET=$(openssl rand -hex 32)
security add-generic-password -U -s "my-service" -a "$USER" -w "$SECRET"
echo "stored (${#SECRET} chars)"
unset SECRET
```

## Common target formats

```bash
# HMAC / webhook signing secret
openssl rand -hex 32

# URL-safe bearer token
openssl rand 32 | base64 | tr '+/' '-_' | tr -d '=\n'

# database password, punctuation-safe for connection strings
LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32; echo

# 6-digit numeric OTP (unbiased - rejects out-of-range draws)
while :; do n=$(( 0x$(openssl rand -hex 3) )); [ "$n" -lt 16000000 ] && break; done
printf '%06d\n' "$(( n % 1000000 ))"

# random identifier, not a secret
uuidgen | tr 'A-Z' 'a-z'
```

That OTP loop matters: `$(( 0x... % 1000000 ))` on its own is biased, because 2^24 is not a
multiple of 10^6. Rejecting draws at or above the largest multiple removes the bias. For a
6-digit code the bias is small, but the rejection loop costs nothing.

## Checklist

- [ ] source is `openssl rand`, `/dev/urandom`, or `python3 -c 'import secrets'`
- [ ] 128 bits minimum, 256 for anything long-lived or signing
- [ ] `-base64 N` understood as N *bytes*
- [ ] encoding survives the destination (URL, YAML, env var, connection string)
- [ ] `LC_ALL=C` set when filtering `/dev/urandom` through `tr`
- [ ] value piped to storage rather than printed
