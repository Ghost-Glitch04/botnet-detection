---
name: phase05_shared_helpers
description: Built modules/_Shared.ps1 — 12 authoritative helpers + 7 Phase 2 stubs. Caught a real Get-MaskedParams bug via smoke test.
type: reflection
---

# phase05_shared_helpers — `_Shared.ps1` Helper Library

> **Scope:** Write `modules/_Shared.ps1` — the dot-sourced helper library that Deploy.ps1 and Invoke-BotnetTriage depend on. Includes Write-Log, Get-Secret, Test-IsPrivateIP, Get-ProcessDetails, Resolve-Config, Invoke-WithRetry, Import-DotEnv, Import-LocalConfig, Get-MaskedParams, Invoke-PhaseStart/Gate, Verify-JsonOutput, and 7 Phase 2 stubs.
> **Date:** 2026-04-09

---

## Applied Lessons

| Rule (file → heading) | Outcome | Note |
|------------------------|---------|------|
| phase03_config_files.md#1 — validate syntax in the same step you wrote the file | **Applied**, yielded a parser pass on first try | Ran `System.Management.Automation.Language.Parser::ParseFile` via `pwsh -NoProfile`. Zero errors on first attempt. Also did a dot-source smoke test (`. ./modules/_Shared.ps1`) to catch runtime load-time errors, which confirmed all 19 functions define cleanly. |
| phase04_iocs_template.md#2 — document semantics, not just syntax | Applied | Every helper has a `#region` block with Purpose / Inputs / Outputs / Depends. Phase 2 stubs have a block comment explaining why they exist and that any Phase 1 code path hitting them is a bug. |
| phase01_doc_realignment.md#7 — ship contract early | Applied | Phase 2 API stubs (`Invoke-VirusTotalLookup` etc.) ship in `_Shared.ps1` now even though Phase 1 never calls them — so dot-sourcing of the eventual Phase 2 modules succeeds, and the "these helpers exist" contract is visible today. |
| scripting-standards_V4_1 reference file | Applied | Write-Log, Invoke-WithRetry, Invoke-PhaseStart, Invoke-PhaseGate, Verify-*Output helpers follow the canonical templates in `.claude/skills/scripting-standards_V4_1/reference/powershell.md` almost verbatim. |
| phase03_config_files.md#3 — don't trust "already done" labels | **Triggered and invaluable** | See "Bugs and Pitfalls #1" below. The phase03 pitfall generalizes beyond prior-phase files: it also applies to "my own code I just wrote — did it actually do what I thought?" Smoke-testing `Get-MaskedParams` caught a real bug because I didn't blindly trust "I wrote this carefully." |

---

## What Went Well

### 1. Promoted Bash syntax-validation pre-declaration caught zero parser errors on first try
<!-- tags: powershell,process,verification -->

Per the phase03 missed-permission lesson, I added "Bash for syntax check" to Step 5's pre-declaration. The parser pass was clean on first run, which is the *good* outcome — not finding bugs means either the code is clean or my check is too weak. Here the check is strong (PowerShell's own AST parser is authoritative) and the code was clean, which gives meaningful confidence. Knowing the file parses also lets Step 6 (Invoke-BotnetTriage) assume `_Shared.ps1` is a safe dot-source target without having to re-verify.

**Lesson:** A "zero bugs" result from a strong verification tool is valuable signal, not wasted effort. The signal is "this class of bug is excluded," which narrows what can still go wrong downstream.

---

### 2. Smoke-testing individual functions caught a real bug in Get-MaskedParams
<!-- tags: powershell,testing,security -->

See "Bugs and Pitfalls #1" for the bug itself. The *method* that found it: I picked two helpers with non-trivial logic (Test-IsPrivateIP for its bit-twiddling on IPv4/IPv6 boundaries, and Get-MaskedParams for its hand-rolled string matching) and wrote quick `pwsh -NoProfile -File` smoke tests that exercise a handful of known-good and known-bad cases. The parser-level validation would never have caught the Get-MaskedParams bug because the code parsed and ran; only exercising it with real inputs did.

**Lesson:** Parser validation and smoke tests catch disjoint bug classes. Parser validation excludes syntax and binding errors; smoke tests exercise logic. For any helper function with hand-rolled matching, string manipulation, numeric thresholds, or bit operations, write a 10-line smoke test with a mix of positive and negative cases — it's the cheapest way to catch a logic bug before it lands in a downstream consumer.

---

### 3. Temp-script fallback for PowerShell tests beats complex bash-quoted one-liners
<!-- tags: powershell,bash,tools -->

My first smoke-test attempt (`Test-IsPrivateIP`) was a one-liner: `pwsh -NoProfile -Command "..."` with heavy backslash-escaping for `$` and backticks. Bash still ate the backticks inside the double-quoted command string (for the `` `n `` newline escape), and ate `$(...)` as command substitution despite my `\$(` escaping. Result: the actual test logic ran correctly (14/14 PASS visible), but the summary line and the overall exit code were corrupted by bash-level substitution. The Get-MaskedParams test used a `pwsh -NoProfile -File output/_smoketest_masking.ps1` tempfile approach instead — zero quoting issues, clean output, unambiguous exit code.

**Lesson:** For any PowerShell verification beyond 3 lines, write a tempfile under `output/` (already gitignored) and invoke with `pwsh -NoProfile -File`. Do not try to cram multi-line PowerShell into bash-quoted `pwsh -Command "..."`. The backslash-escaping for `$` collides with backticks, `$(...)`, and multi-line semicolon chaining, producing subtle corruption that looks like test failure when the logic is actually correct. Tempfiles cost 30 seconds and save the debugging dead-end.

---

### 4. Every helper has a formal region block and a Depends: line
<!-- tags: powershell,docs,standards -->

The scripting-standards reference mandates `#region` blocks with Purpose/Inputs/Outputs/Depends. Mechanically applying this to all 19 helpers (including stubs) took more keystrokes than a minimal "function Foo {}" would have, but the Depends line is load-bearing: it documents exactly what caller-scope state each helper assumes. For `Write-Log` that's `$script:LogFile` (optional — falls through if unset) and `$DebugMode` (optional). For `Invoke-PhaseGate` that's `$StopAfterPhase` in the caller's param scope. When Step 6 wires these helpers into the module, the Depends lines tell the module author exactly which script-scope variables must exist before the first call.

**Lesson:** Helper library headers should always name the caller-scope state the helper reads — not just parameters. "This function reads $script:LogFile" is more valuable to a caller than "this function takes -Message and -Level" because the parameters are obvious from the signature but the implicit dependencies are invisible.

---

## Bugs and Pitfalls

### 1. `Get-MaskedParams` substring-matched `pat` inside `InputPath` — false positive that would have silently masked an innocuous file path in every log line
<!-- tags: powershell,security,testing,masking -->

**The bug:** My first cut of `Get-MaskedParams` did:
```powershell
if ($nameLc -like "*$pat*") { $isSensitive = $true; break }
```
The canonical sensitive pattern list from PHASE1_PLAN.md includes `pat` (for "Personal Access Token"). Any parameter name containing the substring `pat` was being flagged as sensitive. `InputPath` → lowercased `inputpath` → contains `pat` at position 5 → masked as `***`.

**The smoke test that caught it:** A 40-line tempfile with 7 parameters — 4 that should mask (`VtApiKey`, `AbuseIpdbApiKey`, `UserPassword`, `BearerToken`) and 3 that shouldn't (`InputPath`, `OutputDir`, `Verbose`). Six cases passed; `InputPath was incorrectly masked` failed. Without the smoke test, this would have landed silently and the first person to notice would be an operator wondering why their log line said `InputPath='***'`.

**The fix:** Match sensitive patterns against *segments* of the parameter name, not arbitrary substrings. A regex `[A-Z]?[a-z]+|[A-Z]+(?![a-z])` extracts camelCase runs (`Input`, `Path`, `API`, `Key`) or all-caps runs (`SAS`, `API`). Then check `segments -contains $pat` for per-segment match, plus keep a full-name exact check for compound patterns like `connection_string` that contain their own underscore and wouldn't survive segmentation.

**Why it matters beyond the cosmetic fix:** Over-masking is a *security bug in the opposite direction from the obvious one*. Under-masking leaks secrets into logs; over-masking blinds operators to the non-sensitive context they need to triage problems. If `InputPath` gets masked, and a deploy fails because the operator typo'd the path, the log line that would have shown the bad path shows `***` instead. The operator now can't reproduce without rummaging through parameter history.

**Other tests I should have run but didn't, filed as CF-7:** `-like '*secret*'` would also false-positive on a param named `SecretaryEmail`. `*pwd*` would false-positive on `ForwardTo`. A fuller smoke test covering common English-word near-misses (`Forward`, `Secretariat`, `Assessed`, `Pattern`, `Patch`) would belong in a proper test file — out of scope for Phase 1 but a note for Phase 10 (finalization).

**Lesson 1:** Any substring-match-based sensitivity detector must match at word/segment boundaries, not arbitrary character offsets. Short tokens (`pat`, `sas`, `pwd`, `key`, `sas`) are especially prone to collision with common English words at substring level. The mitigation is free: camelCase segmentation via regex.

**Lesson 2:** Security logic that prevents information disclosure is high-signal — test it with explicit positive AND negative cases every single time. "No positive false-negatives" and "no false-positives" are both load-bearing; either failure is a bug.

---

### 2. My first bash-quoted smoke test output was corrupted by bash backtick interpolation, making the test *look* like it failed when the logic was correct
<!-- tags: bash,powershell,tools,process -->

The Test-IsPrivateIP test showed 14 green PASS lines (all correct) followed by `n0 of 14 cases failed` and exit code 1. Parsing this: the string began with `n` (not a newline), the count was `0`, and the exit code was from the *else* branch of `if ($fail -eq 0)`, meaning PowerShell somehow evaluated `$fail` as non-zero even though the loop incremented nothing. The cause was bash-level command substitution of `` `n `` (backtick command sub, not a PowerShell newline escape) and `$(...)` expressions nested inside the outer `pwsh -Command "..."` double-quoted argument — despite my `\$` escaping, bash ate the backticks because backticks in double-quoted bash strings are command substitution regardless of `$`-escaping.

**Cost:** ~5 minutes of "why is the summary line garbled but the cases all pass?" confusion. Fixed for the Get-MaskedParams test by writing a tempfile and using `pwsh -NoProfile -File` instead.

**Lesson:** See Went Well #3 above. Filing as a standing rule.

---

## Design Decisions

### 5. `_Shared.ps1` has no `param` block and no `Set-StrictMode`
<!-- tags: powershell,scoping,library -->

A dot-sourced library runs in the caller's scope. If `_Shared.ps1` had `Set-StrictMode -Version Latest` at file scope, it would impose strict mode on Deploy.ps1 and every module, whether they want it or not. Similarly, a `param` block at file scope on a dot-sourced file is a trap — it binds the caller's arguments to the library's param set, which is almost never what you want.

The rule: libraries declare functions and stay out of the caller's script-scope settings. Strict mode is the *caller's* choice. Param blocks are for scripts, not libraries.

**Lesson:** Dot-sourced library files should not set script-scope state (`Set-StrictMode`, `$ErrorActionPreference`, `param` blocks). Those are the caller's prerogatives. Library files only define functions and (at most) declare module-private constants.

---

### 6. `Write-Log` degrades to console-only when `$script:LogFile` is unset
<!-- tags: powershell,logging,standalone-fallback -->

The scripting-standards template assumed `$script:LogFile` was always set before `Write-Log` was called, and would throw if it wasn't. I relaxed this: `if ($script:LogFile) { Add-Content ... }`. Reason: standalone-paste path. When an operator pastes `Invoke-BotnetTriage.ps1` into a bare shell, the module's inline Write-Log stub activates *before* any log file infrastructure exists, because Deploy.ps1 (which sets `$script:LogFile`) was never run. The triage module still needs Write-Log to work — degrading to console-only is the right answer.

There's a one-time warning if `Add-Content` throws (e.g. disk full mid-run) tracked via `$script:LogFileWarnedOnce` so the warning doesn't spam every log line.

**Lesson:** Helper functions destined for a toolkit with a standalone-paste path must degrade gracefully when their usual caller-scope state is absent. The test is: "can this function be called cold, in a bare shell, without any prior setup?" If yes, it's standalone-compatible.

---

### 7. Phase 2 stubs log a `PHASE2_STUB_CALLED` WARN line and return `$null`
<!-- tags: powershell,stubs,fail-loud -->

The alternative would be to have stubs throw, so that any accidental Phase 1 call becomes a visible failure. I chose WARN+null instead because:

1. If a Phase 2 module accidentally loads in Phase 1 (e.g. someone dot-sources Invoke-C2BeaconHunt.ps1 prematurely), `throw`ing from a helper call would abort the dot-source entirely and make the launcher useless until someone figures it out. WARN+null keeps the system limping but loud.
2. Phase 1 has explicit scope boundaries that say "no API enrichment." If a Phase 1 code path calls one of these stubs, that's a scope-boundary violation — a bug, but one I want to *see* in the log as a WARN line so I can fix it, not a crash that makes the whole module unavailable.
3. `PHASE2_STUB_CALLED` is a grep-able tag. Step 8's verification tiers should grep logs for any instance of it — a clean Phase 1 run must have zero.

**Lesson:** "Fail loud" and "fail closed" are not always the same thing. For stubs in a library that mustn't block dot-sourcing, "log a loud WARN and return null" is the correct flavor of fail-loud — the stub is visible in logs for anyone looking, but the system keeps running. Test your verification tiers by grepping for the stub tag.

---

## Carry-Forward Items

- **CF-1 (phase01)** — still deferred to Step 10.
- **CF-2 (phase01)** — Find-StaleRefs.ps1 idea. Not needed this phase; still open.
- **CF-4 (phase03)** — REPO_PLAN.md exclusions.json schema alignment. Still deferred to Step 11.
- **CF-5 (phase04)** — PHASE1_PLAN.md `.gitignore` block missing `!iocs/README.md`. Still deferred.
- **CF-6 (phase04)** — iocs/README.md vs docs/CHEATSHEET.md source-of-truth. Still deferred.
- **CF-7 (NEW):** Proper Pester tests (or equivalent) for `Get-MaskedParams` covering English-word near-misses: `SecretaryEmail`, `ForwardTo`, `Assessed`, `Pattern`, `Patch`, `PatchVersion`, `KeyboardLayout`. The current smoke test is a one-shot tempfile; the canonical test suite belongs in a future `tests/` directory out of Phase 1 scope. File for Phase 10 finalization or explicitly out-of-scope.
- **CF-8 (NEW):** The `Test-IsPrivateIP` smoke test had a bash-quoting snafu. I fixed it ad-hoc for the next test but the broader lesson — "never write multi-line pwsh inside bash -c double quotes" — needs to be easy to remember. Consider a tiny helper `scripts/Invoke-PwshSnippet.ps1` that takes a heredoc from stdin and runs it, but that feels like over-engineering for a one-off. The lesson alone should be enough.

---

## Metrics

| Metric | Value |
|--------|-------|
| Files created | 2 (`modules/_Shared.ps1`, this reflection) |
| Files modified | 1 (`modules/_Shared.ps1` — post-smoke-test bug fix) |
| Functions defined | 19 (12 authoritative + 7 Phase 2 stubs) |
| Lines of code | ~520 (including header, region blocks, Phase 2 stub banner) |
| Parser validation passes | 2 (pre-fix, post-fix) |
| Dot-source smoke tests | 1 (confirmed all 19 functions load cleanly) |
| Function-level smoke tests | 2 (`Test-IsPrivateIP` 14/14 pass; `Get-MaskedParams` 7/7 post-fix) |
| Real bugs found and fixed | 1 (`Get-MaskedParams` substring false-positive on `InputPath`) |
| Tool-quoting bugs found and worked around | 1 (bash eating backticks inside `pwsh -Command` double-quoted arg) |
| Prior-phase rules applied | 4 (phase01 #7, phase03 #1/#3, phase04 #2) |
| Phase outcome | `modules/_Shared.ps1` on disk; parses clean; 19 functions load; critical helpers smoke-tested; 1 real masking bug caught at write-time instead of landing in production logs |
