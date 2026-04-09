# Python Scripting Patterns

Reference for Ghost's scripting standards applied to Python.
Load this file when writing any Python script.

---

## Script Header Template

```python
#!/usr/bin/env python3
"""
Script  : script_name.py
Purpose : Brief description of what this script does.
Author  : Ghost
Created : 2025-03-27
Version : 1.0.0

Usage:
    python script_name.py --input /path/to/input
"""

import argparse
import csv
import logging
import os
import platform
import sys
import time
import traceback
from contextlib import contextmanager
from pathlib import Path
```

---

## Error Code Reference

```python
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

## Logger Setup Helper

```python
# ============================================================
# HELPER: setup_logger
# Purpose : Configure logging to stdout and log file.
#           DEBUG always written to file; console level controlled
#           by debug_mode flag.
# Args    : log_path (Path), debug_mode (bool)
# Returns : logging.Logger
# Depends : None
# ============================================================
def setup_logger(log_path: Path, debug_mode: bool = False) -> logging.Logger:
    log_path.parent.mkdir(parents=True, exist_ok=True)

    logger = logging.getLogger(__name__)
    logger.setLevel(logging.DEBUG)

    fmt = logging.Formatter("[%(asctime)s] [%(levelname)s] %(message)s", datefmt="%Y-%m-%d %H:%M:%S")

    file_handler = logging.FileHandler(log_path)
    file_handler.setLevel(logging.DEBUG)   # always full detail in file
    file_handler.setFormatter(fmt)

    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.DEBUG if debug_mode else logging.INFO)
    console_handler.setFormatter(fmt)

    logger.addHandler(file_handler)
    logger.addHandler(console_handler)
    return logger
```

---

## Unit Timer Helper

```python
# ============================================================
# HELPER: unit_timer (context manager)
# Purpose : Log entry, exit, and duration for any unit.
#           On exception: logs error with traceback at DEBUG level.
# Args    : logger, unit_name (str)
# Usage   : with unit_timer(logger, "validate_input"):
# Depends : logger
# ============================================================

@contextmanager
def unit_timer(logger: logging.Logger, unit_name: str):
    logger.info(f"UNIT_START: {unit_name}")
    start = time.perf_counter()
    try:
        yield
    except Exception as exc:
        duration = time.perf_counter() - start
        logger.error(f"UNIT_FAILED: {unit_name} | Error: {exc} | Duration: {duration:.3f}s")
        logger.debug(f"STACK_TRACE:\n{traceback.format_exc()}")
        raise
    else:
        duration = time.perf_counter() - start
        logger.info(f"UNIT_END: {unit_name} | Duration: {duration:.3f}s")
```

**Input context limitation:** The `unit_timer` context manager logs the unit name and exception on failure, but it cannot capture the input values being processed — those exist only inside the `with` block. To satisfy the exception capture standard (which requires logging input values in scope), log inputs explicitly at the start of the unit body:

```python
def process_records(records: list, logger: logging.Logger) -> list:
    with unit_timer(logger, "process_records"):
        logger.debug(f"process_records | input_count={len(records)} | first_id={records[0].get('id') if records else 'N/A'}")
        # ... unit logic ...
```

This ensures input context appears in the log file before any failure, making the log self-contained for diagnosis even though `unit_timer` itself can't capture it.

---

## invoke_with_retry Helper

```python
# ============================================================
# HELPER: invoke_with_retry
# Purpose : Execute a callable with exponential backoff retry.
#           Distinguishes transient failures (retry) from exhaustion (exit 50).
# Args    : operation_name (str), func (callable), logger,
#           max_attempts (int, default 3), delay_seconds (float, default 5)
# Returns : Return value of func on success
# Depends : logger
# ============================================================
def invoke_with_retry(operation_name: str, func, logger: logging.Logger,
                      max_attempts: int = 3, delay_seconds: float = 5.0):
    for attempt in range(1, max_attempts + 1):
        try:
            logger.debug(f"RETRY: {operation_name} | Attempt {attempt} of {max_attempts}")
            return func()
        except Exception as exc:
            if attempt == max_attempts:
                logger.error(f"RETRY_EXHAUSTED: {operation_name} | All {max_attempts} attempts failed | Last error: {exc}")
                sys.exit(50)
            wait = delay_seconds * (2 ** (attempt - 1))
            logger.warning(f"RETRY_WAIT: {operation_name} | Attempt {attempt} failed | Waiting {wait:.1f}s | Error: {exc}")
            time.sleep(wait)

# Usage:
# result = invoke_with_retry("Graph API call", lambda: get_user(user_id), logger)
```

---

## Unit Pattern

```python
# ============================================================
# UNIT: validate_input
# Purpose : Confirm input file exists and is readable
# Args    : input_path (Path)
# Returns : None (raises SystemExit on failure)
# Depends : None
# ============================================================
def validate_input(input_path: Path, logger: logging.Logger) -> None:
    with unit_timer(logger, "validate_input"):
        if not input_path.exists():
            logger.error(f"INPUT_NOT_FOUND: '{input_path}' does not exist.")
            sys.exit(10)

        if not input_path.is_file():
            logger.error(f"INPUT_NOT_FILE: '{input_path}' is not a file.")
            sys.exit(10)

        try:
            input_path.open("r").close()
        except PermissionError:
            logger.error(f"INPUT_NOT_READABLE: No read permission on '{input_path}'.")
            sys.exit(11)
```

---

## Dependency Documentation Pattern

When a unit depends on output from another:

```python
# ============================================================
# UNIT: process_records
# Purpose : Transform validated records into output format
# Args    : records (list) — produced by load_records()
# Returns : list of processed records
# Depends : load_records() — must run first and return non-empty list
# ============================================================
def process_records(records: list, logger: logging.Logger) -> list:
    with unit_timer(logger, "process_records"):
        if not records:
            logger.fatal("DEPENDENCY_MISSING: process_records received empty records. Was load_records() skipped or did it fail?")
            sys.exit(20)

        # ... logic ...
        return processed
```

---

## invoke_phase_start / invoke_phase_gate Helpers

```python
# ============================================================
# HELPER: invoke_phase_start
# Purpose : Record phase start time and log phase entry
# Args    : phase_name (str), logger
# Returns : float — phase start timestamp (pass to invoke_phase_gate)
# Depends : logger
# ============================================================
def invoke_phase_start(phase_name: str, logger: logging.Logger) -> float:
    phase_start = time.perf_counter()
    logger.info(f"PHASE_START: {phase_name}")
    return phase_start


# ============================================================
# HELPER: invoke_phase_gate
# Purpose : Log phase duration and stop cleanly if gate matches.
#           Always logs PHASE_END regardless of gate trigger.
#           Exit 0 — a gate stop is not a failure.
# Args    : phase_name (str), phase_start (float), stop_after (str),
#           logger, script_start (float), summary (str, optional)
# Depends : logger, script_start, phase_start timestamps
# ============================================================
def invoke_phase_gate(
    phase_name: str,
    phase_start: float,
    stop_after: str,
    logger: logging.Logger,
    script_start: float,
    summary: str = ""
) -> None:
    phase_duration = time.perf_counter() - phase_start
    if summary:
        logger.info(f"PHASE_SUMMARY: {phase_name} | {summary}")
    logger.info(f"PHASE_END: {phase_name} | Phase Duration: {phase_duration:.3f}s")

    if stop_after == phase_name:
        total_duration = time.perf_counter() - script_start
        logger.info(f"PHASE_GATE: Stopping cleanly after phase '{phase_name}' | Total Duration: {total_duration:.3f}s")
        sys.exit(0)
```

---

## Output Verification Helpers

`verify_file_output` is a helper — it does not wrap itself in `unit_timer` because it is called by higher-level verification functions that manage their own lifecycle logging. This avoids nested UNIT_START/UNIT_END pairs in the log.

```python
# ============================================================
# HELPER: verify_file_output
# Purpose : Confirm a file exists and meets minimum byte size
# Args    : path (Path), logger, min_bytes (int, default 1)
# Returns : None (raises SystemExit 40 on failure)
# Depends : logger
# ============================================================
def verify_file_output(path: Path, logger: logging.Logger, min_bytes: int = 1) -> None:
    if not path.exists():
        logger.error(f"VERIFY_FAILED: File not found | Path: '{path}'")
        sys.exit(40)

    size = path.stat().st_size
    if size < min_bytes:
        logger.error(f"VERIFY_FAILED: File too small | Path: '{path}' | Size: {size}B | Minimum: {min_bytes}B")
        sys.exit(40)

    logger.info(f"VERIFY_OK: File output | Path: '{path}' | Size: {size}B")


# ============================================================
# HELPER: verify_csv_output
# Purpose : Confirm a CSV exists, is non-empty, and has expected row count
# Args    : path (Path), logger, expected_rows (int, -1 = skip count check)
# Returns : None (raises SystemExit 40 on failure)
# Depends : verify_file_output, unit_timer
# ============================================================
def verify_csv_output(path: Path, logger: logging.Logger, expected_rows: int = -1) -> None:
    with unit_timer(logger, f"verify_csv_output:{path.name}"):
        verify_file_output(path, logger)

        with path.open(newline="") as f:
            reader = csv.reader(f)
            rows = list(reader)

        data_rows = len(rows) - 1  # subtract header
        if data_rows <= 0:
            logger.error(f"VERIFY_FAILED: CSV has no data rows | Path: '{path}'")
            sys.exit(40)

        if expected_rows >= 0 and data_rows != expected_rows:
            logger.warning(f"VERIFY_WARN: Row count mismatch | Expected: {expected_rows} | Actual: {data_rows} | Path: '{path}'")
        else:
            logger.info(f"VERIFY_OK: CSV output | Path: '{path}' | Rows: {data_rows}")
```

---

## Argument Parsing

```python
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="Path to input file")
    parser.add_argument("--log-dir", type=Path, default=Path("./logs"), help="Directory for log output")
    parser.add_argument(
        "--stop-after-phase",
        choices=["preflight", "collection", "processing", "output", "verification", "none"],
        default="none",
        help="Stop cleanly at the end of the named phase (for staged testing)"
    )
    parser.add_argument("--dry-run", action="store_true", help="Trace execution without writing outputs or calling APIs")
    parser.add_argument("--debug", action="store_true", help="Show DEBUG entries on console (always written to log file)")
    return parser.parse_args()
```

---

## Record-Level Error Logging Pattern

```python
# Stop-on-first-failure:
for record in records:
    try:
        process_single_record(record)
    except Exception as exc:
        logger.error(f"RECORD_FAILED: process_records | RecordId={record.get('id')} | RecordName='{record.get('displayName')}' | Error: {exc} | ExitCode: 20")
        logger.debug(f"STACK_TRACE:\n{traceback.format_exc()}")
        sys.exit(20)

# Fault-tolerant — collect all failures, report at end:
failures = []
for record in records:
    try:
        process_single_record(record)
    except Exception as exc:
        failures.append(f"RecordId={record.get('id')} | Error: {exc}")

if failures:
    for f in failures:
        logger.error(f"RECORD_FAILED: {f}")
    logger.error(f"UNIT_FAILED: process_records | {len(failures)} of {len(records)} records failed")
    sys.exit(20)
```

---

## Partial Success Evaluation Pattern

Use at the end of any fault-tolerant processing unit to classify the outcome explicitly. The failure threshold is defined in the script's configuration.

```python
# Configuration:
FAILURE_THRESHOLD_PCT = 10   # >10% failures = treat as full failure

# At the end of the processing unit:
fail_pct = round((len(failures) / len(records)) * 100, 1)

if not failures:
    logger.info(f"FULL_SUCCESS: process_records | {len(records)} of {len(records)} records processed")
elif fail_pct <= FAILURE_THRESHOLD_PCT:
    logger.warning(f"PARTIAL_SUCCESS: process_records | {len(records) - len(failures)} of {len(records)} succeeded | {len(failures)} failed ({fail_pct}%) | Threshold: {FAILURE_THRESHOLD_PCT}%")
else:
    logger.error(f"FAILURE: process_records | {len(failures)} of {len(records)} failed ({fail_pct}%) | Threshold exceeded: {FAILURE_THRESHOLD_PCT}%")
    sys.exit(20)
```

---

## Dry-Run Pattern

```python
if args.dry_run:
    logger.info(f"[DRY-RUN] Would export {len(records)} records to '{output_path}'")
else:
    export_records(records, output_path)
    logger.info(f"Exported {len(records)} records to '{output_path}'")
```

---

## Main Block Pattern

The Main Block brings everything together. Logger setup and environment snapshot happen before Phase 1 — they're infrastructure that must exist before `invoke_phase_start` can log. Everything after that follows the phased deployment model.

```python
# ============================================================
# MAIN
# Purpose : Set up logging infrastructure, then orchestrate all phases
# ============================================================
def main() -> None:
    args = parse_args()

    # --- Log infrastructure bootstrap ---
    from datetime import datetime
    log_path = args.log_dir / f"script-{datetime.now():%Y%m%d-%H%M%S}.log"
    logger = setup_logger(log_path, debug_mode=args.debug)

    script_start = time.perf_counter()
    logger.info(f"SCRIPT_START: {Path(__file__).name} | User: {os.getenv('USER') or os.getenv('USERNAME')} | Host: {platform.node()}")
    logger.info(f"ENV_SNAPSHOT: Python={platform.python_version()} | OS={platform.platform()} | WorkingDir={Path.cwd()} | ScriptPath={Path(__file__)}")
    logger.info(f"PARAMS: {vars(args)}")

    if args.dry_run: logger.warning("DRY-RUN MODE ACTIVE — no writes or API mutations will occur")
    if args.debug:   logger.info("DEBUG MODE ACTIVE — DEBUG entries will appear on console")

    try:
        # ================================================================
        # PHASE 1: PREFLIGHT
        # ================================================================
        phase_start = invoke_phase_start("preflight", logger)
        validate_input(args.input, logger)
        invoke_phase_gate("preflight", phase_start, args.stop_after_phase, logger, script_start,
                          summary=f"Input: {args.input}")

        # ================================================================
        # PHASE 2: COLLECTION
        # ================================================================
        phase_start = invoke_phase_start("collection", logger)
        records = load_records(args.input, logger)
        invoke_phase_gate("collection", phase_start, args.stop_after_phase, logger, script_start,
                          summary=f"Records: {len(records)}")

        # ================================================================
        # PHASE 3: PROCESSING
        # ================================================================
        phase_start = invoke_phase_start("processing", logger)
        processed = process_records(records, logger)
        invoke_phase_gate("processing", phase_start, args.stop_after_phase, logger, script_start,
                          summary=f"Records processed: {len(processed)}")

        # ================================================================
        # PHASE 4: OUTPUT
        # ================================================================
        phase_start = invoke_phase_start("output", logger)
        export_results(processed, logger, dry_run=args.dry_run)
        invoke_phase_gate("output", phase_start, args.stop_after_phase, logger, script_start,
                          summary=f"Output complete")

        total = time.perf_counter() - script_start
        logger.info(f"SCRIPT_COMPLETE: Success | Total Duration: {total:.3f}s")
        sys.exit(0)

    except SystemExit:
        raise
    except Exception as exc:
        total = time.perf_counter() - script_start
        logger.fatal(f"SCRIPT_FAILED: Unhandled error | {exc} | Total Duration: {total:.3f}s")
        logger.debug(f"STACK_TRACE:\n{traceback.format_exc()}")
        sys.exit(99)


if __name__ == "__main__":
    main()
```
