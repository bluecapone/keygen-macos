# Authoring conventions

Rules every skill in this repo follows, and the reason each one exists. `scripts/check-skills.sh`
enforces the mechanical ones.

## 1. The description is the product

A skill that never loads is worth nothing. The agent sees only `name` and `description` until it
decides to open the body, so the description is the entire discovery surface.

Hard constraints:

- third person, describing the skill's action - `Generates and configures SSH keys...`, not
  `You can use this to...` or `I help you...`
- 1024 characters or fewer
- states **what it does and when to fire**, with the literal phrases and error strings a user
  would type

That last point is what actually moves trigger reliability. `permission denied (publickey)`,
`gpg failed to sign the data`, and `commits show as Unverified` are in the descriptions here
because those are the strings a person pastes into a prompt. A description that only says
"helps with SSH keys" loses to one that names the symptom.

Validator checks: length, third-person opener, and presence of an explicit `Use when` /
`Use whenever` / `Use for` clause.

## 2. Three-level progressive disclosure

| Level | Loaded | Holds |
|---|---|---|
| 1 | always | `name` + `description` frontmatter |
| 2 | on trigger | `SKILL.md` body |
| 3 | on demand | files under `references/`, linked from the body |

`skills/ssh-keygen-macos/` demonstrates level 3: the common single-key path is in the body,
and the multi-account configuration matrix lives in
`skills/ssh-keygen-macos/references/multi-account-config.md`. Someone generating their first
key never pays for the multi-account content.

## 3. Body under 500 lines

Past 500 lines, split into `references/` and link. This is Anthropic's published limit and it
is a real ceiling, not a style preference - a long body crowds out the working context the
agent needs for the actual task.

## 4. Names are lowercase-hyphen and match the directory

`^[a-z0-9]+(-[a-z0-9]+)*$`, 64 characters or fewer, and `name:` equals the containing directory
name. Mismatches produce skills that resolve inconsistently across agents.

## 5. Imperative body, no preamble

The body is instructions to an agent mid-task, not an article. No "In this guide we will
explore". Lead with the command or the decision rule. Explain *why* only where the why changes
what the reader should do - `IdentitiesOnly yes` needs its rationale because without it the
failure is silent and confusing.

## 6. Every command is executed before it ships

Documented commands are run on a real machine and the output checked. Where a command cannot
be verified (needs hardware, a paid service, or a destructive action), it is either omitted or
explicitly flagged as unverified. A skill full of plausible-looking commands that were never
run is worse than no skill, because the agent will execute them with confidence.

This is why this repo has six skills rather than eight. An `age`/`sops` secrets-at-rest skill
and a Secure Enclave skill were both drafted and cut: neither tool was installed on the
authoring machine, so neither could be verified.

## 7. Audit and delete

Skill count is not the metric. Skill survival is. Expect to write roughly twice what you keep -
if nothing is getting deleted during authoring, the bar is too low.

## Checklist before opening a PR

- [ ] `./scripts/check-skills.sh` passes
- [ ] every command in the body was actually executed
- [ ] description names the symptom or phrase a user would type
- [ ] body is instructions, not prose
- [ ] no real credentials, fingerprints, hostnames, or usernames in examples
