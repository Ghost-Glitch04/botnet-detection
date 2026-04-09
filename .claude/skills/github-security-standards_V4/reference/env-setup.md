# Environment Setup Patterns

Reference for credential and configuration loading standards.
Load this file when writing any code that uses credentials, connects to external services, or reads environment-specific configuration.

---

## Table of Contents

1. [File Templates](#file-templates) — `.env.example` and `config.example.json`
2. [PowerShell Patterns](#powershell-patterns) — `Get-Secret`, config loading, masking, validation
3. [Bash Patterns](#bash-patterns) — `get_secret`, config loading, masking, validation
4. [Python Patterns](#python-patterns) — `get_secret`, config loading, masking, validation
5. [Secrets Manager Migration Notes](#secrets-manager-migration-notes)

---

## File Templates

### `.env.example`

This file is committed to the repo. It documents every credential the project needs without containing real values. Keep it current — update it in the same commit as any code change that adds a new credential dependency.

```bash
# ============================================================
# ENVIRONMENT CONFIGURATION TEMPLATE
# Copy this file to .env and fill in real values.
# NEVER commit .env — it is gitignored.
# ============================================================

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

### `config.example.json`

This file is committed to the repo. It documents operational configuration — non-secret values that vary per person or environment. Safe to log at DEBUG level.

Copy this file to `config.local.json` and fill in real values. Never commit `config.local.json` — it is covered by `.gitignore`.

```json
{
  "environment": "",
  "output_base_path": "",
  "log_base_path": ""
}
```

> **Customization note:** The `config.example.json` shown above is a minimal starting point. All values are empty to follow the same convention as `.env.example` — collaborators fill in their own values after copying to `config.local.json`. Add fields appropriate to your project — organization names, feature flags, threshold values, external service URLs that aren't secrets, etc. If a field has a universally correct default (not environment-specific), document it in a comment in the README rather than pre-filling the template. The `required_fields` parameter in each language's `load_local_config` helper controls which fields are validated at startup. Adjust this list per project.

> **Windows users:** Replace `output_base_path` and `log_base_path` with absolute Windows paths if needed, using forward slashes or escaped backslashes: `"C:/Users/YourName/exports"` or `"C:\\Users\\YourName\\exports"`. The defaults above use relative paths which work on all platforms.

### Startup Note

Both files must exist in the repo root before any code that uses them is committed. The `.gitignore` entry covering the real files must already be in place.

---

## PowerShell Patterns

### `Get-Secret` Helper

Define this in the helpers section of every script that uses credentials. It is the only way credentials should be accessed — never reference `$env:VARIABLE_NAME` directly in script logic.

```powershell
#region ============================================================
# HELPER: Get-Secret
# Purpose : Retrieve a credential from the local .env environment.
#           Fails fast with CONFIG_MISSING if the value is absent.
#           Designed to be replaced with a secrets manager lookup
#           when that integration is available — callers unchanged.
# Inputs  : -Name (string) — the environment variable name
# Outputs : The secret value as a string
# Throws  : Terminating error if the secret is not set (callers
#           should not catch this — a missing secret is fatal).
# Depends : Write-Log (or substitute your project's logging function)
# NEVER   : Log the return value. Not even partially.
#
# WHY THROW INSTEAD OF EXIT:
#   exit 1 inside a function terminates the entire PowerShell host,
#   including interactive sessions and calling scripts. throw produces
#   a terminating error that stops the pipeline (like exit) when run
#   at the top level, but can be caught by a wrapper script that needs
#   to do cleanup before exiting. The Write-Log FATAL call still fires
#   before the throw, so the log file records the failure.
#endregion ==========================================================

function Get-Secret {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    $value = [System.Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        $msg = "CONFIG_MISSING: Required secret '$Name' is not set. Copy .env.example to .env and fill in the value."
        Write-Log $msg -Level FATAL
        throw $msg
    }
    Write-Log "SECRET_LOADED: $Name retrieved successfully" -Level DEBUG
    return $value
}

# Usage:
# $clientId     = Get-Secret "API_CLIENT_ID"
# $clientSecret = Get-Secret "API_CLIENT_SECRET"
```

> **Logging dependency:** This helper calls `Write-Log`. If your project uses a different logging function, replace the `Write-Log` calls accordingly. The important contract is: log the *name* at DEBUG, never the *value*, and log a FATAL message before throwing on missing secrets.

### Load `.env` at Script Start

PowerShell does not natively source `.env` files. Load them explicitly in the main block bootstrap, before operational phases, after the log file path is set.

```powershell
#region ============================================================
# HELPER: Import-DotEnv
# Purpose : Load .env file into process environment variables.
#           Skips blank lines and comments. Strips surrounding quotes
#           from values (single or double). Does not overwrite
#           existing environment variables (system env takes precedence).
# Inputs  : -Path (string, default '.\.env')
#           -Required (bool, default $true) — if $false, silently skips
#           when .env is absent. Use for projects that may not need credentials.
# Outputs : Environment variables set in current process scope
# Throws  : Terminating error if .env file is not found
# Depends : Write-Log (or substitute your project's logging function;
#           log file path must be set before calling)
#
# ORDERING NOTE:
#   Import-DotEnv runs after the log file path is set, so Write-Log
#   is safe to call. If you move this call earlier in your bootstrap
#   sequence (before logging is initialized), switch Write-Log calls
#   to Write-Host until your log file is assigned.
#endregion ==========================================================

function Import-DotEnv {
    param(
        [string]$Path = ".\.env",
        [bool]$Required = $true
    )
    if (-not (Test-Path $Path)) {
        if (-not $Required) {
            Write-Log "ENV_SKIPPED: .env file not found at '$Path' — skipping (not required)" -Level DEBUG
            return
        }
        $msg = "CONFIG_MISSING: .env file not found at '$Path'. Copy .env.example to .env and fill in values."
        Write-Log $msg -Level FATAL
        throw $msg
    }
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        # Skip blank lines and comments
        if ($line -and $line -notmatch '^#') {
            $parts = $line -split '=', 2
            if ($parts.Count -eq 2) {
                $varName  = $parts[0].Trim()
                $varValue = $parts[1].Trim()
                # Strip surrounding quotes — .env files commonly use
                # KEY="value" or KEY='value'. Without stripping, the
                # quotes become part of the value and break API calls.
                if ($varValue.Length -ge 2 -and
                    (($varValue.StartsWith('"') -and $varValue.EndsWith('"')) -or
                     ($varValue.StartsWith("'") -and $varValue.EndsWith("'")))) {
                    $varValue = $varValue.Substring(1, $varValue.Length - 2)
                }
                # Don't overwrite if already set in the system environment
                if (-not [System.Environment]::GetEnvironmentVariable($varName)) {
                    [System.Environment]::SetEnvironmentVariable($varName, $varValue, "Process")
                }
            }
        }
    }
    Write-Log "ENV_LOADED: .env file loaded from '$Path'" -Level DEBUG
}
```

### Load `config.local.json`

```powershell
#region ============================================================
# HELPER: Import-LocalConfig
# Purpose : Load config.local.json into a script-scoped object and
#           validate that required fields are present and non-empty.
#           Fails fast if the file is missing, or if any required
#           field is absent or null — provides the example file name
#           and the missing field name in the error message.
# Inputs  : -Path (string, default '.\config.local.json')
#           -RequiredFields (string[], default @('environment','output_base_path'))
# Outputs : $script:Config (PSCustomObject of config values)
# Throws  : Terminating error if file is missing or required fields are empty
# Depends : Write-Log (or substitute your project's logging function)
#endregion ==========================================================

function Import-LocalConfig {
    param(
        [string]$Path = ".\config.local.json",
        [string[]]$RequiredFields = @('environment', 'output_base_path')
    )
    if (-not (Test-Path $Path)) {
        $msg = "CONFIG_MISSING: Local config not found at '$Path'. Copy config.example.json to config.local.json and fill in values."
        Write-Log $msg -Level FATAL
        throw $msg
    }

    $script:Config = Get-Content $Path -Raw | ConvertFrom-Json

    # Validate required fields — fail fast with the exact missing field name
    # so the error message tells the user exactly what to fix in their config file.
    foreach ($field in $RequiredFields) {
        if ([string]::IsNullOrWhiteSpace($script:Config.$field)) {
            $msg = "CONFIG_MISSING: Required field '$field' is not set in '$Path'. Update config.local.json."
            Write-Log $msg -Level FATAL
            throw $msg
        }
    }

    # Log validated fields — safe because config.local.json holds operational
    # values, not secrets, and log files are covered by .gitignore.
    $logParts = @()
    foreach ($field in $RequiredFields) {
        if ($script:Config.PSObject.Properties[$field]) {
            $logParts += "$field='$($script:Config.$field)'"
        }
    }
    if ($logParts.Count -eq 0) {
        $logParts += "Fields=$($RequiredFields.Count) validated"
    }
    Write-Log "CONFIG_LOADED: $($logParts -join ' | ')" -Level DEBUG
}
```

### Credential Masking Helper

Use this when building any log message that might include parameter values. Never log `$PSBoundParameters` or similar wholesale parameter dumps.

```powershell
#region ============================================================
# HELPER: Get-MaskedParams
# Purpose : Return a sanitized string of parameter values safe to log.
#           Any parameter whose name matches a known-secret pattern
#           is replaced with [REDACTED].
# Inputs  : -Params (hashtable of parameter name/value pairs)
# Outputs : A single log-safe string
# Depends : None
# Patterns: Canonical list from SKILL.md — update both if adding patterns.
#endregion ==========================================================

function Get-MaskedParams {
    param(
        [hashtable]$Params
    )
    $secretPatterns = @('key','secret','password','token','credential','pwd','apikey','auth','bearer','conn_str','connection_string','certificate','pat','sas')
    $parts = foreach ($key in $Params.Keys) {
        $isSecret = $secretPatterns | Where-Object { $key.ToLower() -like "*$_*" }
        $displayValue = if ($isSecret) { '[REDACTED]' } else { $Params[$key] }
        "$key='$displayValue'"
    }
    return $parts -join ' | '
}

# Usage:
# Write-Log "PARAMS: $(Get-MaskedParams @{
#     InputPath        = $InputPath
#     DryRun           = $DryRun
#     ApiClientId      = $ApiClientId
#     ApiClientSecret  = $ApiClientSecret
# })" -Level INFO
#
# Output: InputPath='C:\data\input.csv' | DryRun='False' |
#         ApiClientId='abc-123' | ApiClientSecret='[REDACTED]'
```

### Main Block Bootstrap (Security Section)

Add this to the main block bootstrap section, before the first operational phase:

```powershell
# --- Security bootstrap ---
# Load .env and local config before any code that needs credentials or config.
Import-DotEnv -Path ".\.env"
Import-LocalConfig -Path ".\config.local.json"
# To customize required fields for your project:
# Import-LocalConfig -Path ".\config.local.json" -RequiredFields @('tenant_name','api_base_url')
# For projects that may not need credentials:
# Import-DotEnv -Path ".\.env" -Required $false
```

---

## Bash Patterns

### `get_secret` Helper

```bash
# ============================================================
# HELPER: get_secret
# Purpose : Retrieve a credential from the environment.
#           Fails fast with CONFIG_MISSING if absent.
#           Designed for secrets manager replacement — callers unchanged.
# Args    : VARIABLE_NAME
# Returns : Secret value via stdout only (capture with $())
# Depends : log()
# NEVER   : Log the return value.
#
# IMPORTANT — stdout discipline:
#   This function uses stdout as its return channel. All log()
#   calls are redirected to stderr (>&2) so they do NOT pollute
#   the captured value when called as: VAR=$(get_secret "NAME")
#   Without >&2, the log line would be prepended to the secret
#   value, producing a corrupted, unusable string.
# ============================================================
get_secret() {
    local name="$1"
    local value="${!name:-}"
    if [[ -z "$value" ]]; then
        log FATAL "CONFIG_MISSING: Required secret '$name' is not set. Copy .env.example to .env and fill in the value." >&2
        exit 1
    fi
    log DEBUG "SECRET_LOADED: $name retrieved successfully" >&2
    echo "$value"   # stdout only — the caller captures this value
}

# Usage:
# CLIENT_ID=$(get_secret "API_CLIENT_ID")
# CLIENT_SECRET=$(get_secret "API_CLIENT_SECRET")
```

> **Logging dependency:** This helper calls `log()`. If your project uses a different logging function, replace accordingly. The key contract: all log output goes to stderr (`>&2`), never to stdout (which is the return channel).

### Load `.env` at Script Start

Add to the configuration block, after argument parsing:

```bash
# ============================================================
# Load .env file
# Strips surrounding quotes (single or double) from values.
# ============================================================
load_dotenv() {
    local env_file="${1:-.env}"
    local required="${2:-true}"    # pass "false" to skip silently when absent
    if [[ ! -f "$env_file" ]]; then
        if [[ "$required" == "false" ]]; then
            echo "[DEBUG] ENV_SKIPPED: .env file not found at '$env_file' — skipping (not required)" >&2
            return 0
        fi
        # Use echo to stderr, not log() — the logging system may not be
        # initialized yet when load_dotenv runs (e.g., if log path comes from config).
        echo "[FATAL] CONFIG_MISSING: .env file not found at '$env_file'. Copy .env.example to .env and fill in values." >&2
        exit 1
    fi
    # Export each non-comment, non-blank line.
    # IFS='=' with two variables: key gets the part before the first '=',
    # value gets everything after it (including any further '=' characters,
    # which is correct for base64 values and connection strings).
    while IFS='=' read -r key value; do
        # Skip blank lines and comments
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        # Strip inline comments and surrounding whitespace.
        # NOTE: Only strips # preceded by a space — this is the standard .env
        # convention for inline comments. Stripping on any # (%%#*) would
        # silently corrupt passwords, hex colors, base64 values, and URL
        # fragments that legitimately contain #.
        value="${value%% #*}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        # Strip surrounding quotes — .env files commonly use KEY="value"
        # or KEY='value'. Without stripping, the quotes become part of
        # the value and break API calls.
        if [[ ${#value} -ge 2 ]]; then
            case "$value" in
                \"*\") value="${value:1:${#value}-2}" ;;
                \'*\') value="${value:1:${#value}-2}" ;;
            esac
        fi
        # Don't overwrite variables already set in the environment
        [[ -z "${!key:-}" ]] && export "$key=$value"
    done < "$env_file"
    # Use echo to stderr here too — the logging system may not be initialized yet.
    echo "[DEBUG] ENV_LOADED: .env file loaded from '$env_file'" >&2
}

# In configuration block, after argument parsing:
load_dotenv ".env"
# For projects that may not need credentials:
# load_dotenv ".env" "false"
```

### Load `config.local.json`

Bash doesn't parse JSON natively — `jq` is required. Install it before using Bash scripts with `config.local.json`. The helper fails fast with a clear install instruction if `jq` is not found.

```bash
# ============================================================
# HELPER: load_local_config
# Purpose : Load config.local.json values into global variables.
#           Fails fast if the file is missing or jq is not installed.
#           jq is required — a warning-and-continue would leave all
#           config variables unset, violating fail-fast.
# Args    : CONFIG_FILE (default ./config.local.json)
# Globals : Sets variables based on your project's config fields.
#           Customize the field extraction and required fields
#           sections below for each project.
# Depends : jq (required), log()
# Install : sudo apt install jq  /  brew install jq  /  winget install jqlang.jq
#
# CUSTOMIZATION: Edit the two marked sections below for your project:
#   1. Field extraction — add/remove jq reads as needed
#   2. Required fields — add/remove field names in REQUIRED_FIELDS
#   Fields not listed in REQUIRED_FIELDS are treated as optional
#   (read from the file but not validated — they may be "null").
# ============================================================
load_local_config() {
    local config_file="${1:-./config.local.json}"

    if [[ ! -f "$config_file" ]]; then
        log FATAL "CONFIG_MISSING: Local config not found at '$config_file'. Copy config.example.json to config.local.json."
        exit 1
    fi

    if ! command -v jq &>/dev/null; then
        log FATAL "CONFIG_MISSING: jq is required to parse config.local.json but is not installed. Install it with: sudo apt install jq  OR  brew install jq  OR  winget install jqlang.jq"
        exit 1
    fi

    # --- Field extraction (customize for your project) ---
    ENVIRONMENT=$(jq -r '.environment' "$config_file")
    OUTPUT_BASE_PATH=$(jq -r '.output_base_path' "$config_file")
    LOG_BASE_PATH=$(jq -r '.log_base_path // empty' "$config_file")
    # Note: 'jq -r .field // empty' returns an empty string instead of "null"
    # when the field is absent. Use this for optional fields.

    # --- Required fields validation (customize for your project) ---
    local REQUIRED_FIELDS=("environment:$ENVIRONMENT" "output_base_path:$OUTPUT_BASE_PATH")
    local log_parts=""
    for entry in "${REQUIRED_FIELDS[@]}"; do
        local field_name="${entry%%:*}"
        local field_value="${entry#*:}"
        if [[ -z "$field_value" || "$field_value" == "null" ]]; then
            log FATAL "CONFIG_MISSING: '$field_name' is not set in '$config_file'."
            exit 1
        fi
        log_parts+="$field_name='$field_value' | "
    done

    log DEBUG "CONFIG_LOADED: ${log_parts% | }"
}
```

### Credential Masking

```bash
# ============================================================
# HELPER: mask_params
# Purpose : Build a log-safe string of variable name=value pairs.
#           Variables matching secret patterns are replaced with [REDACTED].
# Patterns: Canonical list from SKILL.md — update both if adding patterns.
# Usage   : log INFO "PARAMS: $(mask_params INPUT_PATH DRY_RUN API_CLIENT_SECRET)"
# ============================================================
mask_params() {
    local secret_patterns="key secret password token credential pwd apikey auth bearer conn_str connection_string certificate pat sas"
    local result=""
    for var_name in "$@"; do
        local is_secret=false
        # tr is used here instead of ${var_name,,} (bash 4+ only) for portability.
        # macOS ships with bash 3.2; some minimal environments use /bin/sh.
        local var_lower
        var_lower=$(echo "$var_name" | tr '[:upper:]' '[:lower:]')
        for pattern in $secret_patterns; do
            if [[ "$var_lower" == *"$pattern"* ]]; then
                is_secret=true
                break
            fi
        done
        local display_value
        if [[ "$is_secret" == "true" ]]; then
            display_value="[REDACTED]"
        else
            display_value="${!var_name:-unset}"
        fi
        result+="$var_name='$display_value' | "
    done
    echo "${result% | }"
}

# Usage:
# Pass variable NAMES (not values) — the function uses indirect expansion
# (${!var_name}) to look up each value at call time.
#
# log INFO "PARAMS: $(mask_params INPUT_PATH DRY_RUN API_CLIENT_SECRET)"
#
# Output: INPUT_PATH='/data/input.csv' | DRY_RUN='false' |
#         API_CLIENT_SECRET='[REDACTED]'
```

---

## Python Patterns

### `get_secret` Helper

```python
# ============================================================
# HELPER: get_secret
# Purpose : Retrieve a credential from the environment.
#           Fails fast with CONFIG_MISSING if absent.
#           Designed for secrets manager replacement — callers unchanged.
# Args    : name (str) — environment variable name
#           logger (logging.Logger)
# Returns : Secret value as string
# Depends : logger
# NEVER   : Log the return value.
# ============================================================
def get_secret(name: str, logger: logging.Logger) -> str:
    value = os.getenv(name)
    if not value or not value.strip():
        logger.critical(f"CONFIG_MISSING: Required secret '{name}' is not set. Copy .env.example to .env and fill in the value.")
        sys.exit(1)
    logger.debug(f"SECRET_LOADED: {name} retrieved successfully")
    return value

# Usage:
# client_id     = get_secret("API_CLIENT_ID", logger)
# client_secret = get_secret("API_CLIENT_SECRET", logger)
```

### Load `.env` at Script Start

Install `python-dotenv` for the preferred implementation:

```bash
pip install python-dotenv
```

The helper below uses `python-dotenv` if available and falls back to manual parsing if it is not installed. The fallback handles most common `.env` file formats but is less robust — installing the library is recommended for any code that will be shared or run in multiple environments.

```python
# ============================================================
# HELPER: load_dotenv
# Purpose : Load .env file into os.environ.
#           Uses python-dotenv if available; falls back to manual
#           parsing if not installed. The fallback strips surrounding
#           quotes (single or double) from values.
#           Call before setup_logger so log path can come from .env.
# Args    : env_path (Path, default Path('.env'))
#           required (bool, default True) — if False, silently returns
#           when .env is absent. Use for projects that may not need credentials.
# Depends : None
# ============================================================
def load_dotenv(env_path: Path = Path(".env"), required: bool = True) -> None:
    if not env_path.exists():
        if not required:
            return
        print(f"[FATAL] CONFIG_MISSING: .env file not found at '{env_path}'. "
              f"Copy .env.example to .env and fill in values.")
        sys.exit(1)

    try:
        from dotenv import load_dotenv as _load
        _load(dotenv_path=env_path, override=False)
    except ImportError:
        # Manual fallback if python-dotenv is not installed
        with env_path.open() as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    key, _, value = line.partition("=")
                    key = key.strip()
                    # Strip inline comments: only strip # preceded by a space.
                    # Stripping on any # would silently corrupt passwords,
                    # hex colors, base64 values, and URL fragments that
                    # legitimately contain #.
                    if " #" in value:
                        value = value[:value.index(" #")]
                    value = value.strip()
                    # Strip surrounding quotes — .env files commonly use
                    # KEY="value" or KEY='value'. Without stripping, the
                    # quotes become part of the value and break API calls.
                    if len(value) >= 2 and (
                        (value[0] == '"' and value[-1] == '"') or
                        (value[0] == "'" and value[-1] == "'")
                    ):
                        value = value[1:-1]
                    if key and key not in os.environ:    # don't overwrite existing env vars
                        os.environ[key] = value

# Call in main() before setup_logger:
# load_dotenv(Path(".env"))
# For projects that may not need credentials:
# load_dotenv(Path(".env"), required=False)
```

### Load `config.local.json`

```python
# ============================================================
# HELPER: load_local_config
# Purpose : Load config.local.json into a dict and validate that
#           required fields are present and non-empty.
#           Fails fast if the file is missing, or if any required
#           field is absent or null — provides the exact field name
#           in the error message so the user knows what to fix.
#           Safe to log — log files are covered by .gitignore (logs/ and *.log
#           in the standard block). config.local.json holds operational values,
#           not secrets, but the gitignore on logs is what prevents this from
#           reaching the repo.
# Args    : config_path (Path, default Path('config.local.json'))
#           required_fields (list[str], default ['environment', 'output_base_path'])
#           logger (logging.Logger, optional — uses print if None)
# Returns : dict of config values (all required fields guaranteed present)
# Depends : logger (optional)
# ============================================================
def load_local_config(config_path: Path = Path("config.local.json"),
                      required_fields: list = None,
                      logger: logging.Logger = None) -> dict:
    if required_fields is None:
        required_fields = ["environment", "output_base_path"]

    if not config_path.exists():
        msg = (f"CONFIG_MISSING: Local config not found at '{config_path}'. "
               f"Copy config.example.json to config.local.json and fill in values.")
        if logger:
            logger.critical(msg)
        else:
            print(f"[FATAL] {msg}")
        sys.exit(1)

    import json
    with config_path.open() as f:
        config = json.load(f)

    # Validate required fields — fail fast with the exact missing field name
    for field in required_fields:
        value = config.get(field)
        if value is None or str(value).strip() == "":
            msg = (f"CONFIG_MISSING: Required field '{field}' is not set in '{config_path}'. "
                   f"Update config.local.json.")
            if logger:
                logger.critical(msg)
            else:
                print(f"[FATAL] {msg}")
            sys.exit(1)

    # Log whichever required fields are present
    log_parts = []
    for field in required_fields:
        if field in config:
            log_parts.append(f"{field}='{config[field]}'")
    if not log_parts:
        log_parts.append(f"fields={len(required_fields)} validated")
    if logger:
        logger.debug(f"CONFIG_LOADED: {' | '.join(log_parts)}")
    return config
```

### Credential Masking Helper

```python
# ============================================================
# HELPER: mask_params
# Purpose : Build a log-safe dict with secrets replaced by [REDACTED].
#           Use when logging args, config, or any parameter collection.
# Args    : params (dict) — parameter names and values
# Returns : dict safe for logging
# Depends : None
# Patterns: Canonical list from SKILL.md — update both if adding patterns.
# ============================================================
SECRET_PATTERNS = {
    "key", "secret", "password", "token", "credential", "pwd", "apikey",
    "auth", "bearer", "conn_str", "connection_string", "certificate",
    "pat", "sas",  # Personal Access Tokens; Azure Shared Access Signature tokens
}

def mask_params(params: dict) -> dict:
    masked = {}
    for k, v in params.items():
        is_secret = any(pattern in k.lower() for pattern in SECRET_PATTERNS)
        masked[k] = "[REDACTED]" if is_secret else v
    return masked

# Usage in main() instead of logging vars(args) wholesale:
# logger.info(f"PARAMS: {mask_params(vars(args))}")
```

### Main Block Bootstrap (Security Section)

```python
def main() -> None:
    args = parse_args()

    # --- Security bootstrap ---
    # Load credentials and config before setup_logger in case log path comes from config.
    # logger is not passed here — it doesn't exist yet. Both functions use print()
    # for fatal errors when logger is None. This is intentional, not an oversight.
    load_dotenv(Path(".env"))
    config = load_local_config(Path("config.local.json"))
    # To customize required fields for your project:
    # config = load_local_config(Path("config.local.json"),
    #                            required_fields=["tenant_name", "api_base_url"])

    # Logger setup (after dotenv so LOG_DIR can come from environment)
    from datetime import datetime
    log_dir = Path(config.get("log_base_path", "./logs"))
    log_path = log_dir / f"script-{datetime.now():%Y%m%d-%H%M%S}.log"
    logger = setup_logger(log_path, debug_mode=args.debug)

    # Log params with masking — never log raw args that may contain secrets
    logger.info(f"PARAMS: {mask_params(vars(args))}")
```

---

## Secrets Manager Migration Notes

When an external secrets manager is available, the migration is localized to one function per language. All calling code remains unchanged.

This section shows the migration pattern for several common secrets managers. Each example replaces only the body of the `Get-Secret` / `get_secret` function — no calling code changes.

> **Before using these stubs in production:** The code below shows only the replacement logic — the minimum needed to illustrate the migration. Each stub requires error handling before it is production-ready. Add: unavailability checks (secrets manager unreachable), missing-secret handling (name not found returns null or empty), authentication failure handling, and logging consistent with the security standards. The stubs below will throw unhandled exceptions or return corrupted values without this work.

> **Bootstrapping note:** The stubs reference connection credentials (URLs, tokens) as environment variables. These are themselves credentials — creating a chicken-and-egg problem if the goal is to eliminate the `.env` file entirely. In practice, secrets manager connection credentials are typically provided by a different mechanism than the secrets they retrieve: a machine identity, a service account token injected by the deployment platform, or a single bootstrap secret that unlocks all others. Plan this bootstrap path before migrating.

### Pattern: Secret Server (Datto / Delinea)

**PowerShell:**
```powershell
function Get-Secret {
    param([Parameter(Mandatory)][string]$Name)
    # NOTE: Add error handling before production use — see warning above.
    $secret = Get-TssSecret -SecretServer $env:SECRET_SERVER_URL -Id (
        Find-TssSecret -SecretServer $env:SECRET_SERVER_URL -SearchText $Name
    ).Id
    return $secret.GetCredential().GetNetworkCredential().Password
}
```

**Bash:**
```bash
get_secret() {
    local name="$1"
    # NOTE: Add error handling before production use — see warning above.
    local value
    value=$(curl -sf -H "Authorization: Bearer $SS_TOKEN" \
        "$SECRET_SERVER_URL/api/v1/secrets?filter.searchText=$name" \
        | jq -r '.records[0].value')
    echo "$value"
}
```

**Python:**
```python
def get_secret(name: str, logger: logging.Logger) -> str:
    # NOTE: Add error handling before production use — see warning above.
    response = requests.get(
        f"{os.getenv('SECRET_SERVER_URL')}/api/v1/secrets",
        params={"filter.searchText": name},
        headers={"Authorization": f"Bearer {os.getenv('SS_TOKEN')}"}
    )
    return response.json()["records"][0]["value"]
```

### Pattern: HashiCorp Vault

**PowerShell:**
```powershell
function Get-Secret {
    param([Parameter(Mandatory)][string]$Name)
    # NOTE: Add error handling before production use — see warning above.
    # Requires the Vault CLI or a REST client.
    $response = Invoke-RestMethod -Uri "$env:VAULT_ADDR/v1/secret/data/$Name" `
        -Headers @{ "X-Vault-Token" = $env:VAULT_TOKEN }
    return $response.data.data.value
}
```

**Bash:**
```bash
get_secret() {
    local name="$1"
    # NOTE: Add error handling before production use — see warning above.
    local value
    value=$(curl -sf -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/secret/data/$name" \
        | jq -r '.data.data.value')
    echo "$value"
}
```

**Python:**
```python
def get_secret(name: str, logger: logging.Logger) -> str:
    # NOTE: Add error handling before production use — see warning above.
    import hvac
    client = hvac.Client(url=os.getenv("VAULT_ADDR"), token=os.getenv("VAULT_TOKEN"))
    response = client.secrets.kv.v2.read_secret_version(path=name)
    return response["data"]["data"]["value"]
```

### Pattern: AWS Secrets Manager

**PowerShell:**
```powershell
function Get-Secret {
    param([Parameter(Mandatory)][string]$Name)
    # NOTE: Add error handling before production use — see warning above.
    # Requires AWS.Tools.SecretsManager module and Set-AWSCredential
    return (Get-SECSecretValue -SecretId $Name).SecretString
}
```

**Bash:**
```bash
get_secret() {
    local name="$1"
    # NOTE: Add error handling before production use — see warning above.
    # Requires AWS CLI configured with credentials.
    local value
    value=$(aws secretsmanager get-secret-value --secret-id "$name" \
        --query 'SecretString' --output text)
    echo "$value"
}
```

**Python:**
```python
def get_secret(name: str, logger: logging.Logger) -> str:
    # NOTE: Add error handling before production use — see warning above.
    import boto3
    client = boto3.client("secretsmanager", region_name=os.getenv("AWS_REGION", "us-east-1"))
    response = client.get_secret_value(SecretId=name)
    return response["SecretString"]
```

### Pattern: Azure Key Vault

**PowerShell:**
```powershell
function Get-Secret {
    param([Parameter(Mandatory)][string]$Name)
    # NOTE: Add error handling before production use — see warning above.
    # Requires Az.KeyVault module and Connect-AzAccount
    return (Get-AzKeyVaultSecret -VaultName $env:AZURE_KEYVAULT_NAME -Name $Name).SecretValue |
        ConvertFrom-SecureString -AsPlainText
}
```

**Bash:**
```bash
get_secret() {
    local name="$1"
    # NOTE: Add error handling before production use — see warning above.
    # Requires Azure CLI and 'az login'.
    local value
    value=$(az keyvault secret show \
        --vault-name "$AZURE_KEYVAULT_NAME" --name "$name" \
        --query 'value' --output tsv)
    echo "$value"
}
```

**Python:**
```python
def get_secret(name: str, logger: logging.Logger) -> str:
    # NOTE: Add error handling before production use — see warning above.
    from azure.identity import DefaultAzureCredential
    from azure.keyvault.secrets import SecretClient
    client = SecretClient(
        vault_url=f"https://{os.getenv('AZURE_KEYVAULT_NAME')}.vault.azure.net",
        credential=DefaultAzureCredential()
    )
    return client.get_secret(name).value
```

The team migration process: update the helper function once, test, deploy. No calling code changes.
