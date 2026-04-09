---
name: phase14_phase12_connection_enrichment_and_hotfix
description: Combined reflection on Phase 1.2 (connection enrichment + parent/cmdline context, BeaconWhitelist plumbing, ListeningPorts split) and the Phase 1.2.1 three-bug hotfix (OneDrive false-High via dead config, quiet non-elevated UX, NULL enrichment shipping silently). Captures the dead-config-audit pattern, the elevation-tier verification gap, and the diagnostic-only-flag pattern (weight=0). Introduces Tier 6 (non-elevated baseline) as a new mandatory verification tier and clarifies the "dead flag" rule to mean *absent from weights file*, not zero-weighted.
type: reflection
---

# phase14_phase12_connection_enrichment_and_hotfix --- Connection Enrichment + Three-Bug Hotfix

> **Scope:** Combined reflection covering (a) Phase 1.2 ship --- parent-process / command-line enrichment, `SuspiciousParentProcess` / `PathOutsideSystem32` / `NonStandardPort` flags, BeaconWhitelist + LocalOnlyPorts plumbing, `HighPortAllInterfaces` rename --- and (b) the Phase 1.2.1 hotfix that landed three bugs caught by the FIRST non-elevated test on the clean Win11 VM.
> **Date:** 2026-04-09
> **Commits:** `bb236eb` (Phase 1.2 new flags), `32951c2` (Phase 1.2.1 bug fixes)
> **Verification:** V1 (non-elevated, post-hotfix) HIGH=0 / banner present / EnrichmentIncomplete fires correctly; V2-extra (non-elevated meta) `elevated:False` typed bool; V3 (elevated verdict) HIGH=0 MEDIUM=22 LOW=2 banner correctly absent.

---

## Applied Lessons

| Rule (file -> heading) | Outcome | Note |
|------------------------|---------|------|
| heuristics.md --- any detector firing on >10% is broken | **Re-applied (CF-29 closed)** | `HighPortNonServerProcess` was at 22% on the clean baseline; rename + tighten to `HighPortAllInterfaces` (require `0.0.0.0` AND high port) brought it to 0% on V3. Same rule that closed CF-29 originally; the rename made the rule's truth-condition match its name. |
| heuristics.md --- flags not in weights file are dead code | **Re-applied as design constraint** | Every new flag in Phase 1.2 (`SuspiciousParentProcess`, `PathOutsideSystem32`, `NonStandardPort`) was added to `triage-weights.json` *in the same edit* as the emit code. `EnrichmentIncomplete` (weight 0) forced a refinement of the rule --- see Bugs/Pitfalls #3. |
| testing.md --- each tier excludes a different bug class | **Re-applied as predictive warning** | The Phase 1.2 verification plan had Tiers 1-7 but no tier exercising the **non-elevated execution path**. That gap shipped --- the OneDrive false-High and the quiet UX both required a non-elevated run on a real desktop to surface. New Tier 6 (non-elevated baseline) is proposed below. |
| process.md --- bug-fix reflections must answer "what would have caught this?" | **Driving this whole reflection** | All three hotfix bugs are answered with a verification gap (CF-36, Tier 6) plus a code-pattern gap (CF-37, dead-config audit) plus a doc-rule refinement (CF-38, diagnostic-only flags). |
| config.md --- per-module ownership; in-file `Description` | **Re-applied** | `triage-weights.json`'s `Description` field still owns the file's purpose. Adding `EnrichmentIncomplete: 0` did not require touching any sidecar doc. |

---

## What Went Well

### 1. Phase 1.2's "enrichment over suppression" design held under bug pressure

The Phase 1.2 design principle was *maximum visibility with better ranked signal --- NOT suppression*. The hotfix bugs all proved this was correct: the OneDrive false-High wasn't a "we surfaced too much," it was "we surfaced something legitimately suspicious-looking and lacked the context to vet it." The fix added context (signer cache + TrustedSigners check), it didn't suppress. The non-elevated UX bug wasn't "we showed too little," it was "we shipped enrichment artifacts (NULL Path/CommandLine) without telling the operator the enrichment was degraded." The fix added a banner and a diagnostic flag, it didn't hide anything.

When all three of your hotfix bugs are *better-context* fixes rather than *more-suppression* fixes, the original design principle is load-bearing and worth re-quoting in the next phase plan. The temptation under hotfix pressure is always to silence the noisy thing; resisting that and instead asking "what context is missing?" produced cleaner fixes.

---

### 2. The signer cache pattern ported cleanly from "build once per phase" rule

Phase06#2 (`Per-row Get-CimInstance inside foreach is a perf bug`) generalizes: any expensive lookup with a stable key should be cached at phase start. `Get-AuthenticodeSignature` is slow (~50-200ms per file, sometimes more) and the same OneDrive binary appears across many connection rows. The fix used a path-keyed `$signerCache` hashtable initialized once per `U-ConnectionsSnapshot` invocation, populated lazily on first miss. Re-applied an old rule to a new lookup type without thinking about it --- which is exactly what the lessons-learned cadence is supposed to produce.

---

### 3. The Phase 1.2 verification ran clean on a clean VM --- proof that an extra environment matters

V1 of Phase 1.2 (clean Win11 VM, no engagement IOCs, no OneDrive installed) passed every verification tier from the original plan and would have shipped without the hotfix bugs ever surfacing. The hotfix bugs only appeared on the dev box --- because the dev box has OneDrive, has user-non-elevated execution, has the operational state a clean VM doesn't. **A clean baseline VM excludes one bug class (regression-on-clean-state); a real desktop excludes a different bug class (regression-on-actual-operational-state).** Both are needed. Neither subsumes the other.

---

## Bugs / Pitfalls

### 1. Dead config field --- TrustedSigners loaded but never consulted
<!-- tags: config,dead-code,suppression -->

**Symptom:** OneDrive flagged High on the first non-elevated dev-box run. Score breakdown: `ProcessInTempOrAppData` (30) + `IOCMatchMultiplier-style stacking` from auxiliary flags pushed it over 50.

**Root cause:** `config/exclusions.json` has held a `TrustedSigners` field since Phase 1 ("Microsoft Corporation", "Microsoft Windows", etc.) intended to suppress legitimate-but-AppData-resident processes. The field was loaded by `U-LoadConfig` into `$script:Exclusions.TrustedSigners` and **never read by any unit**. `U-ConnectionsSnapshot` checked `Test-IsUserWritablePath` and emitted `ProcessInTempOrAppData` regardless of who signed the binary.

**This is the same bug class as BeaconWhitelist before Phase 1.2**: a config field that ships with the repo, looks plausible, loads cleanly, and silently has zero effect. Phase 1.2 *just* fixed the BeaconWhitelist version of this bug. The TrustedSigners version was sitting next to it the entire time. I did not audit.

**Fix:** Per-flag signer-aware suppression --- when `ProcessInTempOrAppData` would fire, check `Get-AuthenticodeSignature` against `TrustedSigners`; if the signer matches, skip the flag. Cached path-keyed to avoid re-signing the same binary. If the signature lookup fails or is unsigned, the flag still fires (defaults to suspicious).

**The deeper rule:** When wiring up a config field, audit *every other config field with the same operational shape* (operator-vetting suppression list) to confirm it's actually consulted somewhere. Same shape = same bug class. Phase06#3 says "flags not in weights file are dead code"; the parallel rule is **"config fields not consulted by any unit are dead code with the same negative value."**

-> CF-37 (dead-config audit pattern) + new rule for `config.md`.

---

### 2. Elevation-degradation is invisible to every existing verification tier
<!-- tags: testing,verification,elevation,multi-tier -->

**Symptom:** Non-elevated dev-box run completed cleanly. Banner showed `BOTNET TRIAGE VERDICT` exactly as the elevated run did. Operator looked at the JSON and noticed several connection rows had `ProcessPath: null` and `CommandLine: null`. There was a single `WARN NOT_ELEVATED` line buried in the middle of the log, easy to miss.

**Root cause:** No verification tier in Tiers 1-7 (from phase08) ever ran the toolkit non-elevated. The dev box, the clean VM, every CI scenario --- all were elevated PowerShell sessions. The non-elevated execution path *worked* mechanically (no unhandled exceptions, exit code 0, JSON valid), it just *degraded silently*. The user couldn't tell from the verdict banner whether the run was authoritative or had giant blind spots.

**Three sub-bugs from one root cause:**
1. **Visibility gap on the operator's screen** --- summary banner identical to elevated. Fix: prominent multi-line `** NOT ELEVATED -- VISIBILITY LIMITED **` banner gated on `$script:Elevated -eq $false`.
2. **Visibility gap in the JSON artifact** --- meta block had no elevation field. Fix: `elevated = [bool]$script:Elevated` in the JSON meta block, typed as bool not string so downstream tooling can filter.
3. **Visibility gap on individual rows** --- NULL `ProcessPath` / `CommandLine` shipped without annotation. Fix: `EnrichmentIncomplete` flag on rows where the enrichment was attempted but yielded null --- tells the operator "this row's signal is partial; non-elevation may explain it."

**The deeper rule:** **Elevation-degradation is its own bug class**, distinct from data-path bugs and from cross-stage bugs. Mechanical correctness under degraded permissions is not the same as informative behavior under degraded permissions. A tier that exercises the degraded path has to actually *run in the degraded environment* --- you can't simulate it by reading the code, because the bug is "the operator is misled," not "the code throws."

-> CF-36 (Tier 6 non-elevated baseline as mandatory) + addition to phase08_verification_tiers.md.

---

### 3. EnrichmentIncomplete forced a refinement of the "dead flag" rule
<!-- tags: heuristics,scoring,diagnostic-flags -->

**Symptom (initial):** When designing the fix for bug 2's row-level visibility gap, the obvious move was a flag that says "this row's enrichment is incomplete." But phase06#3 says **flags not in the weights file are dead code, delete them**. Was `EnrichmentIncomplete` going to be dead?

**Answer:** No --- because it's in the weights file with weight `0`. The rule's letter says "must be in the weights file"; the rule's spirit was "must contribute to the verdict." `EnrichmentIncomplete` is in the file (so it's not dead by the letter), but contributes 0 to the score (so it's dead by the spirit). The two interpretations diverge for the first time.

**Resolution:** The rule needs a carve-out. **Diagnostic-only flags** (weight 0) are a legitimate category --- they exist to communicate signal *to the operator on a specific row* without affecting the *aggregate verdict*. `EnrichmentIncomplete` answers "why might this row look quieter than it should?" --- a question only the operator can act on, not a question the verdict-classifier needs to know.

The phase06#3 rule should be re-stated as: **"Flags absent from the weights file are dead code. Flags present with weight 0 are diagnostic-only flags --- legitimate, but must be marked as such and never appear in scoring math."** The existing rule wording had assumed every flag wanted to influence scoring; the carve-out lets the rule keep its teeth against forgotten flags while not blocking the diagnostic-flag pattern.

**Why this matters beyond EnrichmentIncomplete:** Phase 1.3 (ASN enrichment) is going to want similar diagnostic-only flags --- "ASN lookup failed, /24 fallback used" --- where the row is annotated for operator understanding but the verdict shouldn't move because of a third-party DNS hiccup. Codifying the pattern now prevents Phase 1.3 from rediscovering it.

-> CF-38 (formalize diagnostic-only-flag pattern) + edit to `heuristics.md`'s dead-flag rule.

---

## Free Observations (not bugs, but worth recording)

### 1. Non-elevated execution can still see SYSTEM-owned connections
<!-- tags: powershell,permissions,observation -->

I expected `Get-NetTCPConnection` under non-elevated to either error or to show only the user's own processes. It actually returned **all connections including SYSTEM-owned ones** --- the OwningProcess column populated correctly. What it *did* fail at was downstream: `Get-CimInstance Win32_Process` for a SYSTEM PID under non-elevation returns the PID and Name but not `ExecutablePath` or `CommandLine`. So the connection enumeration is intact, the *enrichment* is what degrades. Useful to know: a non-elevated triage still has wide visibility on *what's connecting*, just not on *what binary is doing the connecting*.

This affects how Tier 6 should be designed --- the meaningful test is "are connections enumerated and ranked correctly with degraded enrichment," not "does the toolkit fail gracefully." It does not fail; it produces useful but partial output.

---

### 2. ParentProcessName survives non-elevation
<!-- tags: powershell,permissions,observation -->

Phase 1.2's parent-name lookup builds `$parentNameIndex` from `$procIndex` keys (PID->ParentPid->Name chain). Both lookups use the WMI fields that *do* populate under non-elevation. So `ParentProcessName` enrichment is **available even on non-elevated runs**, even when `ProcessPath` and `CommandLine` are NULL. This means the new `SuspiciousParentProcess` flag (svchost not under services.exe) can fire correctly under non-elevation --- the highest-signal new flag from Phase 1.2 is the one most resilient to the elevation degradation.

This is accidental good design (the parent lookup happened to pick fields that weren't admin-gated) but worth documenting so Phase 1.3 stays in the same lane for ASN enrichment --- prefer fields that don't require admin where possible.

---

## Design Decisions

### 1. Banner gate uses `-eq $false`, not `-not`

```powershell
if ($script:Elevated -eq $false) { ... show NOT ELEVATED banner ... }
```

`$null -ne $false`, so `if (-not $null)` would *also* fire the banner if `$script:Elevated` were never set --- and the code that sets it lives in `U-ParamValidate`, which is the very first unit. If validation throws or is skipped, `$script:Elevated` stays unset. `-eq $false` fires only when the value is *literally* `$false`, not when it's missing. The "missing" case is now logged separately by `U-ParamValidate` itself, so a missing elevation state is a separate signal from a confirmed-non-elevated state.

### 2. EnrichmentIncomplete is added inside the pre-retain block, not at the top of the loop

```powershell
if ($flags.Count -gt 0 -or $iocHit) {
    if ($pd -and (-not $pd.Path -or -not $pd.CommandLine)) {
        $flags += 'EnrichmentIncomplete'
    }
    $results += [pscustomobject]@{ ... }
}
```

The flag fires only on rows that are *already going to be retained for some other reason* (a real flag or an IOC hit). It's an annotation on existing findings, not a new finding-generator. Adding it at the top of the loop would have made every connection on a non-elevated run a finding --- the `EnrichmentIncomplete` count would have exploded to ~hundreds of rows of "we don't know what this is," which is the opposite of useful.

This is the same shape as phase08#2pitfall (cross-stage filtering): the flag must live where the data lives, and the data lives inside the retain-decision block.

### 3. The signer cache is per-invocation, not per-process or persistent

`$signerCache = @{}` is initialized at the top of `U-ConnectionsSnapshot` and discarded when the function returns. Not persistent across runs, not shared with other units. Two reasons:

1. **Signer state can change** --- a binary that was signed today may be unsigned (or differently signed) tomorrow if the certificate is revoked or the file is replaced. A persistent cache would mask that.
2. **Per-invocation is sufficient** --- the typical phase has 50-200 connection rows, with maybe 10-30 distinct binary paths. Cache hit rate within one invocation is high; the marginal value of carrying it across invocations is small and the correctness risk is real.

This is a different decision than the ASN cache will be in Phase 1.3 --- ASN data is much more stable (months-to-years) and worth persisting. Document the difference when CF-31 lands.

---

## Carry-Forwards (new)

| ID | Title | Surface | Action |
|----|-------|---------|--------|
| CF-36 | Tier 6 non-elevated baseline is a mandatory verification tier | `lessons_learned/phase08_verification_tiers.md` + future Phase 1.3+ verification plans | Add Tier 6 (non-elevated baseline) to phase08; bump cross-host to Tier 7. Tier 6 must run on a real desktop with operator state, not a clean VM. Required to exclude the elevation-degradation bug class. |
| CF-37 | Dead-config audit when wiring new operator-vetting fields | `modules/Invoke-BotnetTriage.ps1` + `lessons_learned/ai/config.md` | When wiring up a new operator-vetting config field (BeaconWhitelist, LocalOnlyPorts, etc.), audit *every other config field with the same shape* (suppression / allowlist / vetting list) to confirm each is actually consulted by some unit. Add a rule to `config.md` --- "fields not consulted by any unit are dead code." |
| CF-38 | Formalize diagnostic-only flag pattern (weight=0) | `lessons_learned/ai/heuristics.md` --- dead-flag rule | Refine the dead-flag rule: *absent* from weights file = dead; *present with weight 0* = diagnostic-only flag, legitimate, must be marked as such. Phase 1.3 will need this for ASN-lookup-failed flags. |

## Carry-Forwards (closed)

- **CF-29 (ListeningPorts 22% fire rate):** closed by `HighPortNonServerProcess` -> `HighPortAllInterfaces` rename + tighten in Phase 1.2.

## Carry-Forwards (still open from prior phases)

- **CF-16, CF-17, CF-18, CF-19:** unchanged (deferred to a tuning pass)
- **CF-26 (dev-box noise):** partial improvement from Phase 1.2 + 1.2.1, not fully closed --- still some Medium-tier noise on dev box from CF-28 (ScheduledTasks LOLBin Microsoft allowlist)
- **CF-28 (ScheduledTasks LOLBin Microsoft allowlist):** still open --- Top 5 on V3 are all `ScheduledTasks LOLBinInArgs`; Phase 1.3 candidate
- **CF-30 (bash + pwsh -Command graduation):** unchanged
- **CF-31 (now):** Phase 1.3 ASN enrichment via Cymru DNS (re-shaped in phase13, premise updated)
- **CF-32, CF-33, CF-34, CF-35:** unchanged (Phase 1.3 work)

---

## What Would Have Caught This (per the bug-fix-reflection rule)

| Bug | What would have caught it |
|-----|---------------------------|
| OneDrive false-High (TrustedSigners dead config) | A "dead config audit" sweep at the end of Phase 1.2 --- grep `$script:Exclusions.X` for every X loaded by `U-LoadConfig`, confirm each is consulted by a unit. Codified as CF-37. |
| Quiet non-elevated UX | A non-elevated dev-box run before declaring Phase 1.2 shipped. The clean VM was elevated; the dev box was untested non-elevated. Codified as CF-36 (Tier 6). |
| NULL fields shipping silently | Same Tier 6 run --- the NULL columns would have been visible in the JSON inspection step. CF-36 covers this too. |

All three of the bugs share a single root cause: **the verification suite did not run the toolkit in the operational state where the bugs lived.** Tier 6 (non-elevated baseline on a real desktop) is the single load-bearing addition that excludes all three.

---

## What This Reflection Did Not Cover

- The CF-28 LOLBin allowlist work (still open, Phase 1.3)
- The Phase 1.3 implementation plan for ASN enrichment (separate planning doc)
- The README update for the new banner / `EnrichmentIncomplete` flag / `TrustedSigners` semantics (ships with Phase 1.3)
- A2 (BeaconWhitelist positive test) --- non-blocking, scheduled as a Phase 1.3 pre-flight smoke test
