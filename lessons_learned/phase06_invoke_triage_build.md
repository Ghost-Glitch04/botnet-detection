---
name: phase06_invoke_triage_build
description: Built modules/Invoke-BotnetTriage.ps1 — 4 sub-phases, 18 units, ~1100 lines. Caught 3 real bugs via incremental smoke-tests (gate exit, per-row CIM perf, service over-flagging).
type: reflection
---

# phase06_invoke_triage_build — `Invoke-BotnetTriage.ps1` Module Build

> **Scope:** Write `modules/Invoke-BotnetTriage.ps1` — the Phase 1 anchor module. 4 sub-phases (Preflight / Collection / Processing / Output), 18 units, JSON output, full standalone-paste support, no API dependencies.
> **Date:** 2026-04-09

---

## Applied Lessons

| Rule (file → heading) | Outcome | Note |
|------------------------|---------|------|
| phase05_shared_helpers.md#1 — parser validation in same step you wrote the file | **Applied**, clean first pass | Ran AST `ParseFile` immediately after `Write`. Zero parser errors. Followed up with dot-source smoke test (loaded `_Shared.ps1` + module, confirmed function defines with all 8 expected params). |
| phase05_shared_helpers.md#2 — smoke-test functions with non-trivial logic | **Triggered, found 3 real bugs** | Built progressive `pwsh -File` tempfile smoke tests: load → gate (`-StopAfterPhase Preflight`) → Collection → full pipeline. Each escalation caught a different bug. See "Bugs and Pitfalls" below. |
| phase05_shared_helpers.md#3 — never multi-line pwsh in bash double-quoted `-Command` | Applied | Every smoke test was a tempfile invoked with `pwsh -NoProfile -File output/_smoketest_*.ps1`. Zero quoting incidents this phase. |
| phase05_shared_helpers.md#7 — fail-loud ≠ fail-closed | Applied | Each unit wrapped in `Invoke-TriageUnit` which catches, logs `UNIT_FAILED`, appends to `$errors[]`, but never rethrows. A single CIM access-denied doesn't kill the whole triage. |
| phase05_shared_helpers.md#6 — standalone-paste degradation | Applied | Module ships with 5 inline helper stubs (`Write-Log`, `Test-IsPrivateIP`, `Get-ProcessDetails`, `Get-Secret`, `Resolve-Config`), each guarded by `if (-not (Get-Command X -ErrorAction SilentlyContinue))`. When pasted into a bare shell with no `_Shared.ps1`, the inline stubs activate. When dot-sourced via `_Shared.ps1`, the authoritative versions take precedence. |

---

## Sub-Phase A — Preflight (`U-ParamValidate`, `U-LoadConfig`, `U-LoadIOCs`)

### What went well

**Config-source detection works exactly as designed.** `Resolve-Config` returns either a parsed JSON object (file path) or a hashtable fallback (no file). The code does `$cfg -is [hashtable]` to flip `$script:ConfigSource` between `'file'` and `'inline-fallback'`. The dry-run smoke test logged `CONFIG_RESOLVED: source=file` correctly.

**Admin-elevation check is warn-only, not block.** First-responder context: an operator running through SentinelOne RemoteShell may not always be elevated. Hard-failing on non-admin would make the tool useless. Soft-warning lets the operator see they're getting partial data without aborting the run.

### Lessons

- **`-StopAfterPhase` short-circuit works on first try when implemented as a thrown error caught in the function body.** See Bug #1 below for *why* the obvious `exit 0` doesn't work.

---

## Sub-Phase B — Collection (8 units)

### What went well

**Per-unit fault tolerance is load-bearing.** `Invoke-TriageUnit` wraps each body in try/catch that logs `UNIT_START`, runs the body, logs `UNIT_END` with stopwatch duration, and on exception logs `UNIT_FAILED` + appends to `$errors[]`. None of the 8 units had a hard dependency on any other; if `Get-CimInstance Win32_Service` was access-denied, the next unit (`U-Autoruns`) still ran.

**Process snapshot caching cut Collection time 9× (97s → 11s).** See Bug #2 below for the discovery and fix.

### Lessons

- **For any unit that touches "live" Windows state per-row (connections, ports, sockets), build the lookup index ONCE at phase start, not per row.** The cost of one Get-CimInstance is dominated by WMI startup overhead, not row count. 1 query for 367 processes = ~1s. 99 queries for 1 process each = ~60s.
- **`Authenticode signer trust` is not a Phase 1 heuristic.** Without a comprehensive trusted-signers list (which is out of scope for Phase 1 since it requires per-engagement curation), any "untrusted signer" check will false-positive against legitimate third-party software. Limit signature checks to "Status -ne Valid" (i.e., truly unsigned or broken signature) and defer signer-trust to Phase 2.

---

## Sub-Phase C — Processing (`U-ApplyExclusions`, `U-ScoreFindings`, `U-CorrelateIOCs`, `U-ClassifyRisk`)

### What went well

**Score function handles both hashtable and pscustomobject weight shapes.** `triage-weights.json` parses as nested `[pscustomobject]` after `ConvertFrom-Json`, but the inline-fallback in `Resolve-Config` returns a `[hashtable]`. The inline `Get-FlagWeight` helper checks both shapes. Verified by running with file config (`source=file`) and getting non-zero scores.

**Verdict counts roundtrip cleanly through the JSON.** Real run produced verdict H=4 M=60 L=23, JSON readback shows the same counts. The classifier's High/Medium thresholds (50/25 from `triage-weights.json`) are observed end-to-end.

### Lessons

- **When a JSON file's structure is the only source of truth for a runtime calculation, both the file path and the inline-fallback path must produce structurally compatible objects.** The cheap fix is to make the inline fallback also a `[pscustomobject]`. The robust fix is to write the consumer code to handle both shapes via duck-typing — slightly more code, but resilient to future fallback restructuring.

---

## Sub-Phase D — Output (`U-WriteJson`, `U-WriteSummary`, `U-VerifyArtifacts`)

### What went well

**Dry-run prefix is consistent across all 3 units.** Every "would write" path is logged with `[DRY-RUN]` prefix and skipped, never silently swallowed. Real run produces a 42KB JSON; dry-run produces 0 bytes.

**`Verify-JsonOutput` catches its own contract.** The verify unit reads the JSON back, parses it, and confirms the 4 required top-level keys (`meta`, `verdict`, `findings`, `errors`). On the real run it logged `VERIFY_OK: ... Keys verified: 4`. This is the kind of cheap, end-of-pipeline check that catches "wrote a file but it's actually empty" bugs.

**Console summary uses ANSI colors for High/Medium/Low.** Operators triaging 10 hosts back-to-back via remote shell appreciate the visual hierarchy. The summary also surfaces the top 5 highest-scored findings, so the operator gets actionable signal without parsing the JSON.

### Lessons

- **Verification is a separate unit, not a side-effect of Write.** Treating verification as its own unit (`U-VerifyArtifacts`) gives it its own log line, its own duration, and its own failure mode (`exit 40`). When operators triage a failed run, "the JSON was written but didn't verify" is a different problem from "the write itself errored out."

---

## Bugs and Pitfalls

### 1. `Invoke-PhaseGate` called `exit 0` — would have killed the caller's session when the module is dot-sourced
<!-- tags: powershell,scoping,phase-gate -->

**The bug:** `_Shared.ps1`'s `Invoke-PhaseGate` ended with `exit 0` when `-StopAfterPhase` matched. That works fine for a script invoked via `pwsh -File foo.ps1` — the script exits, pwsh terminates, the OS gets exit code 0. But `Invoke-BotnetTriage` is **a function**, not a script. When the test harness dot-sourced the module and called `Invoke-BotnetTriage -StopAfterPhase Preflight`, the `exit 0` inside the helper killed the entire pwsh process — including the harness's `=== DRY-RUN END ===` trailer, which never printed. The bash exit code from the test harness was 0, looking like a clean success, but the harness post-conditions never ran.

**How it surfaced:** The very first `-StopAfterPhase Preflight` smoke test. The output stopped at `PHASE_GATE: Stopping cleanly...` and the trailer line was missing. That mismatch — gate logged but trailer not printed — was a precise tell that something between the gate and the function return had killed the process.

**The fix:** `Invoke-PhaseGate` now throws a tagged terminating error (`PhaseGateReached` ErrorRecord) instead of calling `exit`. The body of `Invoke-BotnetTriage` is wrapped in `try { ... } catch { if ($_.FullyQualifiedErrorId -eq 'PhaseGateReached') { return 0 } else { ... } }`. When run as a function: the catch fires, the function returns 0 cleanly, the caller's session survives. When run as a script: the script-level catch can do the same thing, then `exit 0`. Same observable behavior, no session-killing surprise.

**Why it matters:** The whole standalone-paste workflow depends on the module being dot-sourceable into an arbitrary pwsh session without side-effects on the host shell. `exit` from a helper called by a function is one of the worst-possible side-effects: it terminates the parent shell, taking any unrelated work in that session with it. An operator who pasted the module into a long-running RemoteShell session, then called it with `-StopAfterPhase Preflight` to test, would lose their entire shell.

**Lesson 1:** Helpers in a dot-sourced library MUST NOT call `exit`. The right pattern is "throw a tagged terminating error and let the caller decide what to do" — typically convert to a function `return` if called as a function, or convert to `exit` if called from script scope.

**Lesson 2:** The smoke-test signal ("trailer line missing") was specific enough to identify the cause. Trailer-line probes that bracket the action being tested (`=== START ===` / `=== END (rc=$rc) ===`) are a low-cost, high-signal way to detect "the function exited via a path you didn't expect." Adopt this pattern for any function smoke test that's expected to return cleanly.

---

### 2. `Get-ProcessDetails` called per-row → 65 seconds for 99 connections + 21 seconds for 39 listening ports
<!-- tags: powershell,performance,cim,wmi -->

**The bug:** `U-ConnectionsSnapshot` and `U-ListeningPorts` each called `Get-ProcessDetails -ProcessId $c.OwningProcess` inside their `foreach` loops. `Get-ProcessDetails` does `Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId"` followed by `Invoke-CimMethod GetOwner`. Each pair of WMI calls costs ~600ms-800ms — most of which is WMI startup, not the actual query. Cost: 99 connections × ~700ms = 65 seconds for the connections unit alone, 21 seconds for listening ports.

**How it surfaced:** Smoke-testing the full Collection phase produced the expected functional output but the duration log lines made the bug obvious: `UNIT_END: U-ConnectionsSnapshot | Duration: 65.347028s`. For a triage tool whose entire pitch is "30-60 seconds per host," 65s on a single unit is a hard fail.

**The fix:** Build a single process index at the top of Phase B with one call: `Get-CimInstance -ClassName Win32_Process` → loop into a hashtable keyed by `[int]ProcessId`. Both units now do `$procIndex.ContainsKey($pid_) ? $procIndex[$pid_] : Get-ProcessDetails -ProcessId $pid_`. The fall-through to `Get-ProcessDetails` covers the rare case where a process exits between snapshot and the unit run, and preserves the standalone-paste behavior (where the cache may not exist).

**Result:** Connections went from 65s → 1.6s (40× speedup). Listening ports went from 21s → 0.4s (50× speedup). Total Collection phase went from 97s → 11s (9× speedup). The whole module now runs end-to-end in 12s, comfortably inside the 30-60s target.

**Why it matters beyond perf:** A 90-second triage is not a triage tool, it's a pause-and-go-get-coffee tool. Operators with 10 endpoints to sweep in an hour will skip a slow tool entirely and revert to manual `netstat | findstr` workflows. The performance budget is load-bearing for adoption, not just polish.

**Lesson 1:** WMI/CIM startup cost is dominant. ANY per-row CIM call inside a `foreach` is a perf bug waiting to happen. The pattern is: one query at the top, build a hashtable index, look up by key inside the loop. This applies to `Win32_Process`, `Win32_Service`, `Win32_StartupCommand`, and any other Win32_* class.

**Lesson 2:** Always include stopwatch duration in `UNIT_END` log lines. The duration field is what made this bug self-evident — without it, "the script feels slow" is an operator complaint that takes hours to localize. With it, the slow unit names itself in the log.

---

### 3. `U-Services` flagged 195 of 329 services (59%) as suspicious — `UntrustedSigner` + `SuspiciousName` heuristics were both broken
<!-- tags: powershell,heuristics,false-positive,services -->

**The bug:** Two independent over-flagging issues compounded.

1. **`UntrustedSigner` flag:** The Authenticode check did `if (-not $trustedHit) { $flags += 'UntrustedSigner' }` after matching the certificate subject against `$script:Exclusions.TrustedSigners` (5-entry list). Almost every legitimate third-party signed service (Adobe, Citrix, Java, anti-virus other than the one I had on my exclusions, etc.) failed the subject match and got the flag. AND — critically — `UntrustedSigner` wasn't even in `triage-weights.json`, so `Get-FlagWeight` returned 0 for it. The flag was visible in JSON but contributed nothing to the score. Pure noise.

2. **`SuspiciousName` regex:** `^[a-z]{8,}$ -or ^[A-Z0-9]{8,}$`. Intent was "looks autogenerated, like a randomized botnet service name." Reality: matches `wuauserv`, `lanmanworkstation`, `eventsystem`, `bthserv`, `dhcpcsvc`, and dozens of other completely legitimate Windows service names that happen to be 8+ lowercase characters. The "8 chars or more, all lowercase" set is dominated by *normal* Windows services, not botnet droppers.

**How it surfaced:** The Collection phase smoke test logged `SERVICES: 195 flagged of 329 total`. 59% of all services on a clean laptop being flagged as suspicious is a false-positive rate so high the scoring is meaningless.

**The fix:** 
- Drop `UntrustedSigner` entirely. Keep only the "Status -ne Valid" check, which catches genuinely unsigned binaries. (Also added `-and $sig.Status -ne 'UnknownError'` because PowerShell's signature check returns `UnknownError` for some legitimate scenarios like sparse files or ACL'd paths — those shouldn't flag as unsigned.)
- Drop `SuspiciousName` entirely for Phase 1. Document the intent in a comment. A real "looks-randomized" check needs entropy scoring or a length-vs-vowel-ratio heuristic, neither of which is in scope here.

**Result:** Services flagged dropped from 195 → 7 (2.1% rate) on the same host. The 7 flags are now distributed across `UserWritablePath` (legit suspicious) and `Unsigned` (legit suspicious for CI tools, build artifacts) — no noise.

**Lesson 1:** A heuristic that fires on >10% of its input is broken until proven otherwise. "Most things aren't suspicious" is the prior; any suspicion-detector needs to respect that. Triage scoring with a 59% false-positive rate is worse than no scoring at all because it teaches the operator to ignore the "High" verdict.

**Lesson 2:** Substring/regex heuristics for security signals need a corpus check before ship: "what does this match on a clean baseline host?" For service names specifically, the right test is "run the regex against `Get-Service | Select Name` on three different machines and count hits." Anything > 3-5 hits per machine is too broad.

**Lesson 3:** Flags that aren't in the weights file are dead code with negative value — they show up in JSON but don't influence the verdict, AND they consume operator attention. If a flag isn't worth a weight, delete the code that emits it.

---

## Design Decisions

### 1. The whole function body is inside a try/catch for the gate-throw signal
<!-- tags: powershell,error-handling,phase-gate -->

The try wraps from immediately after `param)` to immediately before the function's closing `}`. The catch has two arms:

```powershell
} catch {
    if ($_.FullyQualifiedErrorId -eq 'PhaseGateReached') {
        return 0  # clean gate exit
    }
    Write-Log -Level ERROR -Message "UNHANDLED: $($_.Exception.Message) | At: $($_.InvocationInfo.PositionMessage)"
    return 99
}
```

The two-arm catch is deliberate: gate signals are a *normal* control-flow path (operator asked to stop after phase X), not an error. They exit 0. Anything else — an unhandled exception that escaped the per-unit `Invoke-TriageUnit` try/catch — exits 99 (canonical "unhandled error" code from scripting-standards).

**Why not use `[System.Management.Automation.HaltCommandException]` directly?** The throw side would have to construct one with no useful context, and the catch side would have to do reflection on the exception type. Tagging with a `FullyQualifiedErrorId` of `'PhaseGateReached'` is grep-able, debuggable, and survives serialization across pipeline boundaries.

**Lesson:** When a function has both "early-exit-but-success" (gates) and "unhandled-error" (panics) signals, distinguish them at the catch site, not via separate try blocks. A single try/catch with type-discrimination in the handler is clearer than two nested trys.

---

### 2. Inline helper stubs are guarded by `Get-Command`, not by a `$DotSourced` flag
<!-- tags: powershell,standalone-fallback,helpers -->

Each of the 5 inline stubs is wrapped in:

```powershell
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    function Write-Log { ... }
}
```

The alternative would have been a flag like `$script:UseInlineStubs = $true` set by the caller. I rejected that because:

1. It pushes setup responsibility onto the caller. The dot-source path "just works" — the authoritative `Write-Log` from `_Shared.ps1` is already defined when the module file loads, so the inline `if` is false and the inline stub is not defined.
2. It survives partial dot-sources. If someone dot-sources `_Shared.ps1` but the dot-source fails partway through (e.g., a syntax error in a later helper), some helpers may be defined and others not. The `Get-Command` guard handles this gracefully — only the missing ones get inline stubs.
3. It's idempotent. Loading the module twice doesn't redefine the inline stubs; the second load sees the first load's functions and skips the inline definitions.

**Lesson:** Capability detection (`Get-Command -ErrorAction SilentlyContinue`) is more robust than caller-set flags for "should I provide a fallback?" decisions. The cost is one cmdlet call per stub at load time (~1ms total); the benefit is graceful behavior under partial dot-source and double-load conditions.

---

### 3. The module ships as a function definition only — no top-level execution
<!-- tags: powershell,module-shape,libraries -->

The file ends with `}` — the closing brace of `function Invoke-BotnetTriage`. There is no trailing call like `Invoke-BotnetTriage @PSBoundParameters`. This means:

- Dot-sourcing the file (`. .\modules\Invoke-BotnetTriage.ps1`) just defines the function. Nothing runs.
- Calling `pwsh -NoProfile -File modules\Invoke-BotnetTriage.ps1` defines the function and exits — also runs nothing. (This is what makes the parser-validation step safe.)
- The intended invocation is: dot-source, then call `Invoke-BotnetTriage <args>` separately.

The standalone-paste path uses a different shape: paste the function definition, *then* paste the invocation. The two pieces are decoupled deliberately so an operator can verify the function definition succeeds before triggering execution.

**Lesson:** Modules whose primary entry point is a single named function should ship that function and stop. No "if invoked as script, do the thing" footer. The footer is useful for one-shot scripts; for reusable functions, it conflates definition and invocation in a way that breaks dry-run, breaks `-WhatIf`, and confuses the parser-validation pattern.

---

## Carry-Forward Items

- **CF-1, CF-2, CF-4, CF-5, CF-6, CF-7, CF-8** — all still open from prior phases. None addressed this phase.
- **CF-9 (NEW):** `Get-FlagWeight` inside `U-ScoreFindings` handles both `[hashtable]` and `[pscustomobject]` weight shapes via duck-typing. Document the dual-shape requirement somewhere (likely the `_Shared.ps1` `Resolve-Config` Depends comment) so future helper changes don't accidentally produce a third incompatible shape.
- **CF-10 (NEW):** Top-5-findings summary line shows flag names but not process names or paths. Adding the process name + remote IP to the summary would make the console output dramatically more actionable. Polish, not blocking; tag for Phase 8 (verification-tier polish) or Phase 10 finalization.
- **CF-11 (NEW):** `U-LocalAccounts` flagged 5 accounts on a clean dev laptop, including built-ins. Investigate whether `PasswordLastSet` returns a real date for built-ins like `DefaultAccount`/`WDAGUtilityAccount`/`Guest` — if not, the recency comparison logic needs a null guard. Cosmetic for Phase 1 (5 false positives at low score don't move the verdict needle), but worth a 10-line audit during Phase 8 verification.
- **CF-12 (NEW):** Phase 2 should add a real `Test-IsSuspiciousServiceName` heuristic — entropy-based, or vowel-ratio-based, or length+non-dict-word — to replace the deleted Phase 1 placeholder. The current behavior (no heuristic) is honest; the previous behavior (50% false positive) was actively harmful.

---

## Metrics

| Metric | Value |
|--------|-------|
| Files created | 2 (`modules/Invoke-BotnetTriage.ps1`, this reflection) |
| Files modified | 2 (`modules/_Shared.ps1` for the gate-throw fix; `modules/Invoke-BotnetTriage.ps1` for 3 bug fixes) |
| Lines of code (module) | ~1115 |
| Functions defined (file scope) | 6 (5 inline stubs + `Invoke-BotnetTriage` itself) |
| Sub-phases implemented | 4 (Preflight, Collection, Processing, Output) |
| Units implemented | 18 (3 + 8 + 4 + 3) |
| Parser validation passes | 3 (post-write, post-gate-fix, post-perf+services-fix) |
| Dot-source smoke tests | 1 (loaded `_Shared.ps1` + module, all 8 expected params present) |
| Functional smoke tests | 4 (Preflight gate, Collection gate, full dry-run, full real run) |
| Real bugs found | 3 (gate `exit 0`, per-row CIM perf, services over-flagging) |
| Real bugs fixed | 3 |
| Total Collection time before fix | 97s |
| Total Collection time after fix | 11s |
| Total module runtime (real run, end-to-end) | 12.3s |
| JSON artifact size | 42342B |
| JSON top-level keys | 4 (`meta`, `verdict`, `findings`, `errors`) |
| JSON findings sections | 8 (all 8 data sources represented) |
| Verify-JsonOutput pass | yes |
| Final exit code (real run) | 0 |
| Phase outcome | `Invoke-BotnetTriage.ps1` on disk; parses clean; loads cleanly via dot-source; runs end-to-end in 12s on a real laptop; produces a 42KB schema-valid JSON; verify unit confirms output integrity |
