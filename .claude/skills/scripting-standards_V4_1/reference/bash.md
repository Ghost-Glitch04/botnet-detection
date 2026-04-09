# Bash Scripting Patterns

Reference for Ghost's scripting standards applied to Bash.
Load this file when writing any Bash script.

---

## Script Header Template

```bash
#!/usr/bin/env bash
# ============================================================
# SCRIPT  : script-name.sh
# PURPOSE : Brief description of what this script does.
# AUTHOR  : Ghost
# CREATED : 2025-03-27
# VERSION : 1.0.0
#
# USAGE   : ./script-name.sh --input /path/to/input
# ============================================================

set -euo pipefail   # Exit on error, unset vars, pipe failures
IFS=$'\n\t'         # Safer word splitting
```

---

## Error Code Reference Block

```bash
# ============================================================
# ERROR CODE REFERENCE
# 0  = Success
# 10 = Input file not found
# 11 = Input file unreadable / malformed
# 20 = Unit / processing failure (see log for which one)
# 30 = External service connection failed or unverified
# 40 = Output verification failed (file missing, empty, or malformed)
# 50 = Retry exhausted — transient failure did not resolve
# 99 = Unexpected / unhandled error
# ============================================================
```

---

## Configuration Block

```bash
# ============================================================
# CONFIGURATION
# ============================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"
readonly TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
readonly LOG_FILE="${SCRIPT_DIR}/logs/${SCRIPT_NAME%.sh}-${TIMESTAMP}.log"

# Ensure log directory exists before any logging (Phase helpers need it)
mkdir -p "$(dirname "$LOG_FILE")"

INPUT_PATH=""
STOP_AFTER_PHASE="none"
DRY_RUN=false
DEBUG_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)            INPUT_PATH="$2"; shift 2 ;;
        --stop-after-phase) STOP_AFTER_PHASE="$2"; shift 2 ;;
        --dry-run)          DRY_RUN=true; shift ;;
        --debug)            DEBUG_MODE=true; shift ;;
        *) echo "Unknown argument: $1"; exit 99 ;;
    esac
done
```

---

## log() Helper

```bash
# ============================================================
# HELPER: log
# Purpose : Write timestamped, leveled entries to file always;
#           DEBUG suppressed from console unless --debug is set.
# Args    : LEVEL (DEBUG|INFO|WARN|ERROR|FATAL), MESSAGE (string)
# Depends : LOG_FILE, DEBUG_MODE
# ============================================================
log() {
    local level="$1"; shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local entry="[$timestamp] [$level] $message"

    # Always write to file
    echo "$entry" >> "$LOG_FILE"

    # Suppress DEBUG from console unless debug mode active
    if [[ "$level" == "DEBUG" && "$DEBUG_MODE" != "true" ]]; then return; fi

    case "$level" in
        DEBUG) echo -e "\033[0;37m${entry}\033[0m" ;;
        INFO)  echo -e "\033[0;32m${entry}\033[0m" ;;
        WARN)  echo -e "\033[0;33m${entry}\033[0m" ;;
        ERROR) echo -e "\033[0;31m${entry}\033[0m" ;;
        FATAL) echo -e "\033[1;31m${entry}\033[0m" ;;
        *)     echo "$entry" ;;
    esac
}
```

---

## Initialization Unit

```bash
# ============================================================
# UNIT: initialize
# Purpose : Capture environment snapshot, announce active modes,
#           and start the script timer.
#           Log directory creation happens in the Configuration Block.
# Inputs  : LOG_FILE, DRY_RUN, DEBUG_MODE (globals)
# Outputs : SCRIPT_START set; environment logged
# Depends : log(), LOG_FILE (set in Configuration Block)
# ============================================================
initialize() {
    SCRIPT_START=$SECONDS
    log INFO "SCRIPT_START: $SCRIPT_NAME | User: $(whoami) | Host: $(hostname)"
    log INFO "ENV_SNAPSHOT: BashVersion=$BASH_VERSION | OS=$(uname -sr) | WorkingDir=$(pwd) | ScriptPath=${BASH_SOURCE[0]}"
    log INFO "PARAMS: INPUT_PATH='$INPUT_PATH' | STOP_AFTER_PHASE='$STOP_AFTER_PHASE' | DRY_RUN=$DRY_RUN | DEBUG_MODE=$DEBUG_MODE"
    [[ "$DRY_RUN"    == "true" ]] && log WARN "DRY-RUN MODE ACTIVE — no writes or system changes will occur"
    [[ "$DEBUG_MODE" == "true" ]] && log INFO "DEBUG MODE ACTIVE — DEBUG entries will appear on console"
}
```

---

## invoke_with_retry Helper

```bash
# ============================================================
# HELPER: invoke_with_retry
# Purpose : Run a command with exponential backoff retry.
# Args    : OPERATION_NAME, MAX_ATTEMPTS (default 3),
#           DELAY_SECONDS (default 5), COMMAND...
# Depends : log()
# ============================================================
invoke_with_retry() {
    local operation="$1"; shift
    local max_attempts="${1:-3}"; shift
    local delay="${1:-5}"; shift
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        (( attempt += 1 ))
        log DEBUG "RETRY: $operation | Attempt $attempt of $max_attempts"
        if "$@"; then return 0; fi
        if [[ $attempt -eq $max_attempts ]]; then
            log ERROR "RETRY_EXHAUSTED: $operation | All $max_attempts attempts failed"
            exit 50
        fi
        local wait=$(( delay * (2 ** (attempt - 1)) ))
        log WARN "RETRY_WAIT: $operation | Attempt $attempt failed | Waiting ${wait}s"
        sleep "$wait"
    done
}

# Usage:
# invoke_with_retry "API call" 3 5 curl -sf "$API_ENDPOINT"
```

---

## Unit Timer / Exception Capture Pattern

Bash has two exception capture approaches depending on the unit type.

**For validation units** — explicit checks with structured error messages at each failure point:

```bash
# ============================================================
# UNIT: validate_input
# Purpose : Confirm input file exists and is readable
# Inputs  : INPUT_PATH (global)
# Outputs : None (exits 10 on failure)
# Depends : None
# ============================================================
validate_input() {
    local unit_start=$SECONDS
    log INFO "UNIT_START: validate_input | input=$INPUT_PATH"

    if [[ -z "$INPUT_PATH" ]]; then
        log ERROR "UNIT_FAILED: validate_input | INPUT_PATH is empty | ExitCode: 10"
        exit 10
    fi

    if [[ ! -f "$INPUT_PATH" ]]; then
        log ERROR "UNIT_FAILED: validate_input | File not found: $INPUT_PATH | ExitCode: 10"
        exit 10
    fi

    if [[ ! -r "$INPUT_PATH" ]]; then
        log ERROR "UNIT_FAILED: validate_input | File not readable: $INPUT_PATH | ExitCode: 11"
        exit 11
    fi

    local unit_duration=$(( SECONDS - unit_start ))
    log INFO "UNIT_END: validate_input | Duration: ${unit_duration}s"
}
```

**For units that do real work** (API calls, file transforms, external commands) — use a subshell trap to capture unexpected failures with full context. This is Bash's equivalent of try/catch/finally:

```bash
# ============================================================
# UNIT: fetch_records
# Purpose : Retrieve records from external API
# Inputs  : API_ENDPOINT, AUTH_TOKEN (globals)
# Outputs : Sets RECORDS_FILE (global path to downloaded data)
# Depends : validate_input
# ============================================================
fetch_records() {
    local unit_start=$SECONDS
    local input_context="endpoint=$API_ENDPOINT"
    log INFO "UNIT_START: fetch_records | $input_context"

    # Set output path before subshell — variables set inside ( ) don't propagate
    RECORDS_FILE="${SCRIPT_DIR}/data/records-${TIMESTAMP}.json"

    # Subshell trap captures unexpected failures with structured context
    # The || captures the exit code without triggering set -e in the parent
    local exit_code=0
    (
        trap 'log ERROR "UNIT_FAILED: fetch_records | Error: command failed on line $LINENO | Command: $BASH_COMMAND | $input_context | ExitCode: 20"; exit 20' ERR

        invoke_with_retry "fetch_records" 3 5 curl -sf -H "Authorization: Bearer $AUTH_TOKEN" -o "$RECORDS_FILE" "$API_ENDPOINT"
    ) || exit_code=$?

    local unit_duration=$(( SECONDS - unit_start ))
    log INFO "UNIT_END: fetch_records | Duration: ${unit_duration}s"

    if [[ $exit_code -ne 0 ]]; then
        exit $exit_code
    fi
}
```

The key differences from validation units: the subshell `( ... )` isolates the ERR trap so it doesn't affect the rest of the script, the trap logs the unit name, the failing command (`$BASH_COMMAND`), the line number (`$LINENO`), the input values in scope, and the exit code. The `|| exit_code=$?` after the subshell is critical — without it, `set -e` (from the script header) would terminate the parent function the instant the subshell exits non-zero, skipping the `UNIT_END` log entirely. This idiom captures the exit code without triggering `errexit`. The duration is always logged regardless of success or failure — matching the `finally` block behavior in PowerShell and the `unit_timer` context manager in Python. Note that variables set inside a subshell do not propagate to the parent — set output paths and state variables before entering the subshell, and do only the risky work inside it.

---

## Record-Level Error Logging Pattern

```bash
# Stop-on-first-failure:
while IFS=',' read -r record_id record_name rest; do
    if ! process_single_record "$record_id" "$record_name"; then
        log ERROR "RECORD_FAILED: process_records | RecordId=$record_id | RecordName='$record_name' | ExitCode: 20"
        exit 20
    fi
done < "$INPUT_PATH"

# Fault-tolerant — collect all failures, report at end:
fail_count=0
total_count=0
while IFS=',' read -r record_id record_name rest; do
    (( total_count += 1 ))
    if ! process_single_record "$record_id" "$record_name"; then
        log ERROR "RECORD_FAILED: process_records | RecordId=$record_id | RecordName='$record_name'"
        (( fail_count += 1 ))
    fi
done < "$INPUT_PATH"

if [[ $fail_count -gt 0 ]]; then
    log ERROR "UNIT_FAILED: process_records | $fail_count of $total_count records failed"
    exit 20
fi
```

---

## Partial Success Evaluation Pattern

Use at the end of any fault-tolerant processing unit to classify the outcome explicitly. The failure threshold is defined in the configuration block.

```bash
# Configuration block:
FAILURE_THRESHOLD_PCT=10   # >10% failures = treat as full failure

# At the end of the processing unit:
fail_pct=$(( (fail_count * 100) / total_count ))

if [[ $fail_count -eq 0 ]]; then
    log INFO "FULL_SUCCESS: process_records | $total_count of $total_count records processed"
elif [[ $fail_pct -le $FAILURE_THRESHOLD_PCT ]]; then
    log WARN "PARTIAL_SUCCESS: process_records | $(( total_count - fail_count )) of $total_count succeeded | $fail_count failed (${fail_pct}%) | Threshold: ${FAILURE_THRESHOLD_PCT}%"
else
    log ERROR "FAILURE: process_records | $fail_count of $total_count failed (${fail_pct}%) | Threshold exceeded: ${FAILURE_THRESHOLD_PCT}%"
    exit 20
fi
```

---

## Dry-Run Pattern

```bash
if [[ "$DRY_RUN" == "true" ]]; then
    log INFO "[DRY-RUN] Would write $RECORD_COUNT records to $OUTPUT_PATH"
else
    write_output
    log INFO "Wrote $RECORD_COUNT records to $OUTPUT_PATH"
fi
```

---

## Dependency Documentation Pattern

When unit B depends on unit A:

```bash
# ============================================================
# UNIT: process_records
# Purpose : Transform records from validated input
# Inputs  : VALIDATED_DATA (global, set by validate_input)
# Outputs : PROCESSED_DATA (global)
# Depends : validate_input — MUST run first
# ============================================================
process_records() {
    if [[ -z "${VALIDATED_DATA:-}" ]]; then
        log FATAL "DEPENDENCY_MISSING: process_records requires VALIDATED_DATA. Was validate_input skipped?"
        exit 20
    fi
    # ... logic ...
}
```

---

## invoke_phase_start / invoke_phase_gate Helpers

```bash
# ============================================================
# HELPER: invoke_phase_start
# Purpose : Record phase start time and log phase entry
# Args    : PHASE_NAME
# Depends : log()
# ============================================================
invoke_phase_start() {
    local phase_name="$1"
    PHASE_START=$SECONDS
    log INFO "PHASE_START: $phase_name"
}

# ============================================================
# HELPER: invoke_phase_gate
# Purpose : Log phase duration and stop cleanly if gate matches.
#           Always logs PHASE_END regardless of gate trigger.
#           Exit 0 — a gate stop is not a failure.
# Args    : PHASE_NAME, SUMMARY (optional)
# Depends : STOP_AFTER_PHASE, PHASE_START, SCRIPT_START, log()
# ============================================================
invoke_phase_gate() {
    local phase_name="$1"
    local summary="${2:-}"
    local phase_duration=$(( SECONDS - PHASE_START ))

    [[ -n "$summary" ]] && log INFO "PHASE_SUMMARY: $phase_name | $summary"
    log INFO "PHASE_END: $phase_name | Phase Duration: ${phase_duration}s"

    if [[ "$STOP_AFTER_PHASE" == "$phase_name" ]]; then
        local total_duration=$(( SECONDS - SCRIPT_START ))
        log INFO "PHASE_GATE: Stopping cleanly after phase '$phase_name' | Total Duration: ${total_duration}s"
        exit 0
    fi
}
```

---

## Output Verification Helpers

```bash
# ============================================================
# HELPER: verify_file_output
# Purpose : Confirm a file exists and meets minimum size
# Args    : FILE_PATH, MIN_BYTES (optional, default 1)
# Outputs : 0 (ok) / exits 40 on failure
# Depends : log()
# ============================================================
verify_file_output() {
    local path="$1"
    local min_bytes="${2:-1}"

    if [[ ! -f "$path" ]]; then
        log ERROR "VERIFY_FAILED: File not found | Path: '$path'"
        exit 40
    fi

    local size
    size=$(wc -c < "$path")
    if [[ "$size" -lt "$min_bytes" ]]; then
        log ERROR "VERIFY_FAILED: File too small | Path: '$path' | Size: ${size}B | Minimum: ${min_bytes}B"
        exit 40
    fi

    log INFO "VERIFY_OK: File output | Path: '$path' | Size: ${size}B"
}

# ============================================================
# HELPER: verify_csv_output
# Purpose : Confirm a CSV exists, is non-empty, and has expected row count
# Args    : FILE_PATH, EXPECTED_ROWS (optional, -1 = skip count check)
# Outputs : 0 (ok) / exits 40 on failure
# Depends : log()
# ============================================================
verify_csv_output() {
    local path="$1"
    local expected_rows="${2:--1}"

    verify_file_output "$path"

    local row_count
    row_count=$(( $(wc -l < "$path") - 1 ))  # subtract header

    if [[ "$row_count" -le 0 ]]; then
        log ERROR "VERIFY_FAILED: CSV has no data rows | Path: '$path'"
        exit 40
    fi

    if [[ "$expected_rows" -ge 0 && "$row_count" -ne "$expected_rows" ]]; then
        log WARN "VERIFY_WARN: Row count mismatch | Expected: $expected_rows | Actual: $row_count | Path: '$path'"
    else
        log INFO "VERIFY_OK: CSV output | Path: '$path' | Rows: $row_count"
    fi
}
```

---

## Main Block Pattern

The Main Block brings everything together. All units are organized into phases with phase gates for incremental testing.

```bash
# ============================================================
# MAIN
# ============================================================
main() {
    # ================================================================
    # PHASE 1: PREFLIGHT
    # ================================================================
    invoke_phase_start "preflight"
    initialize
    validate_input
    invoke_phase_gate "preflight" "Input: $INPUT_PATH"

    # ================================================================
    # PHASE 2: COLLECTION
    # ================================================================
    invoke_phase_start "collection"
    collect_data
    invoke_phase_gate "collection" "Records: $RECORD_COUNT"

    # ================================================================
    # PHASE 3: PROCESSING
    # ================================================================
    invoke_phase_start "processing"
    process_records
    invoke_phase_gate "processing" "Records processed: $PROCESSED_COUNT"

    # ================================================================
    # PHASE 4: OUTPUT
    # ================================================================
    invoke_phase_start "output"
    export_results
    verify_file_output "$OUTPUT_PATH"
    invoke_phase_gate "output" "Output: $OUTPUT_PATH"

    local total_duration=$(( SECONDS - SCRIPT_START ))
    log INFO "SCRIPT_COMPLETE: Success | Total Duration: ${total_duration}s"
    exit 0
}

# Trap unexpected errors — captures line number and failing command
trap 'log FATAL "SCRIPT_FAILED: Unhandled error on line $LINENO | Command: $BASH_COMMAND"; exit 99' ERR

main "$@"
```
