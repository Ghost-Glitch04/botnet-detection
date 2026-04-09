---
name: github-security-standards
description: Apply repository security standards whenever writing, reviewing, or modifying any code, script, or configuration file that will be committed to a repository. Trigger on ANY mention of GitHub, repos, git, API keys, tokens, credentials, secrets, sensitive data, .env files, connection strings, or file paths. Also trigger when writing code or scripts in any language that connect to external services, handle sensitive data, or produce output files — even if security is not explicitly mentioned. These standards exist to protect credentials, business-sensitive information, and internal infrastructure details from exposure through version control. Always apply them without being asked.
---

# GitHub Repository Security Standards

Security philosophy: **the repository contains code, never secrets or sensitive data**. A GitHub repo — even a private one — is not a safe place for credentials, organization names, internal paths, or sensitive information of any kind. These standards exist to make the secure approach the default approach, so that sharing work with collaborators never introduces risk.

Apply these standards to all work involving git repositories unless the user explicitly says otherwise.

---

## Pre-Flight Security Checklist

Run this checklist before writing any code or config file that will live in a repository. These questions identify security requirements before code is written — not after.

- Does this code connect to an external service? → A `Get-Secret` / `get_secret()` call and `.env.example` entry are required before writing credential-using code
- Does this code produce output files? → The output directory must be in `.gitignore` before the first run
- Does this code reference organization names, tenant IDs, customer identifiers, or internal paths? → Those values must come from `config.local` at runtime, not from the code
- Does this code log any values? → Identify which values are secrets and confirm they will be masked
- Does a `.gitignore` already exist in this repo? → Review and extend it — never assume an existing gitignore is complete

If any answer requires a gitignore entry, create that entry **before** creating the file it covers.

---

## What Is Sensitive — The Taxonomy

Understanding what counts as sensitive prevents the most common mistakes: assuming only passwords matter, or that "it's just a customer name."

### Category 1 — Credentials (never in any file that touches a repo)

| Type | Examples |
|---|---|
| API keys and tokens | OAuth tokens, webhook secrets, service API keys |
| Passwords | Service account passwords, database passwords |
| Connection strings | Any string containing a username, password, or access key |
| Application secrets | OAuth client secrets, app registration secrets |
| Certificate keys | Private keys for any certificate |

### Category 2 — Business-Sensitive Information (never in repo)

This category covers any data that identifies or is specific to an organization, customer, or engagement. The exact items vary by project type:

| Type | Examples |
|---|---|
| Organization identifiers | Customer/client names, tenant IDs, domain names |
| Environment-specific configuration | Organization-specific URLs, paths, or settings |
| Business data | Any record, export, or file sourced from a production or customer system |
| Project identifiers | Codenames, internal project IDs that map to specific engagements |

### Category 3 — Internal Infrastructure (never in repo)

| Type | Examples |
|---|---|
| Internal paths | UNC paths, server names, internal URLs |
| System identifiers | Internal hostnames, IP addresses, cluster names |
| Org structure | Employee names tied to system access, team names in paths |

### Category 4 — Derived Exposure (gitignore required)

These files may contain any of the above — gitignore them even if they seem harmless:

- Log files (`*.log`, `logs/`)
- Output files (`output/`, `exports/`, `reports/`, `*.csv`, `*.xlsx`)
- Cached API responses
- Database exports or dumps
- Any file written by code at runtime

---

## The Three-Layer Model

All work follows a three-layer separation that keeps sensitive data out of the repo while keeping code fully functional for every collaborator.

| Layer | Contents | Lives in |
|---|---|---|
| **Layer 1 — Code** | Scripts, logic, structure, documentation | GitHub repo — shared |
| **Layer 2 — Local config** | Non-secret operational values: org names, output paths, environment flags | `config.local.json` — gitignored, per-person |
| **Layer 3 — Credentials** | API keys, tokens, passwords | `.env` file — gitignored, per-person |

**Layer 1** is everything a collaborator clones. It contains no real values.

**Layer 2** holds values that are sensitive but not secret — things safe to log at DEBUG level for diagnostics, but wrong to commit. Each person maintains their own version.

**Layer 3** holds secrets that must never be logged, displayed, or stored anywhere but the local file. Each person maintains their own version. When an external secrets manager (e.g., HashiCorp Vault, AWS Secrets Manager, Azure Key Vault, Secret Server by Datto) is available, it replaces this layer without changing any code logic — see the `Get-Secret` abstraction below.

---

## The Get-Secret Abstraction

**Never read credentials directly from environment variables in code logic.** Always go through a `Get-Secret` / `get_secret()` helper function. This single rule enables future secrets manager migration: when that integration is ready, only the helper function changes — no calling code needs to be updated.

```
# Today (reads from .env):              # Tomorrow (same call, new backend inside):
Get-Secret "API_CLIENT_SECRET"      →    Get-Secret "API_CLIENT_SECRET"
get_secret("API_CLIENT_SECRET")     →    get_secret("API_CLIENT_SECRET")
# ↑ Callers unchanged — only the function body is replaced.
```

The helper must:
- Validate the value is present and non-empty
- Fail fast with `CONFIG_MISSING` prefix and the exact variable name if absent
- Never return a null or empty value silently
- Never log the secret value — not even the first few characters

See the language reference files for the complete `Get-Secret` implementation:
- [📋 PowerShell](./reference/env-setup.md#powershell-patterns)
- [🐧 Bash](./reference/env-setup.md#bash-patterns)
- [🐍 Python](./reference/env-setup.md#python-patterns)

---

## Integration with Structured Script Standards

> **This section applies only when a structured scripting-standards skill (or equivalent phased script architecture) is active alongside this skill.** If no such standard is in use, the security helpers below are standalone — place them wherever your project organizes shared utility functions, and call them during application startup before any code that uses credentials or config.

When both skills are active, the security helpers from this skill slot into the scripting-standards script structure at specific points. This section defines that mapping so there is one clear lifecycle — not two competing ones.

### Where Security Helpers Go

Security helpers (`Get-Secret` / `get_secret`, `Import-DotEnv` / `load_dotenv`, `Import-LocalConfig` / `load_local_config`, `Get-MaskedParams` / `mask_params`) are placed in the **HELPERS** section of the script, alongside logging and other shared utilities.

**Dependency ordering within HELPERS:**

1. Logging function (e.g., `Write-Log` / `log()` / `setup_logger`) — must be defined first (most other helpers depend on it)
2. `Get-Secret` / `get_secret` — depends on logging
3. `Import-DotEnv` / `load_dotenv` — depends on logging (PowerShell) or uses echo to stderr (Bash, Python)
4. `Import-LocalConfig` / `load_local_config` — depends on logging
5. `Get-MaskedParams` / `mask_params` — no dependencies (standalone)

### Bootstrap Sequence in Main Block

The security bootstrap runs in the main entry point, after log file setup but before the first operational phase. The sequence is:

```
MAIN / ENTRY POINT
├── Parse arguments
├── Set up logging destination
├── ── Security bootstrap ──
│   ├── Import-DotEnv / load_dotenv      ← loads .env into environment
│   ├── Import-LocalConfig / load_local_config  ← loads config.local.json
│   └── Log parameters with masking      ← uses Get-MaskedParams / mask_params
├── Phase 1 / first operational step — ...
├── Phase 2 / next step — ...
└── Final status log
```

**Language-specific ordering notes:**

- **PowerShell:** `Import-DotEnv` uses `Write-Log`, so the log file path must already be set. This is the natural order since the log file path is set from arguments, not from `.env`.
- **Bash:** `load_dotenv` runs before `LOG_FILE` is set (it uses `echo >&2` instead of `log()`). This is because some scripts derive the log path from config values loaded by dotenv.
- **Python:** `load_dotenv` runs before `setup_logger` for the same reason — the log directory can come from config. The function uses `print()` for fatal errors since the logger doesn't exist yet.

### What This Skill Does NOT Override

If a scripting-standards skill is active, it governs script structure, unit design, exit codes, logging format, performance timers, and phase architecture. This skill only adds:

- Security-specific helpers (listed above)
- A bootstrap sequence in the main entry point
- Security-specific log prefixes (`CONFIG_MISSING`, `SECRET_LOADED`, and optionally `CREDENTIAL_MASKED`)
- The pre-flight checklist (run before writing code, not at runtime)

---

## The `.env` Pattern

The `.env` file holds credentials. The `.env.example` file is its committed counterpart — it documents what credentials are needed without containing any real values.

### File Relationship

```
project-root/
├── .env                  ← gitignored — real values, never committed
├── .env.example          ← committed — placeholder values, documents requirements
├── config.local.json     ← gitignored — non-secret operational config
├── config.example.json   ← committed — placeholder config, documents structure
└── .gitignore            ← covers .env, config.local.json, outputs, logs
```

### The `.env.example` as a Contract

The `.env.example` file is the onboarding instruction for every collaborator. It must:
- List every variable the code requires
- Group variables by service with a comment header
- Use empty values or clearly fake placeholders — never real values
- Stay current — when code gains a new credential dependency, `.env.example` is updated in the same commit

A collaborator's setup process is: copy `.env.example` → `.env`, fill in real values, run.

### Naming Convention

Group and prefix variables by service so the file stays readable:

```bash
# Primary API service
API_CLIENT_ID=
API_CLIENT_SECRET=
API_ENDPOINT=

# Database
DB_HOST=
DB_USER=
DB_PASSWORD=

# Add further service groups below as needed
```

Non-secret operational values (output paths, log paths, organization names, feature flags) belong in `config.example.json` — not here. See the three-layer model above. If a value is safe to log at DEBUG level, it is a Layer 2 value and lives in `config.local.json`.

See the language reference files for complete `.env` loading patterns and startup validation in PowerShell, Bash, and Python.

---

## Credential Masking in Logs

Verbose logging is a security liability if secret values appear in it. Two log patterns are particularly dangerous:

- **PARAMS / startup logging** — logs all parameter values at startup. Must never include raw credential values.
- **Error logging / environment snapshots** — may log data that contains embedded credentials.

### The Masking Rule

Any variable loaded via `Get-Secret` is treated as a secret for the lifetime of the process. When building log messages:
- Replace secret values with `[REDACTED]`
- Never log partial values ("first 4 characters") — partial values can still be used in attacks
- Never log secrets at DEBUG level — debug mode does not grant permission to log credentials

The startup parameter log line must be constructed with a sanitized copy of parameters, not logged wholesale.

### The Secret Pattern List

The masking helpers detect secrets by matching parameter names against this pattern list. If any pattern appears as a substring of the parameter name (case-insensitive), the value is replaced with `[REDACTED]`.

**Canonical patterns** (all implementations must use this exact list):

`key`, `secret`, `password`, `token`, `credential`, `pwd`, `apikey`, `auth`, `bearer`, `conn_str`, `connection_string`, `certificate`, `pat`, `sas`

Pattern notes — read before modifying:

- `apikey` — **Redundant** with `key` (any string containing `apikey` also contains `key`). Kept for documentation clarity: it makes the intent of the list explicit to someone reading it for the first time. Do not remove it thinking it adds coverage — it does not. If building a new pattern list from scratch, `key` alone is sufficient.
- `auth` — **Broad pattern, known false-positive risk.** Matches `author`, `auth_method`, `authorization_mode`, and similar non-secret fields. The pattern is intentionally conservative — any parameter containing `auth` is masked by default. If a legitimate non-secret field triggers masking, rename the field rather than narrowing the pattern.
- `pat` — Personal Access Token (GitHub, Azure DevOps, and similar platforms)
- `sas` — Azure Shared Access Signature token (storage accounts, Service Bus, Event Hubs)

When adding a new pattern: add it here first, then update all language implementations in the env-setup reference file. The list lives here so there is one source of truth — not multiple copies that drift.

See the language reference files for the masking helper implementation in each language.

---

## The Gitignore-First Rule

The gitignore entry must exist **before** the file it covers. This is a sequence, not just a rule:

1. Identify what files the code will create, download, or write
2. Add patterns covering those files to `.gitignore`
3. Run `git status` to confirm covered files don't appear as untracked
4. Only then run the code for the first time

**Why the sequence matters:** `git add -A` or an IDE's auto-stage feature can commit a file in seconds. Once committed, gitignoring it doesn't help — it remains in history.

### Gitignore Pattern Principles

Prefer broad patterns over narrow ones:

| Instead of | Use |
|---|---|
| `.env` | `.env` and `.env.*` |
| `logs/run-2025-03-27.log` | `logs/` |
| `output/acme-report.csv` | `output/` and `*.csv` |

Use the `!` exception to explicitly commit template files:

```gitignore
.env
.env.*
!.env.example
```

See the gitignore reference file for complete, ready-to-use pattern blocks.

---

## Git History Is Permanent

This rule exists because the instinct to "just delete it" is wrong:

**If a secret has touched a commit — even once, even briefly — consider it compromised.**

Gitignoring the file after the fact, deleting the file, or making the repo private does not remove the secret from git history. Anyone who cloned the repo before deletion has it. GitHub's servers have it. It is extractable with standard git commands.

**The correct response when a secret is committed:**
1. **Revoke and rotate the secret immediately** — before doing anything else
2. Audit who has access to the repo
3. Report per your organization's incident response procedure
4. Optionally rewrite git history using `git filter-branch` or BFG Repo Cleaner — but understand this requires force-push, all collaborators must re-clone, and it does not help anyone who already cloned before the rewrite

**The correct prevention:** gitignore-first, always.

---

## Local File Permissions

Gitignored does not mean private from local tools. AI coding assistants, IDE extensions, and other development tools read the working directory. A `.env` file that exists locally but is gitignored is still readable by any tool with filesystem access.

Set restrictive permissions on credential files:

- **Windows:** Remove inherited permissions, grant read access to current user only
- **Linux/macOS:** `chmod 600 .env` — owner read/write only

This is a secondary defense — the primary defense is an external secrets manager when available. But until that integration is in place, file permissions are the only protection against local tool exposure.

---

## CI/CD and GitHub Actions

These standards focus on local development, but code that runs in CI/CD pipelines needs credentials too. The `.env` file does not exist in CI — secrets are injected through the platform's secrets mechanism.

**GitHub Actions:** Store credentials in repository or organization secrets (Settings → Secrets and variables → Actions). Reference them in workflows as `${{ secrets.YOUR_SECRET_NAME }}`. GitHub masks secret values in logs automatically.

**Other CI platforms:** GitLab CI/CD uses Settings → CI/CD → Variables. Azure DevOps uses Pipeline Variables (secret type). AWS CodeBuild uses Parameter Store or Secrets Manager. The mechanism differs but the principle is identical — secrets are injected by the platform, not read from files.

**The mapping:** Each variable in `.env.example` should have a corresponding CI secret. The `.env.example` file serves as the documentation for both local setup and CI configuration — a collaborator setting up the pipeline knows exactly which secrets to create.

**What does NOT change:** Code logic is identical in CI and local. The `Get-Secret` / `get_secret` helper reads from environment variables either way — the only difference is how those variables get set (`.env` file locally, platform injection in CI). This is by design.

---

## Defense in Depth

The gitignore-first rule is the primary prevention layer. These additional layers catch mistakes that slip past gitignore.

### GitHub Secret Scanning and Push Protection

GitHub can detect secrets in commits automatically. Enable both features for every repository:

- **Secret scanning** (Settings → Code security and analysis → Secret scanning): Scans existing commits and alerts when known secret formats are found (API keys, tokens, passwords for major providers). Enable for all repos.
- **Push protection** (Settings → Code security and analysis → Push protection): Blocks pushes that contain detected secrets *before* they reach the remote. This prevents the "secret in git history" problem entirely for supported secret types.

Push protection does not cover custom or proprietary secret formats. It is not a substitute for gitignore — it is a safety net.

### Pre-Commit Hooks

A pre-commit hook that scans for secret patterns before allowing a local commit adds another layer before code reaches the remote. Common tools:

- **gitleaks** — Fast, supports custom regex rules, works standalone or via pre-commit framework
- **detect-secrets** (Yelp) — Maintains a baseline of known false positives, reducing alert fatigue
- **trufflehog** — Scans for high-entropy strings and known credential patterns

Integration via the `pre-commit` framework:
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

Pre-commit hooks are optional but recommended. They do not replace gitignore — they catch what gitignore misses.

---

## Log Prefix for Security Events

Security-related events use their own prefixes. These are emitted by code at runtime:

| Prefix | Level | Meaning |
|---|---|---|
| `CONFIG_MISSING` | FATAL | A required credential or config value is not set |
| `SECRET_LOADED` | DEBUG | A secret was successfully retrieved (value never logged) |

Optional prefix — implement if your project benefits from explicit masking audit trails:

| Prefix | Level | Meaning |
|---|---|---|
| `CREDENTIAL_MASKED` | DEBUG | A value was masked before logging |

The masking helpers in the reference implementations silently replace secret values with `[REDACTED]` without emitting a log line. If your project requires an audit trail of masking events, add a `CREDENTIAL_MASKED` log line to the masking helper after each redaction.

### `GITIGNORE_WARN` — A Conversation Convention, Not a Runtime Event

Unlike the prefixes above, `GITIGNORE_WARN` is emitted by Claude during code generation — not by code at runtime. It exists to create a greppable signal in the conversation history when a gitignore gap is identified.

When writing code that creates, downloads, or writes files, confirm the output path or file pattern is covered by `.gitignore`. If it is not, log a `GITIGNORE_WARN` in the conversation before generating the code:

```
[WARN] GITIGNORE_WARN: Function 'export_results' writes to 'output/' — this path is not covered
by .gitignore. Add 'output/' to .gitignore before running this code.
```

This gives the user an explicit signal that a gitignore gap was identified, and the action required before proceeding. Do not implement this prefix in application code — it has no runtime equivalent.

---

## Reference Files

Load the appropriate reference file for implementation details. SKILL.md above is principles only.

- [🔑 Environment setup](./reference/env-setup.md) — `.env` / `config.local` patterns, `Get-Secret` helper, startup validation, credential masking in all three languages
- [🛡️ Gitignore patterns](./reference/gitignore-patterns.md) — Ready-to-use `.gitignore` blocks by category, template file convention, common mistakes, git history response procedure
