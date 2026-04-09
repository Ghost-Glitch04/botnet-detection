# Gitignore Patterns

Reference for repository gitignore standards.
Load this file when setting up a new repository, reviewing an existing gitignore, or any time code produces output files or handles credentials.

---

## Table of Contents

1. [The Standard Block](#the-standard-block) — Drop this into every new repo
2. [Patterns by Category](#patterns-by-category) — Reference when extending
3. [Template File Convention](#template-file-convention) — `.example` files that ARE committed
4. [Verification Checklist](#verification-checklist) — Confirm coverage before first run
5. [Common Mistakes](#common-mistakes) — Patterns that look right but don't work
6. [If a Secret Was Committed](#if-a-secret-was-committed) — Response procedure

---

## The Standard Block

Copy this entire block into `.gitignore` for every new repository. It covers all categories of sensitive files that scripts and applications typically produce or consume. Never remove security patterns (credentials, secrets, local config, logs, outputs). Language-specific sections can be removed or adjusted if they don't apply to your project.

```gitignore
# ============================================================
# REPOSITORY SECURITY — STANDARD GITIGNORE BLOCK
# This block is required in every repository.
# Never remove security patterns. Adjust language-specific sections as needed.
# ============================================================

# ------------------------------------------------------------
# CREDENTIALS AND SECRETS — NEVER COMMIT
# ------------------------------------------------------------
.env
.env.*
!.env.example

*.key
*.pem
*.p12
*.pfx
*.cer

secrets/
credentials/
*.secret
# Note: config.local.* files are covered in the LOCAL CONFIGURATION section below.

# ------------------------------------------------------------
# LOCAL CONFIGURATION — NEVER COMMIT
# ------------------------------------------------------------
config.local.*
*.local.json
*.local.yaml
*.local.yml
settings.local.*

# ------------------------------------------------------------
# SCRIPT / APPLICATION OUTPUT — MAY CONTAIN SENSITIVE DATA
# ------------------------------------------------------------
output/
outputs/
exports/
reports/
data/
downloads/
staging/

*.csv
*.xlsx
*.xls
*.out           # Generic output files produced by scripts or CLI tools

# ------------------------------------------------------------
# LOGS — MAY CONTAIN CREDENTIALS OR SENSITIVE DATA
# ------------------------------------------------------------
logs/
*.log
*.log.*

# ------------------------------------------------------------
# TEMPORARY AND CACHE FILES
# ------------------------------------------------------------
temp/
tmp/
cache/
*.tmp
*.cache

# ------------------------------------------------------------
# LANGUAGE-SPECIFIC — PYTHON
# ------------------------------------------------------------
__pycache__/
*.pyc
*.pyo
.venv/
venv/
*.egg-info/

# ------------------------------------------------------------
# LANGUAGE-SPECIFIC — NODE.JS
# ------------------------------------------------------------
node_modules/
.npm/
*.tgz

# ------------------------------------------------------------
# LANGUAGE-SPECIFIC — POWERSHELL
# ------------------------------------------------------------
*.ps1xml
# Note: PowerShell profile files that may contain tokens

# ------------------------------------------------------------
# LANGUAGE-SPECIFIC — JAVA / JVM
# ------------------------------------------------------------
target/
*.class
*.jar
*.war
# Note: *.jar and *.war ignore all Java archives, including vendored
# dependencies some legacy projects check in. If your project commits
# JARs deliberately (e.g., a lib/ directory), add a ! exception:
#   !lib/*.jar

# ------------------------------------------------------------
# LANGUAGE-SPECIFIC — GO
# ------------------------------------------------------------
vendor/
# Note: Some Go projects deliberately commit vendor/ for reproducible
# builds without network access. Delete this line if your project vendors.

# ------------------------------------------------------------
# LANGUAGE-SPECIFIC — RUST
# ------------------------------------------------------------
# target/ already covered above (shared with Java)
Cargo.lock
# Note: Cargo.lock should only be gitignored for library crates.
# For binary projects, delete this line when setting up the repo
# and commit Cargo.lock for reproducible builds.

# ------------------------------------------------------------
# DEVELOPMENT TOOL ARTIFACTS
# ------------------------------------------------------------
.vscode/settings.json
# Note: .vscode/settings.json may contain extension configs with tokens.
# Commit .vscode/extensions.json (extension recommendations) but not settings.

.idea/
*.suo
*.user
.DS_Store

# ------------------------------------------------------------
# WINDOWS FILESYSTEM ARTIFACTS
# ------------------------------------------------------------
Thumbs.db
desktop.ini
$RECYCLE.BIN/
```

---

## Patterns by Category

Use these when extending the standard block for project-specific needs.

### Credentials and Secrets

These patterns extend the standard block. Entries marked with `(+)` are additions not already in the standard block; the rest are repeated here for completeness when copy-pasting this section independently.

```gitignore
# Named credential files (+)
*-credentials.*
*-secrets.*
*-keys.*
auth.json
token.json
bearer.txt

# Certificate files (standard block includes *.key, *.pem, *.p12, *.pfx, *.cer)
*.key
*.pem
*.p12
*.pfx
*.cer
*.crt            # (+) not in standard block
*.csr            # (+) not in standard block
```

### Cloud Provider Patterns

```gitignore
# Azure
*.publishsettings
ServiceConfiguration.*.cscfg

# AWS
.aws/credentials
.aws/config

# GCP
*-service-account.json
*-credentials.json
gcloud/
```

### Environment-Specific Files

```gitignore
# Environment-specific data directories
clients/
client-data/
tenants/

# Named export files
*-export.*
*-report.*
*-extract.*

# Tenant or environment-specific config
tenant-*.json
tenant-*.yaml
env-*.local.*
```

### Database and API Exports

```gitignore
# Database exports
*.sql
*.db
*.sqlite
*.sqlite3
*.bak
dump/
dumps/

# API response caches
*.response.json
api-cache/
response-cache/
```

### Infrastructure Files

```gitignore
# Terraform state (contains credentials)
*.tfstate
*.tfstate.*
.terraform/
terraform.tfvars
*.tfvars

# Ansible vaults and inventory
*.vault
inventory/
hosts

# Docker environment files
docker-compose.override.yml
*.env.docker
```

### Container and Build Artifacts

```gitignore
# Docker
.docker/
*.tar

# Build outputs
dist/
build/
out/
bin/
```

---

## Template File Convention

Every gitignored configuration file must have a committed `.example` counterpart. This is how collaborators know what they need to set up.

| Gitignored (never commit) | Committed template |
|---|---|
| `.env` | `.env.example` |
| `config.local.json` | `config.example.json` |
| `settings.local.yaml` | `settings.example.yaml` |

### The `!` Exception Syntax

Use the `!` prefix to explicitly commit template files even when their pattern is blocked:

```gitignore
# Block all .env variants
.env
.env.*

# Explicitly allow the template
!.env.example
```

Without the `!` exception, `.env.example` would be blocked by `.env.*`.

### What Template Files Must Contain

A template file is documentation. It must:
- List every variable or field the real file requires
- Use empty values or clearly fake placeholders — never real values
- Include a comment at the top explaining how to use it
- Stay current — updated in the same commit as any change to the code that uses it

**Good `.env.example`:**
```bash
# Copy this file to .env and fill in real values.
# NEVER commit .env — it is covered by .gitignore.

API_CLIENT_ID=
API_CLIENT_SECRET=
DB_PASSWORD=
```

**Bad `.env.example` — do not do this:**
```bash
# These are examples — use your own values
API_CLIENT_ID=abc123-real-looking-id
API_CLIENT_SECRET=def456-real-looking-secret
```
Real-looking placeholder values cause confusion about whether they're real. Use empty values.

---

## Verification Checklist

Run this before the first run of any new code, and when adding code to an existing repo.

**Step 1 — Confirm gitignore exists:**
```bash
ls -la .gitignore
# Should exist at repo root
```

**Step 2 — Confirm credential files are covered:**
```bash
git check-ignore -v .env
git check-ignore -v config.local.json
# Each should return the matching gitignore rule
```

**Step 3 — Confirm output directory is covered:**
```bash
git check-ignore -v output/
git check-ignore -v logs/
# Each should return the matching gitignore rule
```

**Step 4 — Create covered files and confirm they don't appear in git status:**
```bash
touch .env
touch config.local.json
mkdir -p output logs
git status
# .env, config.local.json, output/, logs/ should NOT appear as untracked
```

Once confirmed, remove the test files — do not leave empty stubs in the working directory.

> **Warning:** Only remove files you created in this step. If `.env` or `config.local.json` already existed with real values before you ran `touch`, do not delete them — `touch` only updated their timestamp.

```bash
# Bash / Linux / macOS
rm .env config.local.json

# PowerShell (Windows)
Remove-Item .env, config.local.json
```

**Step 5 — Confirm template files ARE tracked:**
```bash
git ls-files .env.example
git ls-files config.example.json
# Each should return the filename if tracked.
# If nothing is returned, the file is not tracked — add and commit it:
#   git add .env.example config.example.json
#   git commit -m "Add environment and config templates"
```

Note: `git status` is not reliable here — a committed, clean file shows nothing in `git status`, which looks the same as "file doesn't exist." `git ls-files` is the correct tool to confirm a file is tracked.

If any step fails, fix the gitignore before proceeding.

---

## Common Mistakes

These patterns look correct but have subtle problems.

### Mistake 1 — Trailing slash omitted for directories

```gitignore
# Wrong — only ignores a file named 'logs', not the directory contents
logs

# Correct — ignores the directory and everything inside it
logs/
```

### Mistake 2 — Pattern too narrow

```gitignore
# Wrong — only ignores this one file
.env

# Better — ignores all .env variants, but explicitly allows the template
.env
.env.*
!.env.example
```

### Mistake 3 — Nested gitignore confusion

Git processes multiple `.gitignore` files (repo root, subdirectories). A pattern in a subdirectory `.gitignore` only applies within that subdirectory. Put security-critical patterns in the root `.gitignore` to ensure they apply everywhere.

### Mistake 4 — Already-tracked files

**Gitignore has no effect on files already tracked by git.** If a file was ever committed, adding it to `.gitignore` does not remove it from the repo or its history. To stop tracking a currently-tracked file:

```bash
git rm --cached .env          # stops tracking without deleting the local file
git commit -m "Remove .env from tracking"
```

Then add the gitignore entry. But if the file contained real credentials, they are still in git history — see the response procedure below.

### Mistake 5 — Assuming `.gitignore` protects from tools

`.gitignore` only governs git. AI coding assistants, IDE extensions, and other tools read the filesystem directly. A `.env` file that is gitignored is still readable by any tool with filesystem access. Set file permissions separately:

```powershell
# PowerShell — restrict .env to current user only
$acl = Get-Acl ".env"
$acl.SetAccessRuleProtection($true, $false)  # disable inheritance
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $env:USERNAME, "Read,Write", "Allow"
)
$acl.SetAccessRule($rule)
Set-Acl ".env" $acl
```

```bash
# Bash/Linux/macOS — owner read/write only
chmod 600 .env
```

---

## If a Secret Was Committed

**The secret is compromised. Gitignoring or deleting the file does not fix this.**

Follow this sequence:

### Step 1 — Revoke and rotate immediately

Before doing anything else — before cleaning git history, before notifying anyone — revoke the exposed credential and issue a new one. The old credential is compromised the moment it touches a commit. Assume it has already been seen.

| Credential type | Where to rotate |
|---|---|
| OAuth / API key | The service's developer console or admin panel |
| Cloud provider key (AWS/Azure/GCP) | Cloud provider's IAM / credential management console |
| Database password | Database admin tool or hosting provider dashboard |
| Service account password | Identity provider admin (Active Directory, Okta, etc.) |
| SSH key | Remove from `~/.ssh/authorized_keys` on target servers; generate new keypair |

### Step 2 — Make the repo private (if it isn't already)

Limits further exposure while you clean up. Does not protect anyone who already cloned.

### Step 3 — Audit access

Check who has cloned or forked the repo. GitHub → Insights → Traffic shows clone counts but not who. If the repo is shared with the team, assume all team members and any service integrations have the credential.

### Step 4 — Notify per incident response procedure

Report to your organization's security contact. This is not optional even for "minor" exposures.

### Step 5 — Clean git history (optional, complex)

Rewriting git history removes the secret from future clones but does not help anyone who already cloned. Only worth doing if the repo is relatively new, hasn't been cloned widely, and the team can coordinate re-cloning.

```bash
# Using BFG Repo Cleaner (simpler than git filter-branch)
# Replace the secret value before running
bfg --replace-text secrets.txt
git reflog expire --expire=now --all
git gc --prune=now --aggressive
git push --force
```

After rewriting:
- All collaborators must delete their local clone and re-clone
- GitHub Actions caches and Pages deployments may retain old history
- GitHub support can help with additional cleanup

**Do not do this** unless you have confirmed the new credential is in place and working first.

### Step 6 — Add correct gitignore and proceed

Only after the credential is rotated and the incident is reported: add the gitignore entry, stop tracking the file (`git rm --cached`), commit the fix.
