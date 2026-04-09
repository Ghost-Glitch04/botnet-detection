---
name: phase07_deploy_launcher
description: Built Deploy.ps1 — 9-unit bootstrap launcher. Caught 3 real bugs (StrictMode + scalar .Count, dot-source-in-function-scope, announce filter pulling Microsoft Graph).
type: reflection
---

# phase07_deploy_launcher — `Deploy.ps1` Bootstrap Launcher

> **Scope:** Write `Deploy.ps1` — the canonical entry point when the toolkit is deployed via `git clone`. 9 units (Init/OutputDir/Logging combined → EnvSnapshot → DotSourceModules → ImportDotEnv → ImportLocalConfig → MaskedParams → LoadConfig → Announce). Standalone-paste path is intentionally NOT supported; that path uses the inline-stub fallback inside `Invoke-BotnetTriage.ps1` directly.
> **Date:** 2026-04-09

---

## Applied Lessons

| Rule (file → heading) | Outcome | Note |
|------------------------|---------|------|
| phase05_shared_helpers.md#1 — parser validation in same step you wrote the file | **Applied**, clean first pass | One AST `ParseFile` after `Write`, zero parser errors. Repeated after each bug fix. |
| phase05_shared_helpers.md#3 — never multi-line pwsh in bash double-quoted `-Command` | Applied | All smoke tests are tempfiles invoked via `pwsh -NoProfile -File`. |
| phase06_invoke_triage_build.md#1 — helpers in dot-sourced libraries must NOT call `exit` | **Re-applied for Deploy.ps1's own helpers** | The `Invoke-DeployUnit` wrapper for non-critical units logs `UNIT_FAILED` and continues; only `-Critical` units exit. The pattern matches `Invoke-TriageUnit` from phase06. |
| phase06_invoke_triage_build.md#1 — bracket smoke tests with START/END trailers | **Triggered, found 2 bugs** | First run: trailer printed but `ASSERT_FAIL: Invoke-BotnetTriage NOT in scope`. The trailer-bracket pattern made it instantly obvious that deploy "succeeded" but didn't actually load anything. |
| phase06_invoke_triage_build.md#2 — `UNIT_END` includes stopwatch duration | Applied | `Invoke-DeployUnit` logs duration on every successful unit. Confirms entire 9-unit bootstrap runs in <0.5s on the dev laptop. |

---

## What Went Well

### 1. Inline bootstrap `Write-Log` is replaced (not shadowed) when `_Shared.ps1` dot-sources
<!-- tags: powershell,bootstrap,logging -->

Deploy.ps1 needs `Write-Log` for `SCRIPT_START` and `ENV_SNAPSHOT` BEFORE `_Shared.ps1` is dot-sourced — those log lines are how operators know the bootstrap actually started. The trick: define an inline `Write-Log` with the same signature at top of Deploy.ps1, then dot-source `_Shared.ps1` later. Function definitions in PowerShell shadow earlier ones, so after dot-source the authoritative version takes over transparently. No flag, no name collision check, no `Remove-Item function:Write-Log`. The early log lines went to the bootstrap version; the later log lines went to the authoritative version; both wrote to the same `$script:LogFile` because both honor the same script-scope variable.

**Lesson:** When a script needs a logger BEFORE its full helper library is loaded, define a minimal inline version at the top. PowerShell's function shadowing makes the handoff free — no special "switch to real logger" step needed. Just keep the signatures compatible.

---

### 2. AST-based toolkit-function discovery beats `Get-Command -Name 'Invoke-*'`
<!-- tags: powershell,announce,filtering -->

The first cut of `U-Announce` did `Get-Command -CommandType Function -Name 'Invoke-*'`. On the dev laptop that returned **hundreds** of `Invoke-Mg*` cmdlets from auto-loaded Microsoft Graph modules, plus `Invoke-Pester`, `Invoke-AllTests`, etc. — 11KB of unrelated noise in a single log line.

The fix: during U-DotSourceModules, parse each `modules\Invoke-*.ps1` file with `[Parser]::ParseFile`, walk the AST for `FunctionDefinitionAst` nodes, and collect names matching `Invoke-*`. Store them in `$script:ToolkitFunctionNames`. U-Announce then iterates that list and confirms each is actually defined in the current session. Output: `AVAILABLE_COMMANDS: Invoke-BotnetTriage`. Crisp.

**Lesson:** When you need to enumerate "things this codebase contributed to the session," don't use ambient session queries (`Get-Command`, `Get-Module`) which can't distinguish your contributions from auto-loaded modules. Instead, walk the source files you control and extract their declarations directly. AST parsing is cheap (~5ms per file), exact, and survives PSModulePath pollution.

---

### 3. Critical-vs-non-critical unit distinction kept the bootstrap robust
<!-- tags: powershell,bootstrap,error-handling -->

`Invoke-DeployUnit` takes a `-Critical` switch. Critical units that fail call `exit 20` (canonical "module dot-source failure"). Non-critical units log `UNIT_FAILED`, append to `$script:DeployErrors`, and continue. Only `U-DotSourceModules` is currently critical, because if `_Shared.ps1` doesn't load, nothing downstream can work. Everything else (config files missing, .env absent, local config absent) falls back gracefully.

This was tested implicitly: the dev laptop has no `.env` and no `config.local.json`. Deploy.ps1 logs `CONFIG_MISSING` and `CONFIG_LOCAL_ABSENT` as warnings, the units log `UNIT_END: ... OK`, and the bootstrap completes with `FULL_SUCCESS: 9 unit(s) OK`.

**Lesson:** Distinguish "this failure means everything downstream is broken" (critical → exit) from "this failure means we lose a feature but the rest still works" (non-critical → warn). Bake the distinction into the unit wrapper API as a switch, not as scattered ad-hoc try/catch logic. The wrapper enforces consistent behavior across units; ad-hoc try/catch leads to drift (one unit exits on missing file, another silently swallows it).

---

## Bugs and Pitfalls

### 1. `Set-StrictMode -Version Latest` rejected `$singleFileInfo.Count` from `Get-ChildItem`
<!-- tags: powershell,strict-mode,scalar-vs-array -->

**The bug:** `U-DotSourceModules` initially did:
```powershell
$moduleFiles = Get-ChildItem -Path $moduleDir -Filter 'Invoke-*.ps1' -ErrorAction SilentlyContinue
if (-not $moduleFiles -or $moduleFiles.Count -eq 0) { ... }
```
On a repo with exactly one `Invoke-*.ps1` file, `Get-ChildItem` returns a single `[FileInfo]` object — not an array. Under `Set-StrictMode -Version Latest`, accessing `.Count` on a `[FileInfo]` throws `The property 'Count' cannot be found on this object`. (PowerShell 7's "scalar-as-collection" affordances are *disabled* by `Set-StrictMode -Version Latest` — you only get the synthetic `.Count` on scalars when strict mode is OFF or set to a lower version.)

**How it surfaced:** First Deploy.ps1 smoke test. The exception was crystal clear: line number, property name, file path. Took ~30 seconds to identify and fix.

**The fix:** Wrap the `Get-ChildItem` result in `@(...)` to force array context:
```powershell
$moduleFiles = @(Get-ChildItem -Path $moduleDir -Filter 'Invoke-*.ps1' -ErrorAction SilentlyContinue)
if ($moduleFiles.Count -eq 0) { ... }
```
Now `$moduleFiles` is always an array. `.Count` is always defined. The `-not` short-circuit can be dropped because an empty array `.Count -eq 0` covers the null case.

**Lesson:** Under `Set-StrictMode -Version Latest`, ALWAYS wrap `Get-ChildItem`, `Get-ChildItem -Recurse`, `Get-Process`, `Get-Service`, and any cmdlet that *might* return zero, one, or many objects in `@(...)`. The `@(...)` operator is the canonical "force this to be an array" pattern in PowerShell, and it's free. The bug class is "code that works on dev machine with N>1 results breaks in production with N=1 result," which is exactly the kind of latent failure that escapes local testing.

---

### 2. Dot-sourcing inside `& $Body` loaded helpers into a transient function scope — they vanished on return
<!-- tags: powershell,scoping,dot-source,critical -->

**The bug:** The first cut of `U-DotSourceModules` was wrapped in `Invoke-DeployUnit -UnitName 'U-DotSourceModules' -Body { . $sharedPath; ... }`. `Invoke-DeployUnit` invokes its body via `& $Body` — the call operator, which runs the script block in a NEW function-level child scope. When `. $sharedPath` ran inside that script block, the 19 helper functions from `_Shared.ps1` were loaded into the wrapper's transient function scope, not into Deploy.ps1's script scope. As soon as `Invoke-DeployUnit` returned, the function scope popped and ALL 19 helpers vanished.

**How it surfaced:** The next unit (`U-ImportLocalConfig`) called `Import-LocalConfig` and got `The term 'Import-LocalConfig' is not recognized`. Then `U-MaskedParams` failed the same way for `Get-MaskedParams`. Then `U-LoadConfig` failed for `Resolve-Config`. Three cascading failures with the same root cause. The smoke test's post-Deploy assertion `ASSERT_FAIL: Invoke-BotnetTriage NOT in scope` was the final tell — Deploy.ps1 thought it had succeeded, but nothing it loaded had actually landed in script scope.

**Why this is subtle:** Function-name *lookup* in PowerShell walks UP the parent scope chain — so calling a function defined in a parent scope from inside a child scope works. But function *definition* via dot-source happens in the CURRENT scope. Dot-sourcing a file `_Shared.ps1` from inside a function scope defines those functions inside that function scope, not the parent. This is the inverse of what most people expect from "dot-source is the in-place include operator."

**The fix:** Don't wrap dot-source operations in `Invoke-DeployUnit`. Lift the dot-source body OUT of the wrapper and run it inline at script scope. Manual `UNIT_START` / `UNIT_END` logging plus a script-scope try/catch replaces the wrapper for this one unit. Costs ~20 lines of duplication; gains: `_Shared.ps1`'s helpers actually exist after the unit returns.

**Lesson 1:** **Dot-source operations (`.`) cannot be wrapped in a function unless you accept that the dot-sourced definitions die with the function.** The whole point of dot-sourcing is to inject definitions into the current scope; running it inside a function inverts the semantics. If your unit needs to dot-source, that unit's body must execute at script scope, not inside any wrapper function.

**Lesson 2:** This is the second time this phase the "trailer-bracket" smoke test pattern (phase06 #1) caught an "execution succeeded but state didn't propagate" bug. The pattern is becoming load-bearing for any test of a dot-source-driven setup function. Standardize on it: every smoke test of a setup script should have a `=== START ===` line, the operation, then explicit asserts on the resulting session state, then a `=== END (rc=$rc) ===` line. If the END trailer is missing, the operation aborted. If the END trailer is present but asserts failed, the operation ran but didn't accomplish its goal. Two distinct failure modes, one harness.

**Lesson 3:** Wrappers like `Invoke-DeployUnit` are appropriate for pure-data units (collect this, transform that, write out) but inappropriate for scope-mutating units (dot-source, set strict mode, register module). When a unit's PURPOSE is "modify the caller's scope," it cannot be hidden behind a function call.

---

### 3. `Get-Command -Name 'Invoke-*'` pulled in 11KB of Microsoft Graph cmdlets
<!-- tags: powershell,announce,filtering,session-pollution -->

**The bug:** `U-Announce` initially did a session-wide `Get-Command -CommandType Function -Name 'Invoke-*'` and excluded specific names with a hand-maintained blocklist (`Invoke-DeployUnit`, `Invoke-WithRetry`, `Invoke-PhaseStart`, `Invoke-PhaseGate`, the four Phase 2 enrichment stubs). On the dev laptop, the user has Microsoft Graph PowerShell auto-loaded via PSModulePath, contributing **hundreds** of `Invoke-Mg*` functions. Plus Pester (`Invoke-Pester`), HNS (`Invoke-HnsRequest`), Excel query (`Invoke-ExcelQuery`), etc. The `AVAILABLE_COMMANDS:` log line ballooned to ~11KB and buried the one command operators actually care about.

**How it surfaced:** Reading the Deploy.ps1 smoke test output. The blocklist was failing exactly because it was a blocklist — every PowerShell module on the planet adds `Invoke-*` functions, and trying to maintain a blocklist of "everything that isn't ours" is unbounded.

**The fix:** Switch from blocklist to allowlist, and source the allowlist from the modules we control. During `U-DotSourceModules`, parse each `modules\Invoke-*.ps1` file with the AST parser and extract `FunctionDefinitionAst` names matching `Invoke-*`. Store in `$script:ToolkitFunctionNames`. `U-Announce` cross-checks each name against `Get-Command` (to confirm it's actually loaded) and prints just those.

**Lesson 1:** Allowlists scale; blocklists don't. When you need to enumerate "things our code added to the environment," derive the list FROM your code, not from the environment minus things you don't recognize.

**Lesson 2:** Session pollution from PSModulePath is invisible until your test or announce code does a session-wide query. Any wildcard `Get-Command` query is suspect — assume it returns the union of your stuff AND everything the user's profile auto-loaded, AND act accordingly.

**Lesson 3:** AST-walking source files for top-level declarations is a 5-line, ~5ms operation that produces a perfect inventory of what a file contributes. Use it whenever you need ground truth about "what does this file define" rather than runtime introspection of "what's in scope right now."

---

## Design Decisions

### 1. U-OutputDir runs BEFORE U-Logging, breaking PHASE1_PLAN.md's nominal step order
<!-- tags: powershell,bootstrap,ordering -->

PHASE1_PLAN.md lists the 10-unit order as Init → Logging → EnvSnapshot → ImportDotEnv → ImportLocalConfig → MaskedParams → OutputDir → DotSourceModules → LoadConfig → Announce. Deploy.ps1 implements OutputDir as part of the U-Init prelude — BEFORE U-Logging. The reason: the log file lives inside `$OutputDir`, so the directory must exist before `New-Item` can create the log file at script scope. The plan's ordering would either fail to create the log file (because the dir didn't exist yet) or silently create the dir as a side-effect of `Add-Content`, neither of which is acceptable.

I called the unit `U-OutputDir (early)` in a comment so future readers see why it's out of order vs. the plan. The deploy log still has the right unit names; only the order shifts.

**Lesson:** Plans describe nominal ordering; implementations sometimes need to reshuffle for mechanical dependencies. When you reshuffle, document the divergence in a comment AT the divergence, not in a separate doc that drifts.

---

### 2. Standalone-paste path is NOT supported by Deploy.ps1
<!-- tags: powershell,architecture,standalone -->

PHASE1_PLAN.md mentions a "standalone-paste fallback" for both Deploy.ps1 AND `Invoke-BotnetTriage.ps1`. Deploy.ps1 deliberately does NOT implement that fallback. The reason: Deploy.ps1's whole job is to wire up a multi-file repo layout. There is nothing for Deploy.ps1 to "fall back to" if the repo layout is missing — without `modules/_Shared.ps1`, without `config/*.json`, without `iocs/`, Deploy.ps1 has no reason to exist.

The standalone-paste path is implemented entirely inside `Invoke-BotnetTriage.ps1` itself, via the inline helper stubs guarded by `Get-Command` checks (see phase06 design #2). When `git clone` is blocked, the operator pastes the triage module directly into RemoteShell — Deploy.ps1 never enters the picture. This is the canonical "two paths, one of which doesn't need the launcher" architecture, and it's why `Invoke-BotnetTriage.ps1` carries its own inline stubs.

**Lesson:** Don't reflexively add fallback modes to every file. Some files ARE the fallback for other files; making them themselves fall-back-capable is just dead code. Identify the canonical "no-launcher" path and concentrate the fallback complexity there.

---

### 3. Bootstrap Write-Log honors `$script:LogFile` early so the file gets the SCRIPT_START line
<!-- tags: powershell,logging,bootstrap -->

The bootstrap `Write-Log` (defined inline in Deploy.ps1 before `_Shared.ps1` loads) reads `$script:LogFile` and `$script:DebugMode` from script scope just like the authoritative version. This means `SCRIPT_START`, the dry-run/debug-mode banners, and any pre-dot-source error messages all land in the log file from the very first line. After `_Shared.ps1`'s authoritative `Write-Log` shadows the bootstrap version, the same `$script:LogFile` is still in scope, so the log file is continuous — no gap between bootstrap and post-dot-source phases.

This required setting `$script:LogFile = ...` in U-Init (before U-Logging in plan terms), which is part of why U-OutputDir got promoted to early-phase too. The chain is: OutputDir exists → log file path is valid → bootstrap Write-Log can write to it → SCRIPT_START is logged → dot-source happens → authoritative Write-Log takes over → identical file target → continuous log.

**Lesson:** When designing a bootstrap with replaceable helpers, make sure the script-scope variables they depend on are set BEFORE the first call. The bootstrap version and the authoritative version share state via script-scope variables, not via parameters. Both versions reading the same variable is what makes the handoff transparent.

---

## Carry-Forward Items

- **CF-1, CF-2, CF-4, CF-5, CF-6, CF-7, CF-8, CF-9, CF-10, CF-11, CF-12** — all still open from prior phases. None addressed this phase.
- **CF-13 (NEW):** PHASE1_PLAN.md's `## Deploy.ps1 Structure` lists OutputDir as step 7. Deploy.ps1 implements it as part of the U-Init prelude (step 1.5) for the dependency reason described above. Patch PHASE1_PLAN.md in Step 11 to either reorder the list or add a parenthetical noting the OutputDir-before-Logging dependency.
- **CF-14 (NEW):** The smoke-test trailer-bracket pattern (`=== START ===` / asserts / `=== END (rc=$rc) ===`) has now caught 2 distinct bugs across phases 6 and 7. Promote it from a per-test convention to a documented standard, possibly into the scripting-standards reference, when the lessons-learned graduation runs in Step 10.
- **CF-15 (NEW):** Deploy.ps1's `U-DotSourceModules` uses the AST parser to extract function names from each module file. That same AST-walking logic could be extracted into a `Get-FunctionDefinitions` helper in `_Shared.ps1` for any future phase that needs to enumerate what a file defines. Out of Phase 1 scope; tag for Phase 5 (BaselineCapture) which may need similar introspection.

---

## Metrics

| Metric | Value |
|--------|-------|
| Files created | 2 (`Deploy.ps1`, this reflection) |
| Files modified | 1 (`Deploy.ps1` — three bug fixes after smoke tests) |
| Lines of code (Deploy.ps1) | ~340 |
| Units implemented | 9 (Init/OutputDir/Logging combined → EnvSnapshot → DotSourceModules → ImportDotEnv → ImportLocalConfig → MaskedParams → LoadConfig → Announce) |
| Parser validation passes | 3 (post-write, post-StrictMode-fix, post-scope-fix) |
| Functional smoke tests | 3 (failing-on-`.Count`, failing-on-scope, end-to-end pass) |
| Real bugs found | 3 (StrictMode + scalar `.Count`; dot-source-in-wrapper-scope; announce blocklist explosion) |
| Real bugs fixed | 3 |
| Total Deploy.ps1 runtime | 0.49s |
| Post-deploy `Invoke-BotnetTriage -StopAfterPhase Preflight` | rc=0 |
| Final status | FULL_SUCCESS: 9 unit(s) OK |
| Phase outcome | `Deploy.ps1` on disk; parses clean; bootstraps in 0.49s; `Invoke-BotnetTriage` in scope post-deploy and runs end-to-end; AVAILABLE_COMMANDS log line is exactly the toolkit's contribution, free of session pollution |
