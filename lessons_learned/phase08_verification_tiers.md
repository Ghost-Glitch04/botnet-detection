---
name: phase08_verification_tiers
description: Ran verification tiers 1-5 against the live toolkit. Caught 4 bugs across the data path (StrictMode CIM polymorphism, IOC correlation architecture, IOC-only score floor, missing inline phase-gate stub for standalone-paste).
type: reflection
---

# phase08_verification_tiers — Tiered Verification of `Invoke-BotnetTriage` + `Deploy.ps1`

> **Scope:** Run the 6-tier verification plan from PHASE1_PLAN.md / the re-shape plan against the built toolkit. Tier 1 (dry-run) → Tier 1a (phase gates) → Tier 2 (real, no IOCs) → Tier 2a (real, with IOCs) → Tier 3 (artifact schema) → Tier 4 (git hygiene) → Tier 5 (standalone paste). Tier 6 (cross-host) deferred — single-host environment.
> **Date:** 2026-04-09

---

## Applied Lessons

| Rule (file → heading) | Outcome | Note |
|------------------------|---------|------|
| phase06_invoke_triage_build.md#1 — bracket smoke tests with START/END trailers | Applied to every tier script | Each tier ends with `=== TIER N PASS ===` / `FAIL`. Made multi-tier runs trivially diffable. |
| phase05_shared_helpers.md#3 — never multi-line pwsh in bash double-quoted `-Command` | Applied | Tier 5 spawns the child via `Start-Process pwsh -ArgumentList @('-NoProfile','-File',...)`. Tier 2a / Tier 5 child scripts written via `Write` to a tempfile, never inlined into bash. |
| phase05_shared_helpers.md#1 — parser validation in same step you write the file | Applied after every fix | After each Edit to `Invoke-BotnetTriage.ps1`, ran `[Parser]::ParseFile` before re-running the tier. Caught a missing brace once before burning a 13s tier cycle. |
| phase06_invoke_triage_build.md#1 — helpers in dot-sourced libraries must NOT call `exit` | **Re-validated** | Tier 5 actually exercises the throw-and-catch phase-gate path in a fresh pwsh child (no caller try/catch is at script scope, but the `Invoke-BotnetTriage` function body owns it). rc=0 returned cleanly. |
| phase07_deploy_launcher.md#3 — AST allowlist instead of session enumeration | Validated | Deploy.ps1's `AVAILABLE_COMMANDS: Invoke-BotnetTriage` line is single-line clean across all tiers; no Microsoft Graph regression. |

---

## What Went Well

### 1. Multi-tier verification is non-redundant — each tier excludes a different bug class
<!-- tags: testing,verification,multi-tier -->

Tier 2 (real run, no IOCs) **passed clean**. Tier 2a (real run, *with* IOCs) immediately surfaced TWO bugs:

1. `U-ScheduledTasks` regression: `'Execute' cannot be found on this object` — under `Set-StrictMode -Version Latest`, `MSFT_TaskComHandlerAction` instances don't expose an `Execute` property and direct `$a.Execute` access throws. Tier 2 didn't hit it because the strict-mode failure pattern depends on which scheduled tasks happen to exist on the host *and which order* `Get-ScheduledTask` returns them — pure luck that Tier 2's pass-through didn't trip it.
2. `IOC_CORRELATED: 0 finding(s)` despite `api.anthropic.com` being in BOTH the live DNS cache AND the IOC file. Root cause: `U-DnsCache` only stored entries that were independently flagged (the only flag was `RawIPEntry` for raw-IP-named cache entries). `api.anthropic.com` wasn't independently suspicious, so it never made it into `triageData.DnsCache`, so `U-CorrelateIOCs` had nothing to scan.

If I had skipped Tier 2a (because Tier 2 passed), I would have shipped a triage tool whose IOC correlation was *architecturally broken*. The IOC path is invisible to any test that doesn't actually pass IOCs. Tier 5 (standalone paste) similarly caught the missing inline `Invoke-PhaseGate` stub — invisible to every other tier because they all dot-source `_Shared.ps1` first.

**Lesson:** Each verification tier must exclude a *different* bug class. Tier 1 (dry-run) excludes write-contract bugs. Tier 1a (gates) excludes early-exit bugs. Tier 2 (real) excludes data-path bugs. Tier 2a (with IOCs) excludes IOC-correlation bugs. Tier 3 (schema) excludes structure bugs. Tier 4 (git hygiene) excludes privacy bugs. Tier 5 (standalone) excludes inline-fallback completeness bugs. Skipping any tier silently allows a class of bugs to ship.

---

### 2. Mock IOC files must contain real entries from the test host
<!-- tags: testing,ioc,verification -->

The first version of `_tier2a_iocs.txt` I almost wrote contained `evil.example.com`, `192.0.2.15`, and a synthetic CIDR. They would have parsed cleanly, loaded into `$script:IOCSet`, and matched **nothing** — making the test indistinguishable from a passing run that simply has no IOC hits. Instead I ran `Get-DnsClientCache` first, picked `api.anthropic.com` (a real cached entry), and put it in the mock file. The test then either correlates (PASS) or doesn't (FAIL with a meaningful error).

**Lesson:** When testing a "needle in a haystack" detector, the mock needles must be real haystack contents from the test environment. Synthetic indicators that match nothing produce a vacuous pass.

---

### 3. AST parse-check before re-running a tier saves cycles
<!-- tags: testing,powershell,verification -->

After every Edit to `Invoke-BotnetTriage.ps1` (1100+ lines, 13s per real-run tier, 14s for the standalone tier), I ran `[Parser]::ParseFile` first. One attempted edit to U-ScheduledTasks left an unclosed brace; the parser caught it in <100ms. Without the parse-check I would have spent 13s waiting for `pwsh -File` to surface the same error from inside a stack trace.

**Lesson:** Parser validation isn't just for first writes — it's the cheapest possible regression test for every subsequent edit. Make it a reflex, not a checkpoint.

---

### 4. Tier 5 (standalone-paste) is the only test that exercises inline-fallback completeness
<!-- tags: testing,standalone-fallback,verification -->

Inline fallback stubs at the top of `Invoke-BotnetTriage.ps1` are guarded by `if (-not (Get-Command X -ErrorAction SilentlyContinue))`. When `_Shared.ps1` is loaded first (the normal Deploy.ps1 path), every guard is true and the stubs are skipped — their bodies never execute. The only way to actually exercise the stub *bodies* is to dot-source `Invoke-BotnetTriage.ps1` in a session where `_Shared.ps1` was never loaded.

Tier 5 caught that I had stubs for `Write-Log`, `Test-IsPrivateIP`, `Get-ProcessDetails`, `Get-Secret`, `Resolve-Config` — but **no stubs for `Invoke-PhaseStart` and `Invoke-PhaseGate`**. The function body calls `Invoke-PhaseGate -PhaseName 'Preflight' ...` directly, which would cause "command not found" in a paste session. Every other tier dot-sourced `_Shared.ps1` first and never noticed.

**Lesson:** Helper-stub guards (`if -not Get-Command ... { function ... }`) make the stubs *invisible* in the normal load path. The standalone path is the only path that proves the inline fallback is complete. If a paste-target file references a helper, that helper MUST have an inline stub regardless of whether it "feels like" a small enough helper to inline.

---

## Bugs / Pitfalls

### 1. Polymorphic CIM properties under Set-StrictMode break direct property access
<!-- tags: powershell,strict-mode,cim,wmi -->

`Get-ScheduledTask` returns objects whose `.Actions` array contains polymorphic CIM instances:
- `MSFT_TaskExecAction` — has `Execute`, `Arguments`, `WorkingDirectory`
- `MSFT_TaskComHandlerAction` — has `ClassId`, `Data` — **no `Execute`**
- `MSFT_TaskShowMessageAction`, `MSFT_TaskSendEmailAction` — different shapes again

Under `Set-StrictMode -Version Latest`, accessing `$a.Execute` on a `MSFT_TaskComHandlerAction` throws `'Execute' cannot be found on this object`. The fix is property probing:

```powershell
$exec = if ($a.PSObject.Properties.Name -contains 'Execute') { $a.Execute } else { $null }
```

This is NOT the same as the `phase07_deploy_launcher.md#1` pitfall (scalar `.Count`) — that one is about the synthetic scalar-as-collection adapter. This is about CIM polymorphism: the underlying object genuinely doesn't have the property because it's a different CIM class. Both manifest as "property not found" under StrictMode, but the fix patterns are different (`@(...)` array wrapping vs PSObject.Properties probing).

**Lesson:** Any CIM class that returns a heterogeneous collection (`Actions`, `Triggers`, `Settings` on scheduled tasks; `Drives` on Win32_LogicalDisk; etc.) needs property probing under StrictMode. Direct property access works for the common subtype and silently breaks on the others. Test scripts must hit a host with at least one COM-handler scheduled task to trip this.

---

### 2. Cross-stage filtering hides downstream-only data
<!-- tags: architecture,data-flow,ioc -->

The collection units (`U-ConnectionsSnapshot`, `U-DnsCache`, `U-ScheduledTasks`, `U-Services`, `U-Autoruns`) all stored only items that earned a heuristic flag. The processing units (`U-CorrelateIOCs`) iterated only the stored items. So an IOC that matched a benign-looking row never surfaced — it was filtered out one stage upstream from the stage that was supposed to detect it.

Three possible fixes:
1. Store all items in the collection units (rejected: bloats JSON for connections / tasks / services).
2. Move IOC correlation into the collection units (rejected: couples collection to scoring config).
3. **Inline IOC pre-retain check at collection time**: still filter for storage, but `OR` the heuristic filter with `$script:IOCSet.Contains(...)`. The IOC-only items get retained without other flags. `U-CorrelateIOCs` then runs as designed and finds them.

I went with option 3. Pattern applied to Connections, DnsCache, ScheduledTasks, Services, Autoruns. The `U-CorrelateIOCs` body is unchanged — it just has more items to walk now.

**Lesson:** When a downstream stage depends on data from an upstream stage, an upstream filter that's *correct in isolation* can be wrong in the pipeline. Test the pipeline end-to-end with data that's *only* visible via the cross-stage path. (Here: an IOC that doesn't independently look suspicious.)

---

### 3. IOC-only score floor (10 × 2.0 = 20) lands in Low (Medium threshold = 25)
<!-- tags: heuristics,scoring,ioc -->

`U-CorrelateIOCs` applies `Score = $score * IOCMatchMultiplier`, with a floor of `10 * IOCMatchMultiplier` (= 20) when the row's heuristic score is 0 (i.e., it was retained ONLY because of the IOC match). The Medium threshold from `triage-weights.json` is 25. So a confirmed IOC match — the strongest signal the operator has — classifies as **Low Risk** in the JSON output. That's wrong on its face: a known-bad indicator should at minimum bump the row to Medium. (The DNS hit in Tier 2a came out as `Score=20, Risk=Low` despite being flagged `IOCMatch=true`.)

Two fixes are possible: raise the IOC-only floor to ≥ 25, or have `U-ClassifyRisk` apply a `IOCMatch ⇒ min Risk = Medium` override. Either is a tuning decision and gets logged as a carry-forward (CF-16) — not blocking Phase 1 sign-off because the *correlation works* and the JSON correctly records the IOC match; only the Risk bucket is wrong.

**Lesson:** Thresholds and floors must be checked against each other, not just set independently. A pre-flight unit test for the scoring system would catch this — feed in a known-IOC-only row and assert the resulting Risk bucket. No such test exists today.

---

### 4. Helper-stub completeness is invisible to the load-from-library path
<!-- tags: standalone-fallback,powershell,verification -->

(Sister to "What Went Well #4".) The `if (-not Get-Command X) { function X { ... } }` guard pattern makes inline stubs **invisible** in the normal load order. Every Tier 1 / 1a / 2 / 2a / 3 run was via `Deploy.ps1`, which dot-sources `_Shared.ps1` first, which defines all 19 helpers, which makes every guard pass `-not Get-Command` = false, which skips every stub body. The stubs never executed in any tier except Tier 5. Tier 5 caught the gap (`Invoke-PhaseGate` not stubbed) on the very first run.

The risk is structural: I cannot prove inline-fallback completeness by reading the code, only by running it in an isolated session. A grep-based audit could catch *some* gaps (every function called inside `Invoke-BotnetTriage` should have a matching `Get-Command` guard at the top), but call-via-variable, splatting, and dynamic invocation defeat grep. The standalone-paste tier is the only authoritative check.

**Lesson:** If the standalone-paste path is load-bearing, the standalone-paste tier is non-optional. Schedule it for every change to the function body that *might* introduce a new helper call.

---

## Design Decisions

### 1. Inline `Get-Variable -Scope 1` over implicit dynamic scoping
<!-- tags: powershell,scoping,defensive -->

The inline `Invoke-PhaseGate` stub uses `Get-Variable -Name StopAfterPhase -Scope 1 -ErrorAction Stop` to reach the caller's parameter, instead of just referencing `$StopAfterPhase` directly. PowerShell's dynamic scoping makes the implicit version work in normal cases, but under `Set-StrictMode -Version Latest` an unset variable reference throws — and a fresh paste session may have inconsistent strict-mode state. The explicit `Get-Variable` call returns `$null` if not found instead of throwing, and the surrounding `try { } catch { }` catches the explicit-stop throw if ErrorAction Stop fires anyway.

The authoritative `Invoke-PhaseGate` in `_Shared.ps1` doesn't need this defense because `_Shared.ps1` deliberately does NOT set `Set-StrictMode` (per phase05_shared_helpers.md#5). The inline stub is in the *caller's* file (`Invoke-BotnetTriage.ps1`), which inherits whatever strict-mode state the paste session has. Defending the inline copy is cheap; not defending it costs a load-bearing path.

---

### 2. Mock IOC files live in `output/` (gitignored), not `iocs/` (mostly gitignored)
<!-- tags: testing,git,privacy -->

`output/` is unconditionally gitignored. `iocs/` is ignored *except* for `iocs_template.txt` and `iocs/README.md`. A test script that wrote `iocs/_tier2a_iocs.txt` would be safe today — but a future change to `.gitignore` might whitelist a pattern that catches it. Putting test IOC files in `output/` puts them under the unconditional ignore and removes any future-proofing risk. Tradeoff: less semantically obvious that the file is an IOC fixture. Mitigation: filename prefix `_tier2a_` makes the role obvious to any human reading the directory.

---

### 3. Tier 5 spawns a literal fresh `pwsh -NoProfile` child process, not just a fresh runspace
<!-- tags: testing,standalone-fallback,isolation -->

A new `New-PSSession` or `[powershell]::Create()` runspace inherits the parent process's `$env:PSModulePath`, profile state, and module auto-loading rules. To prove the standalone-paste path works in a *truly* clean environment, the test must spawn a separate `pwsh.exe` process via `Start-Process` with `-NoProfile`. Anything less risks the child accidentally inheriting helpers from the parent and silently masking a missing-stub bug. The Tier 5 script writes child scripts to disk and uses `pwsh -File`, not `pwsh -Command`, to avoid bash-quoting interference.

---

## Carry-Forwards (new)

| ID | Title | Surface | Action |
|----|-------|---------|--------|
| CF-16 | IOC-only Risk floor lands in Low | `Invoke-BotnetTriage.ps1` U-ClassifyRisk + triage-weights.json Thresholds | Either raise floor to ≥ 25 or override `IOCMatch ⇒ Risk >= Medium` in classifier. Tune in next config-revision pass. |
| CF-17 | No grep audit for inline-fallback completeness | `modules/Invoke-BotnetTriage.ps1` | Build a small static checker: enumerate function calls in the function body via AST, intersect with the set of `if (-not (Get-Command X))` guards, report missing. Phase 9 helper. |
| CF-18 | `U-CorrelateIOCs` doesn't iterate ListeningPorts | `Invoke-BotnetTriage.ps1` U-CorrelateIOCs | Probably correct (IOCs are usually remote-side, listening ports are local), but should be documented in the unit header. Phase 1 trailing comment. |
| CF-19 | Top-5 summary doesn't surface IOC-only hits | `Invoke-BotnetTriage.ps1` U-WriteSummary | Currently sorts strictly by score; an IOC-only row at score=20 sorts below every Medium hit. Consider a separate "IOC matches" line in the console summary regardless of score. |

---

## Permissions Gap Report

**None requested at start. None needed.** All five executed tiers ran with the dev laptop's standard user permissions; the toolkit logs `NOT_ELEVATED` warnings but degrades cleanly. No CIM access denials, no scheduled-task / service enumeration failures. Tier 6 (cross-host) was deferred for environment reasons, not permissions reasons.

The only permission-adjacent observation: `U-LocalAccounts` flagged 5 accounts despite the lab being a single-user workgroup. Inspection of the JSON showed all 5 were builtin or default accounts (Administrator, Guest, DefaultAccount, WDAGUtilityAccount, ryanf). This is CF-11 from phase06 — already tracked.

---

## Verification Tier Results Summary

| Tier | Test | Result | Duration | Notes |
|------|------|--------|----------|-------|
| 1   | Dry-run end-to-end (`-DryRun -DebugMode`) | PASS | 16.5s | rc=0, no JSON written, all 18 units logged START/END |
| 1a  | Phase gates (`-StopAfterPhase X` × 3) | PASS | ~2s × 3 | rc=0 at each gate, no downstream units fired |
| 2   | Real run, no IOCs | PASS | 13s | 34961-byte JSON, all 8 finding sections, errors=0 |
| 2a  | Real run, with mock IOCs (3 indicators, 1 real cache hit) | PASS (after 2 fixes) | 13.3s | `IOC_CORRELATED: 1` — DNS hit for `api.anthropic.com` confirmed |
| 3   | Artifact schema inspection | PASS | manual | 4 top-level keys (meta/verdict/findings/errors), 8 finding sections, counts non-negative |
| 4   | `git status --ignored --untracked-files=all` | PASS | <1s | All `output/`, deploy logs, mock IOCs properly ignored |
| 5   | Standalone-paste (orphan file in `$env:TEMP`, fresh `pwsh -NoProfile` child) | PASS (after 1 fix) | 14s | configSource=inline-fallback confirmed, JSON written to temp |
| 6   | **Non-elevated baseline** (added phase14) — real desktop with operator state, run as standard user | RETROACTIVELY ADDED | — | Excludes elevation-degradation bug class. See "Tier 6 — Non-Elevated Baseline" section below. |
| 7   | Cross-host diff | DEFERRED | — | Single-host environment — not blocking Phase 1 |

---

## Bugs Fixed In Phase 8

| # | Bug | Surface | Fix |
|---|-----|---------|-----|
| 1 | `'Execute' cannot be found` on COM-handler scheduled tasks | `U-ScheduledTasks` line ~565 | Switch to `$a.PSObject.Properties.Name -contains 'Execute'` probe |
| 2 | IOC correlation finds 0 hits even when IOC is in live DNS cache | `U-DnsCache` (and 4 other collection units) — items filtered out before reaching `U-CorrelateIOCs` | Add `$iocHit` pre-retain check; OR with heuristic flags to drive storage |
| 3 | `U-CorrelateIOCs` doesn't iterate Autoruns | `U-CorrelateIOCs` body | Add Autoruns loop with same multiplier + score-floor pattern as Connections/DnsCache |
| 4 | Standalone-paste fails: `Invoke-PhaseGate` not defined | `Invoke-BotnetTriage.ps1` inline stub block | Add inline stubs for `Invoke-PhaseStart` and `Invoke-PhaseGate`; phase-gate stub uses `Get-Variable -Scope 1` defensive caller-param lookup |

All four fixes were applied, AST-parse-checked, then re-tested by re-running the failing tier. No regressions surfaced in any earlier tier.

---

## Tier 6 — Non-Elevated Baseline (added phase14)

**Why it exists:** Phase 1.2.1 caught three bugs (OneDrive false-High, quiet non-elevated UX, NULL fields shipping silently) that all required a non-elevated run on a real desktop with operator state to surface. The clean-VM tier (Tier 2) and the elevated dev-box tier (Tier 2 variants) were both administrator sessions; the non-elevated execution path *worked mechanically* (no exceptions, exit code 0, valid JSON) but degraded silently. Operator could not distinguish a partial-coverage run from an authoritative one.

**Bug class excluded:** *Elevation-degradation* — code that runs cleanly under non-administrator permissions but produces misleading output. Distinct from data-path bugs (Tier 2), cross-stage bugs (Tier 2a), and standalone-paste bugs (Tier 5). No prior tier excluded this class.

**Test environment requirements:**
- Real desktop with operator state (OneDrive installed, browser running, scheduled tasks present, real DNS cache).
- A clean VM is **insufficient** — it lacks the operational state where the bugs live. Both environments are needed; neither subsumes the other.
- Run as a standard user (no `Run as Administrator`, no UAC elevation prompt).

**Pass criteria:**
1. Exit code 0.
2. `meta.elevated` field present in JSON, typed as `false` (not string).
3. Prominent `** NOT ELEVATED -- VISIBILITY LIMITED **` banner visible in console output (multi-line, yellow).
4. Connection rows with `ProcessPath: null` or `CommandLine: null` carry the `EnrichmentIncomplete` flag.
5. No `HIGH` findings on a binary that passes `TrustedSigners` (e.g., OneDrive). False-positive sanity check.
6. `ParentProcessName` populated even when `ProcessPath` is null (parent-name lookup is admin-independent).

**When to run:** Mandatory before declaring any phase shipped if that phase touched (a) connection enumeration, (b) process enrichment, (c) suppression / signer / vetting logic, or (d) anything that emits a row to JSON. Skip only for pure-doc or pure-test changes.

**Why it can't be simulated:** The bug class is "the operator is misled," not "the code throws." A code-reading audit cannot find these bugs because the code is mechanically correct. Only a human-in-the-loop run on the degraded environment, followed by JSON inspection, surfaces them.

*Source: phase14_phase12_connection_enrichment_and_hotfix.md#2*
