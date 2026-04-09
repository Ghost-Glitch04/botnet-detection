---
name: powershell
description: PowerShell-specific rules covering StrictMode pitfalls, scoping/dot-source, standalone-fallback, CIM/WMI performance, library shape, bootstrap, and bash interop.
type: ai-subject
---

# PowerShell — Subject Rules

Rules for writing, debugging, and shipping PowerShell modules in this toolkit. Anchor topics: StrictMode polymorphism, dot-source scoping, inline-fallback stubs, CIM/WMI cost, phase-gate error patterns, bootstrap/launcher idioms.

---

## Strict Mode

### Wrap Get-ChildItem (and any 0/1/N cmdlet) in @() under StrictMode

**When:** Authoring or editing a script that runs under `Set-StrictMode -Version Latest` and reads `.Count` on the result of a cmdlet that may return 0, 1, or N items.
**Rule:** Always wrap `Get-ChildItem`, `Get-NetTCPConnection`, `Get-LocalGroupMember`, etc. in `@(...)` before assigning. A single FileInfo is a scalar, not an array — `.Count` throws under StrictMode. The `@()` operator coerces to array uniformly.

```powershell
$contents = @(Get-ChildItem -Path $tempDir -File)
if ($contents.Count -ne 1) { ... }
```

*Source: phase07_deploy_launcher.md#1*

---

### Probe CIM polymorphic properties before reading

**When:** Iterating heterogeneous CIM collections like `ScheduledTask.Actions` or `.Triggers`, where each element may be one of several subtypes (e.g. `MSFT_TaskExecAction` vs `MSFT_TaskComHandlerAction`).
**Rule:** Test `$obj.PSObject.Properties.Name -contains 'PropName'` before accessing. Direct `$obj.PropName` throws under StrictMode for subtypes that don't define the property. Default action is `Exec` so the bug only surfaces on hosts with `ComHandler` tasks.

```powershell
$exec = if ($a.PSObject.Properties.Name -contains 'Execute') { $a.Execute } else { $null }
```

**Symptom:** `'Execute' cannot be found on this object.`
**Companions:** standalone-fallback (multi-host shape exposes the bug)

*Source: phase08_verification_tiers.md#1pitfall*

---

## Scoping & Dot-Sourcing

### Dot-source must run at script scope, never inside a function

**When:** Authoring a launcher (`Deploy.ps1`) or any script that loads helper libraries via `. .\path\helper.ps1`.
**Rule:** Dot-sourcing inside a function body discards the loaded definitions when the function returns — they bind to the function's scope, not the caller's. Always lift dot-source to script-top scope. If you need conditional logic, conditionally choose the *path*, then dot-source unconditionally outside the function.

*Source: phase07_deploy_launcher.md#2*

---

### Library files must not set script-scope state

**When:** Authoring a dot-sourceable helper file (e.g. `_Shared.ps1`) intended to be loaded into a caller's scope.
**Rule:** Do not put `Set-StrictMode`, `$ErrorActionPreference = 'Stop'`, `param(...)` blocks, or other top-level state mutations in a library file. Those decisions belong to the caller. Library files should ship only `function` definitions.

*Source: phase05_shared_helpers.md#5*

---

### Use Get-Variable -Scope 1 for caller-param lookup in inline stubs

**When:** Writing an inline fallback stub in a paste-target file that needs to read a caller's parameter (e.g. `$StopAfterPhase`) without knowing the caller's StrictMode state.
**Rule:** Use `Get-Variable -Name X -Scope 1 -ErrorAction Stop` rather than relying on PowerShell's dynamic scoping. Implicit `$X` reads can throw under StrictMode if the var isn't bound, and the paste session's StrictMode setting is unknowable in advance.

```powershell
$sap = $null
try { $sap = (Get-Variable -Name StopAfterPhase -Scope 1 -ErrorAction Stop).Value } catch { }
```

*Source: phase08_verification_tiers.md#1design*

---

## Standalone-Fallback / Inline Stubs

### Guard inline stubs with Get-Command, never with caller-set flags

**When:** A function in `_Shared.ps1` is duplicated inline as a fallback in a paste-target script (e.g. `Invoke-BotnetTriage.ps1`).
**Rule:** Wrap the inline definition in `if (-not (Get-Command Name -ErrorAction SilentlyContinue)) { function Name { ... } }`. Capability detection is more robust than caller-set flags ("did Deploy.ps1 run?") because the launcher may be absent in standalone-paste mode.

*Source: phase06_invoke_triage_build.md#2design*

---

### Helpers in dot-sourced libraries must throw, not exit

**When:** Authoring a function in `_Shared.ps1` (or any dot-sourceable library) that hits a fatal condition.
**Rule:** Use `throw` (or a tagged terminating ErrorRecord) instead of `exit`. `exit` from a dot-sourced function tears down the entire host process — the caller never sees the error. The caller is the one with context to decide function-return vs script-exit.

*Source: phase06_invoke_triage_build.md#1*

---

### Library stubs WARN-and-return-null, do not throw

**When:** Stubbing out a Phase-2 helper in `_Shared.ps1` that ships now but isn't implemented yet.
**Rule:** Stubs should `Write-Warning` and `return $null`, not `throw`. "Fail loud" is correct for missing-impl detection, but throwing from a stub bricks the entire dot-source chain — every consumer of the library breaks because of one unused stub.

*Source: phase05_shared_helpers.md#7*

---

### Helpers degrade gracefully when caller-scope state is absent

**When:** Authoring a helper destined for a standalone-paste toolkit (e.g. `Write-Log` reading `$script:LogFile`).
**Rule:** Test for the expected caller-scope variable; if absent, fall back to a sensible default (e.g. write to host only, or `$env:TEMP\fallback.log`). Never assume the caller has set up state — paste sessions may not have.

*Source: phase05_shared_helpers.md#6*

---

## Performance — CIM/WMI

### Build snapshot once, hashtable-index, look up in loop

**When:** Iterating connections, services, or any collection where each row needs process metadata via `Get-Process`/`Get-CimInstance Win32_Process`.
**Rule:** Per-row `Get-CimInstance` inside `foreach` is a perf bug — each call costs ~50–200ms. Build one snapshot at phase start, index by primary key (PID) into a hashtable, look up inline. Cuts a 30-second collection phase to <1 second.

```powershell
$procIndex = @{}
foreach ($p in (Get-CimInstance Win32_Process)) { $procIndex[[int]$p.ProcessId] = $p }
foreach ($c in $connections) { $proc = $procIndex[[int]$c.OwningProcess] }
```

*Source: phase06_invoke_triage_build.md#2*

---

## Phase Gates / Error Handling

### Two-arm catch for early-exit-success vs panic

**When:** A function has both a clean phase-gate exit path (return 0) and a panic exit path (return 99).
**Rule:** Wrap the function body in one `try` with two `catch` arms keyed on a tagged ErrorRecord category — the gate-signal arm returns 0, the catch-all arm returns 99. Clearer than separate `try` blocks because the success-vs-failure decision lives in one place.

```powershell
try {
    Invoke-PhaseGate -PhaseName 'Preflight'  # may throw PHASE_GATE_REACHED
    # ... rest of function ...
} catch [System.Management.Automation.RuntimeException] {
    if ($_.FullyQualifiedErrorId -like '*PhaseGateReached*') { return 0 }
    Write-Log -Level ERROR -Message "UNHANDLED: $($_.Exception.Message)"
    return 99
}
```

*Source: phase06_invoke_triage_build.md#1design*

---

### Distinguish critical vs non-critical units via wrapper switch

**When:** Building a launcher (`Deploy.ps1`) with multiple bootstrap units, some of which must abort the run on failure and some of which should warn-and-continue.
**Rule:** Bake critical-vs-noncritical into the unit-runner API as a parameter (e.g. `-Critical`), not scattered try/catch in each unit body. The rule lives in one place; new units inherit it correctly.

*Source: phase07_deploy_launcher.md#3went*

---

## Library / Module Shape

### Modules with single-function entry ship only the function, no script footer

**When:** A module file's purpose is to define one named function (e.g. `Invoke-BotnetTriage.ps1` defines `Invoke-BotnetTriage`).
**Rule:** Stop at the closing brace of the function. Do not append `if ($MyInvocation.InvocationName -eq 'Script') { Invoke-BotnetTriage }` or similar "if invoked as script, run it" footers. Definition and invocation are separate concerns; conflating them breaks dot-source flows.

*Source: phase06_invoke_triage_build.md#3design*

---

### Helper headers name caller-scope state read, not just params

**When:** Documenting a helper function that reads variables from the caller's scope (e.g. `$script:LogFile`, `$script:TriageData`).
**Rule:** Add a `Depends:` line to the function header listing the caller-scope vars consumed. Implicit dependencies are invisible during refactor; the `Depends:` line surfaces them.

```powershell
<#
.SYNOPSIS Append a structured log entry.
.PARAMETER Level INFO/WARN/ERROR/DEBUG
Depends: $script:LogFile (path), $script:DebugMode (bool, optional)
#>
```

*Source: phase05_shared_helpers.md#4*

---

## Logging / Observability

### Always include stopwatch duration in UNIT_END log lines

**When:** Authoring a unit in a multi-unit pipeline (Phase A/B/C/D structure).
**Rule:** Start a stopwatch at `UNIT_START`, write its `Elapsed.TotalSeconds` at `UNIT_END`. Slow units name themselves in the log. Without it, "feels slow" troubleshooting takes hours; with it, `grep UNIT_END *.log | sort -k duration` finds the offender in seconds.

*Source: phase06_invoke_triage_build.md#2went*

---

### Inline minimal Write-Log at top of launcher, then shadow

**When:** Building a bootstrap launcher that needs logging before the authoritative `Write-Log` (in `_Shared.ps1`) has been dot-sourced.
**Rule:** Define a 10-line `Write-Log` inline at the very top of the launcher. After dot-sourcing the library, the authoritative version transparently shadows the inline version — provided their signatures and the script-scope vars they read (`$script:LogFile`) match exactly.

*Source: phase07_deploy_launcher.md#1went*

---

## Bash Interop

### Never cram multi-line pwsh into bash-quoted -Command

**When:** Calling PowerShell from a bash session for smoke testing (e.g. dot-source + run a function).
**Rule:** Bash eats backticks and `$()` regardless of `$` escaping inside `pwsh -Command "..."`. Always write the snippet to a tempfile and use `pwsh -NoProfile -File /tmp/x.ps1`. Saves an hour of debugging "why is `$null` getting interpolated."

*Source: phase05_shared_helpers.md#3*

---

## Bootstrap / Launcher

### Mechanical dependencies in step order trump nominal order

**When:** A planning doc lists steps in nominal (logical) order but a mechanical dependency demands a different order (e.g. logfile path requires OutputDir to exist first).
**Rule:** Reshuffle steps to satisfy the dependency, document the divergence inline at the swap point with a one-liner explaining why. Future readers see the rationale at the divergence, not buried in a doc comment elsewhere.

*Source: phase07_deploy_launcher.md#1design*

---

### AST parse for "what this codebase contributes," not Get-Command -Name

**When:** Building an "Announce" unit that lists the functions a launcher just loaded.
**Rule:** Parse the source files with `[System.Management.Automation.Language.Parser]::ParseFile(...)` and walk `FunctionDefinitionAst` nodes. Never use `Get-Command -Name 'Invoke-*'` — `$env:PSModulePath` pollution makes blocklists unbounded and the announce list silently grows.

*Source: phase07_deploy_launcher.md#3*

---

## Heuristic / Detector Rules (PowerShell-flavored)

### Substring matchers must respect camelCase boundaries

**When:** Implementing a sensitivity detector (e.g. mask values whose name contains `pat`, `pwd`, `sas`).
**Rule:** Plain substring match false-positives on `InputPath`, `Assessed`, `ForwardTo`. Match at camelCase segment boundaries (split on uppercase, compare segments) or use a regex with `\b`-equivalent anchors.

*Source: phase05_shared_helpers.md#1pitfall*

---

### Smoke test with positive AND negative cases

**When:** Authoring any helper with hand-rolled string matching, regex, or path logic (where "obvious" inputs may behave non-obviously).
**Rule:** Write a 10-line smoke test exercising at least one positive and one negative case before declaring done. Use `=== START ===` / `=== END (rc=$rc) ===` brackets in the test output — a missing trailer is the precise tell that the function exited via an unexpected path.

*Source: phase05_shared_helpers.md#2 + phase06_invoke_triage_build.md#1went*

---

### Parser validation is meaningful "zero bugs" signal

**When:** Finishing a helper file and deciding whether to run smoke tests.
**Rule:** Always run `[System.Management.Automation.Language.Parser]::ParseFile(...)` first — sub-100ms, catches 90% of edit-induced regressions. "Parser said zero" is a meaningful exclusion of a bug class, not wasted effort.

*Source: phase05_shared_helpers.md#1*

---
