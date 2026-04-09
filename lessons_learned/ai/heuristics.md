---
name: heuristics
description: Detector and scoring rules — false-positive rate ceilings, dead-flag detection, threshold/floor consistency, cross-stage data-flow pitfalls.
type: ai-subject
---

# Heuristics — Subject Rules

Rules for designing detectors, scoring weights, and risk classifiers in this toolkit. Anchor topics: false-positive rate ceilings, dead-code flags, threshold/floor math consistency, and architecture pitfalls in cross-stage data flows.

---

## False-Positive Discipline

### Any detector firing on >10% of input is broken

**When:** Adding or tuning a heuristic detector (suspicious-process, raw-IP-DNS, listening-port-on-all-interfaces, etc.).
**Rule:** Corpus-check against a clean baseline host before ship. If the detector fires on >10% of its input, the threshold is wrong, the rule is wrong, or the population is wrong — fix one of those. High-fire detectors train operators to ignore the column.

*Source: phase06_invoke_triage_build.md#3*

---

### Flags not in the weights file are dead code with negative value

**When:** A detector emits a flag (e.g. `'SuspiciousArgs'`) that has no corresponding entry in `triage-weights.json`.
**Rule:** Delete the emit code. The flag consumes operator attention column-space without influencing the verdict — strictly worse than not flagging. Either add the weight or delete the detector. Don't ship dead flags.

*Source: phase06_invoke_triage_build.md#3*

---

## Threshold Math

### Thresholds and floors must be checked against each other

**When:** Tuning IOC-match multipliers, score floors, or verdict thresholds.
**Rule:** Run the math on edge cases. A 10×2.0=20 IOC-only floor lands in `Low` when `Medium=25` — operator sees an IOC match flagged `Low` and assumes the tool is broken. Each multiplier change demands a re-check of every threshold downstream. Check before ship; lurks until pipeline test otherwise.

*Source: phase08_verification_tiers.md#3pitfall*

---

## Cross-Stage Architecture Pitfalls

### Cross-stage filter that's correct in isolation can be wrong in pipeline

**When:** A collection unit filters out "uninteresting" rows before storing them, and a later processing unit (`U-CorrelateIOCs`) needs to see those rows.
**Rule:** Test the pipeline end-to-end with data only visible via the cross-stage path. Each unit can pass its own unit test and the pipeline still be broken — the bug is the *interaction*. Add an `iocHit` pre-retain check at every collection unit that downstream IOC correlation will scan.

```powershell
$iocHit = ($script:IOCSet.Count -gt 0 -and $entry -and $script:IOCSet.Contains([string]$entry))
if ($flags.Count -gt 0 -or $iocHit) { ... store item ... }
```

**Symptom:** `IOC_CORRELATED: 0 finding(s)` despite a known IOC being in live data.

*Source: phase08_verification_tiers.md#2pitfall*

---

### Concentrate fallback complexity on the canonical no-launcher path

**When:** Tempted to add inline-fallback stubs to every script in the toolkit "for safety."
**Rule:** Identify the *one* file that IS the standalone-paste path (e.g. `Invoke-BotnetTriage.ps1`) and concentrate all fallback complexity there. Other files can assume their dependencies are loaded. Some files ARE the fallback; the rest are normal-load.

*Source: phase07_deploy_launcher.md#2design*

---
