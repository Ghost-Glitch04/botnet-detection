---
name: scripting-standards
description: Apply Ghost's personal scripting standards when writing PowerShell, Bash, or Python scripts. Use this skill for ANY scripting or automation task — whether writing a new script from scratch, extending an existing one, debugging, or refactoring. Standards prioritize reliability, auditability, fail-fast behavior, phased deployment with graceful phase exits, modular unit design, helper functions, dependency documentation, performance timing, result verification, structured exception capture, dry-run mode, runtime debug verbosity, retry logic for transient failures, environment snapshots, and record-level error logging. Always apply these standards even if the user doesn't explicitly ask for them.
---

# Scripting Standards

Ghost's scripting philosophy: **code you can trust is code you can see — and verify**. Every script should be auditable, self-documenting, designed to surface its own failures clearly and immediately, and able to prove that its outputs are what they claim to be.

Apply these standards to all PowerShell, Bash, and Python work unless Ghost explicitly says otherwise.

---

## Pre-Flight: Permissions and Logging Setup

Before writing any functional code, identify what permissions and logging capabilities are needed and ask Ghost to enable them explicitly. Never assume access.

At minimum, ask about:
- Log file write permissions (path and rotation policy)
- Elevated execution rights if needed (e.g., `Set-ExecutionPolicy`, `sudo`)
- Access to any external systems, APIs, or paths the script will touch

State clearly what each permission enables and why it is needed.

---

## Script Template

Every new script follows this scaffold. Read this first — it shows how all the standards below fit together in a real script.

```
[SCRIPT HEADER — name, purpose, author, date, version]
[ERROR CODE REFERENCE — all exit codes documented]
[PARAMETERS — stop-after-phase, dry-run, debug flags for runtime control]
[CONFIGURATION — paths, constants, retry defaults, failure thresholds]
[HELPERS — log helper, phase start/gate, retry helper, unit timer]

[PHASE 1: PREFLIGHT]
  [UNIT: Initialize — logging setup, env snapshot, overall timer start]
  [UNIT: Verify Connection — confirm external service auth and scope]
  [UNIT: Validate Input — confirm inputs exist and are well-formed]
  [Phase Gate — "Preflight"]

[PHASE 2: DATA COLLECTION]
  [UNIT: Get Data — fetch/read source data; wrap external calls with retry helper]
  [UNIT: Verify Collection Output — confirm expected data was retrieved]
  [Phase Gate — "Collection"]

[PHASE 3: PROCESSING]
  [UNIT: Process Data — transform, enrich, evaluate]
  [  — log RECORD_FAILED with record ID on per-record errors]
  [  — evaluate PARTIAL_SUCCESS threshold at end of unit]
  [UNIT: Verify Processing Output — confirm processing produced expected results]
  [Phase Gate — "Processing"]

[PHASE 4: OUTPUT]
  [UNIT: Export Results — write files, update systems]
  [  — check dry-run flag before any write; log [DRY-RUN] if active]
  [UNIT: Verify Output Files — confirm outputs are correct]
  [Phase Gate — "Output"]

[MAIN — wires phases together, overall timer, final status log]
```

---

## Structure: Units

Break every script into clearly bounded **units** — discrete, named sections of functionality. A unit does one thing completely.

Each unit must be:
- **Labeled** with a prominent header comment
- **Self-contained** enough to be read, tested, and swapped independently
- **Documented** at the top with its purpose, inputs, outputs, and any dependencies

**PowerShell:**
```powershell
#region ============================================================
# UNIT: Validate-InputFiles
# Purpose : Ensure all required input files exist and are readable
# Inputs  : $InputPath (string)
# Outputs : $true / throws terminating error
# Depends : None
#endregion ==========================================================
```

**Bash:**
```bash
# ============================================================
# UNIT: validate_input_files
# Purpose : Ensure all required input files exist and are readable
# Inputs  : $INPUT_PATH
# Outputs : 0 (success) / exits with error
# Depends : None
# ============================================================
```

**Python:**
```python
# ============================================================
# UNIT: validate_input_files
# Purpose : Ensure all required input files exist and are readable
# Args    : input_path (Path)
# Returns : None (raises SystemExit on failure)
# Depends : None
# ============================================================
```

---

## Phased Deployment and Phase Gates

Scripts are built and tested in **phases** — ordered groups of units that represent a discrete, verifiable stage of work. Confirm each phase is solid before building on it.

### What a Phase Is

| Phase | Typical purpose |
|---|---|
| Phase 1: Preflight | Permissions, connections, input validation |
| Phase 2: Data Collection | Fetching, querying, reading inputs |
| Phase 3: Processing | Transforming, enriching, evaluating data |
| Phase 4: Output | Writing files, sending results, updating systems |

Define phases based on what makes sense to test independently, not to hit a fixed number.

### Phase Gates

Every phase boundary includes a **phase gate** — a flag (`--stop-after-phase` / `-StopAfterPhase`) that stops the script cleanly at the end of that phase. Stopping at a gate is exit code 0 — not a failure. It lets Ghost run one phase at a time, inspect results, then proceed.

Each phase also tracks its own start and end time. The gate logs both phase duration and total script duration unconditionally, so every phase's cost appears in every log.

### How Phases Appear in the Script

Example in PowerShell (see reference files for Bash and Python equivalents):

```powershell
# ================================================================
# PHASE 1: PREFLIGHT
# ================================================================
Invoke-PhaseStart -PhaseName "Preflight"
Verify-EntraConnection
Validate-InputFiles -Path $InputPath
Invoke-PhaseGate -PhaseName "Preflight" -Summary "Connection: verified | Input: $InputPath"
```

### Phase Log Output

Every phase produces three log lines unconditionally. A gate stop adds a fourth:

```
[INFO] PHASE_START:   Preflight
[INFO] PHASE_SUMMARY: Preflight | Connection: verified | Input records found: 847
[INFO] PHASE_END:     Preflight | Phase Duration: 3.2s
[INFO] PHASE_START:   Collection
[INFO] PHASE_END:     Collection | Phase Duration: 11.4s
[INFO] PHASE_GATE:    Stopping cleanly after phase 'Collection' | Total Duration: 14.6s
```

### Deploying Incrementally

Run the script phase by phase when first deploying:

1. Stop after Preflight — confirm connections and inputs are healthy
2. Stop after Collection — confirm data retrieval looks right
3. Continue through each phase until the full script runs end-to-end

See the language reference files for the complete phase start/gate implementations (`Invoke-PhaseStart` / `invoke_phase_start`).

### When Phasing Is Unnecessary

Not every script needs phase gates. Short utility scripts — a one-shot file converter, a quick lookup tool, a simple rename operation — don't benefit from four phases and a gate parameter. The overhead of phase timing and gate checks adds complexity that outweighs the debugging value.

Use phasing when the script has **two or more** of the following: external service calls, multi-step data transformations, file outputs that need verification, or a run time long enough that restarting from scratch is costly. If the script is short enough to read top-to-bottom in a single screen and has no external dependencies, skip phasing — the unit headers, logging, and error codes still apply.

---

## Logging

Logging is not optional — it is the primary tool for understanding why code behaved the way it did.

### Log Every Unit's Lifecycle
- **Entry:** log the unit name and the key inputs it received
- **Exit:** log that it completed and what it produced
- **Errors:** log the full context — error message, inputs in scope, line reference, exit code

### Log Levels

| Level | When to use |
|---|---|
| `DEBUG` | Detailed trace — always written to file; console-visible only with `--debug` flag |
| `INFO` | Normal progress — phase starts/ends, unit completions, verification results |
| `WARN` | Unexpected but recoverable — row count mismatch, retry attempt, partial success |
| `ERROR` | A unit failed — includes all context needed to reproduce the failure |
| `FATAL` | Script cannot continue — connection lost, dependency missing |

### Log Helper

Always implement logging as a reusable helper (`Write-Log`, `log()`, `setup_logger()`). The helper must:
- Write **all levels** to the log file, always
- **Suppress `DEBUG` from console** by default — promote to console only when `--debug` / `-DebugMode` is active
- Apply **consistent timestamp and level formatting** so logs are greppable

See the language reference files for the complete, current implementation:
- [📋 PowerShell — Write-Log helper](./reference/powershell.md)
- [🐧 Bash — log() helper](./reference/bash.md)
- [🐍 Python — setup_logger() helper](./reference/python.md)

---

## Helper Functions

When the same logic appears more than once, extract it into a named helper function. This keeps units clean, makes behavior predictable, and isolates changes to one place.

Helper functions should:
- Have a single, clear responsibility
- Be **defined** in a dedicated `# HELPERS` section after the configuration and error code blocks but before any executable code — in PowerShell and Bash, functions must be defined before they are called, so helpers must appear before the Main Block and any units that use them
- Include a brief comment describing purpose, inputs, and outputs
- Follow the same fail-fast principle as units

---

## Fail Fast

Units must fail immediately and loudly when something goes wrong. Never allow a failure to silently pass and corrupt downstream steps.

- Validate inputs at the start of each unit, before doing any work
- On failure: log a clear error, emit a distinct exit/error code, and stop
- Units that are dependencies for other units are especially critical — a quiet failure in a dependency creates a hard-to-trace chain. Fail fast there above all.

Use **distinct, documented exit codes** per failure type. Keep a code reference block at the top of every script:

```
# 0  = Success
# 10 = Input file not found
# 11 = Input file unreadable / malformed
# 20 = Unit / processing failure
# 30 = External service connection failed or unverified
# 40 = Output verification failed
# 50 = Retry exhausted — transient failure did not resolve
# 99 = Unexpected / unhandled error
```

---

## Exception Capture

A catch block that logs only the error message is half a diagnosis. Every exception must capture enough context to reproduce the failure without re-running the script.

Every catch block must record:
- **The error message** — what went wrong
- **The unit name** — where it went wrong
- **The input values in scope** — what was being processed when it failed
- **The stack trace or line reference** — where in the code it went wrong
- **The exit code** — which category of failure this is

Stack traces go at `DEBUG` level — always written to the log file, only visible on console when `--debug` is active.

The unit timer and exception capture pattern are intentionally combined in the reference files — the `finally` block ensures duration is always logged even when a unit throws:
- [📋 PowerShell — Unit Timer / Exception Capture Pattern](./reference/powershell.md)
- [🐧 Bash — Unit Timer / Exception Capture Pattern](./reference/bash.md)
- [🐍 Python — unit_timer context manager](./reference/python.md)

---

## Dry-Run Mode

Every script that writes files, calls APIs, or modifies systems must support a `--dry-run` / `-DryRun` flag. This traces the full execution path without any side effects — the single most useful tool for confirming a script will behave correctly before it does anything real.

In dry-run mode the script:
- Runs all validation and connection verification normally
- Logs every action it *would* take, prefixed with `[DRY-RUN]`
- Skips all writes, API mutations, and system changes
- Exits cleanly

Log `DRY-RUN MODE ACTIVE` prominently at script start. See the language reference files for the flag declaration and per-unit guard pattern.

---

## Debug Verbosity Flag

Every script must support a `--debug` / `-DebugMode` flag that promotes `DEBUG` log entries to the console at runtime, without editing the script. By default `DEBUG` writes to the log file only — the flag enables live trace visibility for active troubleshooting.

Log `DEBUG MODE ACTIVE` at script start when the flag is set. See the language reference files for the flag declaration and how the log helper implements it.

---

## Retry Logic for Transient Failures

Not every failure is a real failure. Network blips, rate limits, and token expiry are transient — they may succeed if retried after a short wait. Failing fast on these wastes a full run.

Use `Invoke-WithRetry` / `invoke_with_retry` for any operation that touches an external service. The retry helper must:
- Accept a configurable attempt count and initial delay
- Use exponential backoff (delay doubles each attempt)
- Log each attempt at `DEBUG` and each wait at `WARN`
- Log `RETRY_EXHAUSTED` and exit code 50 when all attempts fail

See the language reference files for the complete implementation and usage examples.

---

## Environment Snapshot at Startup

Log immediately after `SCRIPT_START`, before any units run. Capture: runtime version (PowerShell / Bash / Python), OS, user, host, working directory, script path, and all parameter values.

Every log file should be self-contained — someone reading it cold should be able to reconstruct the exact conditions the script ran under without asking.

The environment snapshot is built into the Initialize unit in all three language reference files.

---

## Result Verification

Completing a unit is not the same as confirming it worked. Verify that outputs are what they are expected to be before the next unit runs.

### Connection Verification (External Services)

Always verify a connection is live and authenticated before doing any dependent work. Confirm:
- Authenticated identity (the expected account or service principal)
- Correct tenant and scope
- Required permissions are present for the operations the script will perform

Log the verified identity and tenant — the audit trail should show *who* the script ran as, not just *that* it ran.

Connection verification is service-specific — each script should implement a verification unit tailored to the service it connects to. The PowerShell reference file includes a complete `Verify-EntraConnection` unit for Microsoft Graph as a reference pattern. For Bash and Python, follow the same structure: query the service for the current session identity, confirm scope, log the result with `VERIFY_OK` or `VERIFY_FAILED`, and exit 30 on failure.

### Output File Verification

After writing any file output, verify it before moving on. A file that exists but is empty is a silent failure. Check:
- File exists at the expected path
- File size is greater than zero
- Row/line count matches expected output count where applicable
- For CSVs: header row is present and column count is correct

### Verification as a Dedicated Unit

When output verification is non-trivial, give it its own named unit:

```
[UNIT: Export-Results]   → writes the file
[UNIT: Verify-Results]   → confirms the file is correct
```

Every verification logs `VERIFY_OK` or `VERIFY_FAILED` so results are easy to grep.

See the language reference files for the complete verification helper implementations:
- [📋 PowerShell](./reference/powershell.md) — `Verify-EntraConnection`, `Verify-CsvOutput`, `Verify-TextOutput`
- [🐧 Bash](./reference/bash.md) — `verify_file_output`, `verify_csv_output`
- [🐍 Python](./reference/python.md) — `verify_file_output`, `verify_csv_output`

---

## Record-Level Error Logging

When a unit processes a collection and one record fails, the log must identify the specific record. Without this, reproducing the failure requires re-running the full script and hoping the same record appears.

Log the failing record's identity — ID and display name at minimum — at the point of failure using the `RECORD_FAILED` prefix before exiting.

For fault-tolerant units that should process all records and report at the end, collect failures into a list and log the full set before exiting.

See the language reference files for both the stop-on-first-failure and fault-tolerant patterns.

---

## Partial Success Standard

When a script processes a collection and some records succeed while others fail, the outcome must be explicitly categorized — not left ambiguous.

Define a failure threshold in the script's configuration block (PowerShell example — see reference files for Bash and Python):

```powershell
[int]$FailureThresholdPct = 10   # >10% failures = treat as full failure
```

At the end of each processing unit, evaluate and log the outcome using one of three explicit labels:

| Outcome | Log level | Exit code | Meaning |
|---|---|---|---|
| `FULL_SUCCESS` | INFO | 0 | All records processed successfully |
| `PARTIAL_SUCCESS` | WARN | 0 | Some failures, but within threshold |
| `FAILURE` | ERROR | 20 | Failure rate exceeded threshold |

This makes the distinction between "a few expected failures" and "something is systematically wrong" auditable rather than implicit.

See the language reference files for the complete evaluation pattern:
- [📋 PowerShell](./reference/powershell.md) — Partial Success Evaluation Pattern
- [🐧 Bash](./reference/bash.md) — Partial Success Evaluation Pattern
- [🐍 Python](./reference/python.md) — Partial Success Evaluation Pattern

---

## Log Prefix Vocabulary

Every log entry uses a consistent prefix so logs are greppable and self-describing. Use these exact prefixes — don't invent new ones without adding them here.

| Prefix | Level | Meaning |
|---|---|---|
| `SCRIPT_START` | INFO | Script has begun; user, host, and version follow |
| `SCRIPT_COMPLETE` | INFO | Script finished successfully; total duration follows |
| `SCRIPT_FAILED` | FATAL | Unhandled error terminated the script |
| `ENV_SNAPSHOT` | INFO | Runtime environment captured (OS, version, working dir) |
| `PARAMS` | INFO | All parameter values at time of execution |
| `PHASE_START` | INFO | A named phase has begun |
| `PHASE_SUMMARY` | INFO | What the phase produced, logged before PHASE_END |
| `PHASE_END` | INFO | Phase complete; phase duration follows |
| `PHASE_GATE` | INFO | Script stopped cleanly at a requested phase boundary |
| `UNIT_START` | INFO | A named unit has begun; key inputs follow |
| `UNIT_END` | INFO | Unit complete; duration follows |
| `UNIT_FAILED` | ERROR | Unit failed; error, inputs, line number, exit code follow |
| `DEPENDENCY_MISSING` | FATAL | A required upstream unit did not run or produced no output |
| `VERIFY_OK` | INFO | A verification check passed |
| `VERIFY_FAILED` | ERROR | A verification check failed; path/detail follows |
| `VERIFY_WARN` | WARN | Verification passed but with an unexpected condition |
| `RECORD_FAILED` | ERROR | A specific record failed processing; record ID follows |
| `RETRY` | DEBUG | An operation is being attempted (attempt N of N) |
| `RETRY_WAIT` | WARN | An attempt failed; waiting before next retry |
| `RETRY_EXHAUSTED` | ERROR | All retry attempts failed |
| `STACK_TRACE` | DEBUG | Full exception stack trace (file always; console only in debug mode) |
| `[DRY-RUN]` | INFO | Action that would have occurred in a live run |
| `FULL_SUCCESS` | INFO | All records in a collection processed successfully |
| `PARTIAL_SUCCESS` | WARN | Some records failed, but within the configured threshold |
| `FAILURE` | ERROR | Record failure rate exceeded configured threshold |

**Useful grep patterns:**
```bash
# All failures in a run:
grep -E "UNIT_FAILED|RECORD_FAILED|VERIFY_FAILED|RETRY_EXHAUSTED|FAILURE" run.log

# Phase timing profile:
grep "PHASE_END" run.log

# Every record that failed:
grep "RECORD_FAILED" run.log

# Partial success outcomes:
grep -E "FULL_SUCCESS|PARTIAL_SUCCESS|FAILURE" run.log

# Full trace for one unit:
grep "validate_input" run.log
```

---

## When Something Isn't Working: Try Something Different

Repeating the same approach expecting a different result is not debugging — it's spinning. When a solution fails, the next attempt must be meaningfully different from the last one.

### The Rule

**If an approach has failed twice, do not try it a third time.** Stop, document what was tried and why it failed, then shift to a genuinely different strategy.

Different strategy means different at the level of approach, not just parameters. Changing a timeout value is a tweak. Switching from a direct API call to a batched queue is a different approach.

### How to Pivot

When stuck, work through this sequence before writing any new code:

1. **Name the failure clearly.** What did the error say? What did the logs show? Vague failures produce vague solutions.
2. **Identify the assumption that was wrong.** Every failed attempt rested on at least one false assumption. Find it.
3. **Generate at least two alternative approaches** before choosing one.
4. **Pick the approach most likely to surface new information** — a partial success that reveals why the original failed is more valuable than another clean failure.

Alternative angles when pivoting:
- Change the abstraction level (lower-level API instead of a wrapper, or vice versa)
- Change the authentication method or permission scope
- Decompose the failing unit further to isolate exactly which step breaks
- Add diagnostic-only instrumentation to observe what's actually happening before fixing it
- Consult the error code reference — a fresh read often reveals a misread exit code
- Try the operation manually to confirm the environment is what you think it is

### What Worked / What Didn't Log

Every attempt — successful or not — gets recorded in a `## Development Notes` block at the top of the script or in a companion `.notes.md` file. This is not optional — it is the institutional memory for the script.

Each entry must include:
- **Date and attempt number**
- **What was tried** — specific enough that someone else could reproduce it
- **Result** — FAILED or SUCCESS
- **Why it failed or succeeded** — the root cause, not just the symptom
- **What the next attempt will change** (for failures)

```text
## Development Notes

### [2025-03-27] Attempt 1 — Direct API call with default timeout
Tried : Single POST to /api/export with default 30s timeout
Result: FAILED — timeout on payloads > 5MB
Reason: Default timeout insufficient; large payloads exceed 30s consistently
Next   : Switch to chunked requests with configurable timeout param

### [2025-03-27] Attempt 2 — Chunked requests, $TimeoutSec = 120
Tried : Split payload into 500-record chunks, POST each with 120s timeout
Result: FAILED — auth token expired mid-batch on large datasets
Reason: Token lifetime (60min) shorter than full batch run time
Next   : Refresh token between chunks; different approach from attempt 1

### [2025-03-27] Attempt 3 — Chunked requests with token refresh per batch
Tried : Refresh auth token before each chunk, 120s timeout retained
Result: SUCCESS — reliable across all tested payload sizes
```

The notes block is also where edge cases discovered during testing get recorded, so the next session doesn't rediscover them the hard way.

---

## Reference Files

Load the appropriate file when writing or reviewing code for that language. These contain all complete, copy-paste-ready implementations — the SKILL.md above is principles only.

- [📋 PowerShell patterns](./reference/powershell.md) — Write-Log, Invoke-WithRetry, Invoke-PhaseStart/Gate, Verify-EntraConnection, Verify-CsvOutput, unit timer, dry-run, partial success evaluation, env snapshot
- [🐧 Bash patterns](./reference/bash.md) — log(), invoke_with_retry, invoke_phase_start/gate, verify helpers, dry-run, partial success evaluation, env snapshot
- [🐍 Python patterns](./reference/python.md) — setup_logger, invoke_with_retry, invoke_phase_start/gate, unit_timer, verify helpers, dry-run, partial success evaluation, env snapshot
