---
name: phase12_diagnostic_playbook
description: Meta-reflection on the Phase 1.1 encoding-bug diagnostic. Extracts the 13-step debugging playbook used (read-error -> mojibake-fingerprint -> ground-truth-tool -> codepoint-enumeration -> bounded-map -> apply -> same-tool-verify -> different-tool-cross-check -> functional-test -> scope-expansion -> document-with-exclusions). Also captures three new findings from the clean-VM baseline run that the dev box could not have surfaced.
type: reflection
---

# phase12_diagnostic_playbook --- Meta-Reflection on the Phase 1.1 Encoding Diagnostic

> **Scope:** This is not a bug-fix reflection (phase11 is). This is a *method* reflection on the debugging process used to find and fix the PS 5.1 encoding bug, captured because the operator explicitly asked for the diagnostic steps to be reviewed and turned into lessons. The playbook generalizes beyond encoding bugs --- it is the shape of any "tool's display IS the bug" debugging session.
> **Date:** 2026-04-09
> **Triggered by:** Operator request after the Phase 1.1 fix verified clean on a Windows 11 VM with PS 5.1.26100.6899.

---

## Applied Lessons

| Rule (file -> heading) | Outcome | Note |
|------------------------|---------|------|
| phase05_shared_helpers.md#3 --- never cram multi-line pwsh into bash-quoted -Command | **Re-applied (3rd phase)** | First diagnostic attempt was a `pwsh -NoProfile -Command "..."` from Bash with a regex containing `\\\\output\\\\`. Bash ate the backslash escaping. Switched to Write-then-pwsh-File. This is the **third phase** the same lesson has applied (phase05 origin, phase11 first re-app, phase12 second re-app). It is a Foundation-tier candidate by any reasonable graduation rule. |
| phase08_verification_tiers.md#1 --- each tier must exclude a different bug class | **Re-applied as design constraint** | The diagnostic playbook is structured around this lesson: each diagnostic step excludes a *different* bug class. Re-running the same tool on the same files would not exclude anything new. Step 10 (parser check) and Step 11 (Tier 1 dry-run) are deliberately *different tool classes* than Step 4 (byte audit) for this reason. |
| phase09_readme_expansion.md#1 --- verification belongs in the same step as the change | **Applied** | Discovery tools (`_audit_encoding.ps1`, `_audit_chars.ps1`) became the regression tests. The same script used to *find* the bug was the script used to *prove* it gone. Zero additional code. |
| phase06_invoke_triage_build.md#3 --- corpus-check heuristics against a clean baseline | **Validated --- and surfaced two new pitfalls** | The clean VM is now the baseline. Dev box has 79 findings; clean VM has 28. But the clean VM also exposes detectors that fire on Microsoft's own built-in scheduled tasks (CF-28) --- something the dev box's noise had hidden. |

---

## The 13-Step Diagnostic Playbook

The user's bug report was a 60-line PS error transcript. The fix involved 6 files and 4 codepoint substitutions. Between those two endpoints, the diagnostic followed a specific shape. Numbering the steps because the *order* matters as much as the steps themselves --- changing the order slows the diagnosis by hours.

### Step 1: Read the entire error transcript verbatim --- not the cited line

The error reported `At Deploy.ps1:253` and pointed at a `|` inside a string. The wrong move would have been to open Deploy.ps1 at line 253 and try to understand why a pipe in a string was being parsed as a pipeline operator (it shouldn't be --- and *isn't*, in normal PS). The right move was to read the *entire* pasted error, including the lines that looked like incidental cascade. Line 295 contained `(non-fatal â€" Phase 1 has no API dependencies)"`. That sequence named the bug class. The cited line 253 was downstream noise.

**Generalizable rule:** When PowerShell reports cascading parser errors with a "Missing closing '}'" trail back through nested function definitions, **the cited line is always wrong**. Read the whole error from bottom to top --- the *first* place the parser got confused is closer to the bottom of the error output, not the top.

---

### Step 2: Recognize the mojibake fingerprint

`â€"` is the Windows-1252 rendering of UTF-8-encoded U+2014 (em-dash). The byte sequence `0xE2 0x80 0x94` decoded as three single-byte Windows-1252 characters is exactly `â € "`. There are about a dozen of these fingerprint sequences worth memorizing:

| UTF-8 char | Codepoint | Mojibake (Windows-1252) |
|------------|-----------|-------------------------|
| em-dash `--` | U+2014 | `â€"` |
| en-dash `-` | U+2013 | `â€"` |
| smart-quote left `"` | U+201C | `â€œ` |
| smart-quote right `"` | U+201D | `â€` |
| apostrophe-curly `'` | U+2019 | `â€™` |
| ellipsis `...` | U+2026 | `â€¦` |
| right arrow `->` | U+2192 | `â†'` |
| non-breaking space | U+00A0 | `Â ` |
| degree `°` | U+00B0 | `Â°` |

**Generalizable rule:** Any time a Windows tool produces text containing `â€`, `â†`, `Â`, or `Ã`, the diagnosis is over before it began: **UTF-8 bytes are being read by something that expects Windows-1252**. Skip the parser-error chase and go directly to the encoding fix.

---

### Step 3: Form the hypothesis in one sentence

> "PS 5.1 reads .ps1 files as Windows-1252 by default; the file is UTF-8 without BOM; em-dashes in the source corrupt parser state."

A one-sentence hypothesis is testable. A multi-sentence hypothesis is a guess. If you cannot state the hypothesis in one sentence, you do not yet have one --- you have a confused suspicion.

**Generalizable rule:** Before writing any diagnostic code, force yourself to write the hypothesis in a single sentence. If you cannot, re-read the error.

---

### Step 4: Pick a ground-truth tool that bypasses the broken layer

The bug was in PowerShell's text-decoding layer. Using `Get-Content` to investigate would have produced exactly the same broken decode that caused the bug --- the diagnostic tool and the buggy tool would have agreed, and the bug would have looked like "the file is correct, somehow PowerShell is wrong."

The right tool was `[System.IO.File]::ReadAllBytes($path)`. That returns a `byte[]` --- no encoding, no string conversion, no PowerShell layer between you and the disk. From there, counting bytes >127 is mechanical.

**Generalizable rule:** When the bug is in tool X's *display* of data, you cannot diagnose it with tool X. Find a tool that operates *one layer below* the broken layer --- raw bytes for encoding bugs, raw network packets for protocol bugs, raw timing for race conditions. The "ground truth" tool is always less ergonomic than the broken one. That is the price of getting an answer.

---

### Step 5: First diagnostic attempt failed --- and the failure mode was a known lesson

I tried to enumerate non-ASCII bytes via `pwsh -NoProfile -Command "..."` from a bash terminal. Bash ate the backslash-escaping in `\\output\\`. The error came back: `Invalid pattern '\output\' at offset 2. Unrecognized escape sequence \o.` Stopped immediately, recognized it as phase05#3 (third re-application now), wrote the script to a `.ps1` file and used `pwsh -File`. Worked first try.

**Generalizable rule:** When a diagnostic command fails for reasons that look like quoting / escaping / encoding rather than the underlying problem, **stop**. The diagnostic environment is now compromised. Use a different invocation path before continuing --- otherwise you will get a "second bug" obscuring the first.

---

### Step 6: Quantify before fixing

Before any substitution, the audit produced concrete numbers:

- 3 .ps1 files affected (later expanded to 6 text files total)
- 213 non-ASCII bytes (later expanded to 388)
- 4 distinct codepoints

Knowing the *count* of distinct codepoints --- 4, not "many" --- changed the fix strategy. With 4 codepoints, a deterministic substitution map is the right tool. With 40 codepoints, a regex strip-and-replace might have been justified. The numbers drove the design.

**Generalizable rule:** Quantify the bug surface before designing the fix. "How many files? how many bytes? how many distinct values?" answers belong on paper before any `Edit` runs. Number-driven decisions are auditable; vibe-driven decisions are not.

---

### Step 7: Bounded substitution map, not greedy strip

```powershell
$map = @{
    [char]0x2014 = '--'  # em-dash
    [char]0x2192 = '->'  # right arrow
    [char]0x2190 = '<-'  # left arrow
    [char]0x2500 = '-'   # box-drawings horizontal
}
```

A reader of this map can verify the substitution is correct *without running the code*. The alternative --- `[regex]::Replace($text, '[\u0080-\uFFFF]', '?')` --- would have fixed the parsing bug AND silently destroyed any future non-ASCII content (which we may want, e.g. legitimate Unicode in IOC entries). Bounded maps are reversible; greedy strips are not.

**Generalizable rule:** When fixing a bug, prefer the *narrowest* fix that resolves it. Narrow fixes are easy to review, easy to reverse, and easy to extend. Broad fixes accumulate scope and hide future bugs inside the same change.

---

### Step 8: Apply the fix using the same low-level tool

The fix used `[System.IO.File]::WriteAllBytes($path, $ascii.GetBytes($text))` --- *not* `Set-Content`, *not* `Out-File`, *not* `$text | Out-File`. The reason: `Set-Content` and `Out-File` both apply PowerShell's default encoding, which differs between PS 5.1 and PS 7 and between machines, and which the original bug was caused by. Using the same broken layer to write the fix would have left the file looking different on disk depending on which PS version ran the script.

**Generalizable rule:** The fix for an encoding bug must be applied with a writer that bypasses encoding negotiation. Read raw bytes, mutate as text, write raw bytes. If at any point you let PowerShell choose an encoding for you, you have re-introduced the bug class.

---

### Step 9: Verify with the SAME tool used to discover

After the fix, I re-ran `_audit_encoding.ps1` --- the same script that found the bug. Result: 0 non-ASCII bytes in all 6 files. The discovery tool became the regression test, no extra code.

This is *not* the same as Step 11 (different-tool cross-check). Step 9 proves "the bug as I detected it is gone." Step 11 proves "no other bug class has been introduced." Both are necessary; neither is sufficient.

**Generalizable rule:** The tool that found the bug should always be the first tool that verifies the fix. If the discovery tool still finds the bug after the fix, the fix is wrong --- no other verification matters yet.

---

### Step 10: Cross-check with a DIFFERENT tool class

After the byte-level audit confirmed clean, I ran the AST parser on all 3 .ps1 files (`[Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)`). The byte audit excludes "non-ASCII bytes remain"; the parser check excludes "the substitution accidentally created a syntax error" (e.g. if `--` had landed inside a numeric expression, it would have been parsed as decrement). Different bug classes; different tools required to exclude each.

**Generalizable rule:** Two verification passes that exercise the same code path are one verification pass. Each pass should exclude a *different* bug class. If you cannot articulate which bug class a verification pass excludes, that pass is decoration.

---

### Step 11: Run an existing functional test

Tier 1 dry-run on the dev box. 18 units, 0 errors, exit 0. This excludes "the fix worked syntactically but broke runtime behavior" --- a class neither byte-audit nor parser-check can catch.

**Generalizable rule:** After any change to a script that ships, re-run the cheapest existing functional test. If no functional test exists, write a one-liner smoke test. The cost is bounded; the value is "did the change break the thing the script does?"

---

### Step 12: Expand the audit scope --- "would this same bug exist elsewhere?"

After the .ps1 files were verified, I asked: "would the same root cause produce a bug in *other* text files the operator might read?" Audited `config/*.json`, `iocs/*.txt`, `.env.example`. Found 3 more files. Same root cause, same fix, applied in the same round-trip.

This step is the difference between a one-round hot-fix and a two-round one. If I had stopped at the .ps1 files, the operator would have run the fix on the VM, hit mojibake in `triage-weights.json`'s Description field, and we would be on round 2 of the same hot-fix.

**Generalizable rule:** When you find a bug, ask "what is the bug *class*, and where else could it manifest?" Then audit the surface. Most bugs have siblings. Finding them in the same session is cheaper than finding them next week.

---

### Step 13: Document with exclusions named --- not just the bug

The phase11 reflection names not just *what was wrong* but *what tier should have caught it*: CF-25 (PS 5.1 standalone-paste tier). A reflection that documents only the bug invites the same bug class to recur. A reflection that documents the *gap in coverage* turns the bug into a permanent improvement to the verification plan.

**Generalizable rule:** Every bug-fix reflection should answer two questions: (1) what was the bug, and (2) which test would have caught it. If the answer to (2) is "none of our tests would have," that is a CF, not a footnote.

---

## What the Clean VM Run Revealed (Beyond the Encoding Fix)

The successful run on DESKTOP-1ICTRR7 produced data that the dev box literally could not have produced. Three findings worth capturing:

### Finding 1: Clean VM baseline = 28 findings; dev box = 79 findings

| Bucket | Dev box | Clean VM | Delta |
|--------|---------|----------|-------|
| HIGH   | 3       | 0        | -3    |
| MEDIUM | 53      | 22       | -31   |
| LOW    | 23      | 6        | -17   |
| **Total** | **79** | **28** | **-51** |

The dev box has ~51 dev-tool-specific findings on top of the clean baseline. **CF-26 closes:** the heuristics are not broken, the corpus is. Operate on clean baselines for any future detector tuning. Dev-box runs are smoke tests, not measurements.

---

### Finding 2: Top-5 dominated by identical detector (CF-28 candidate)

```
1. [Medium] score=35  ScheduledTasks -- LOLBinInArgs
2. [Medium] score=35  ScheduledTasks -- LOLBinInArgs
3. [Medium] score=35  ScheduledTasks -- LOLBinInArgs
4. [Medium] score=35  ScheduledTasks -- LOLBinInArgs
5. [Medium] score=35  ScheduledTasks -- LOLBinInArgs
```

Five identical findings at identical score. The clean VM has zero third-party software --- these are **Microsoft's own built-in scheduled tasks** (Defender, Edge update, telemetry, customer experience, Windows Update). Microsoft uses `powershell -enc`, `rundll32`, and `regsvr32` legitimately in built-in tasks because the LOLBin classification applies to *operator behavior*, not to vendor inclusion.

This is a textbook phase06#3 violation: a detector firing on legitimate baseline behavior at high enough rate to dominate the top-5. Two possible fixes (not both):

1. **Allowlist the Microsoft signer / Author=Microsoft Corporation tasks** in `exclusions.json`. The signer check is high-confidence and cheap.
2. **Top-5 deduplication.** Even if the detector is right, showing five rows of the same flag is operator-hostile. Diversify the top-5 by flag combination so the operator sees five *different* signals, not five copies of one.

I prefer option 1 (allowlist by signer) because option 2 hides a noisy detector behind cosmetics. Tracked as **CF-28**.

---

### Finding 3: ListeningPorts fire rate 22% on clean VM (CF-29 candidate)

```
LISTENING_PORTS: 4 flagged of 18 total listening
```

4 / 18 = 22%. Phase06#3 says "any detector firing on >10% of input is broken." Clean Win11 has standard listening services (RPC mapper, NetBT, Server, etc.) listening on `0.0.0.0` for normal reasons. The "ListeningOnAllInterfaces" or "HighPortNonServerProcess" rule is too aggressive.

Tracked as **CF-29**. Same fix shape as CF-28: allowlist by signer (Windows built-ins) before broader rule changes.

---

### Finding 4: CF-25 de facto satisfied for current build

The successful PS 5.1 run on the VM is exactly what Tier 5b (CF-25) would have been: standalone-paste-equivalent execution under Windows PowerShell 5.1 against the canonical target environment. CF-25 should remain *open* until the tier is *codified* (a runnable script in `output/_tier5b_ps51.ps1` with documented pass criteria), but for the current commit the bug class it owns has been exercised.

---

## Pitfalls

### 1. The bash regex incident is the third re-application of phase05#3
<!-- tags: bash,powershell,tools -->

phase05_shared_helpers.md#3 ("never cram multi-line pwsh into bash-quoted -Command") is now a confirmed Foundation-tier rule by any reasonable graduation criterion: original phase05 + re-applied phase11 (encoding diagnostic first attempt) + re-applied phase12 (this very phase). Three independent re-applications across distinct contexts, all costing time before the lesson kicked in.

**Lesson:** The graduation pass deferred by CF-21/CF-23 should *prioritize* this rule. Until it is in the Foundation table, it is invisible to AI assistants browsing rules by topic and the next user will hit it again.

---

### 2. The discovery script's "safety net" was decoration, not safety
<!-- tags: powershell,verification,defensive -->

`_fix_encoding.ps1` had a `if ($back.Contains('?')) { WARN }` check intended to catch ASCII-can't-represent characters. It fired on every file because the source legitimately contains `?` characters. The WARN line undermined trust in the script's other (real) output. Phase11 already captured this as a went-well-with-pitfall; restating it here because it intersects with Step 10 of the playbook (cross-checks must exclude *something* --- decoration that always fires excludes nothing).

**Lesson:** A check that fires on every input is not a check, it is noise. Either fix it to fire on the actual condition you care about, or delete it.

---

### 3. The encoding bug class is bigger than the encoding bug
<!-- tags: powershell,encoding,verification -->

Strictly, the user's report was "Deploy.ps1 won't parse on PS 5.1." Strictly, the fix is "replace 75 non-ASCII bytes in Deploy.ps1." Three steps of scope expansion happened:

1. Audit found the same root cause in `_Shared.ps1` and `Invoke-BotnetTriage.ps1`. Without those, the user would have hit the bug again at module load.
2. Audit found the same root cause in 3 non-.ps1 text files. Cosmetic, not functional, but operator-confusing.
3. Reflection identified the *missing tier* (CF-25). Without CF-25, the next module written for Phase 2 will have the same bug class because the same gap exists.

The "shipping fix" for the bug as reported is step 1 alone. The "actually-done fix" is steps 1+2+3. The temptation in any hot-fix is to ship step 1 and call it done. **Resist.** The CF system exists exactly to capture step 3 when step 3 cannot be done in the same change.

---

## Design Decisions

### 1. New phase reflection rather than expanding phase11
<!-- tags: lessons-learned,scoping -->

Phase11 documents the *bug*: what broke, how it was fixed, what files changed. Phase12 documents the *method*: the 13-step playbook, the diagnostic shape, the tool-class discipline. They are separate concerns. Merging them would either bury the playbook inside a bug-fix narrative (so future readers looking for the bug do not learn the method) or bloat phase11 past the point where it can be skimmed. The two-file split costs ~5 minutes of cross-referencing and pays back every time someone needs the playbook without the encoding context.

---

### 2. Playbook captured as numbered steps, not as free prose
<!-- tags: lessons-learned,docs -->

The 13 steps are numbered because *the order matters*. Step 4 (ground-truth tool) before Step 6 (quantify) because you cannot quantify until you have a tool that can see the bug. Step 9 (same-tool verify) before Step 10 (different-tool cross-check) because the same-tool check is the cheap one and a failure there means stop. Step 12 (scope expansion) before Step 13 (document) because you do not know the full bug surface until you have looked.

A reader who follows the steps in order has the diagnostic shape internalized. A reader who reads them as a bullet list does not. Prose flattening loses the dependency graph.

---

### 3. CF-26 closes, CF-25 stays open, CF-28 and CF-29 open
<!-- tags: planning,heuristics -->

CF-26 (dev box may have noise) is now answered with data: yes, the dev box has ~51 dev-tool findings on top of baseline. Closing it.

CF-25 stays open because the fix verified on the VM is *operator-driven*, not *test-driven*. Until there is a script (`output/_tier5b_ps51.ps1`) that an automated runner can invoke, the bug class is not actually owned by a tier. CF-25 closes when the script ships.

CF-28 (LOLBinInArgs firing on Microsoft built-ins) and CF-29 (ListeningPorts >10% on clean VM) are *new findings* that the dev box could not have produced. They belong in the Phase 1.2 detector-tuning pass.

---

## Carry-Forwards

### Updated

| ID | Status | Note |
|----|--------|------|
| CF-25 | **Open (de facto satisfied)** | PS 5.1 run on VM verified the encoding fix. Still needs to be codified as `output/_tier5b_ps51.ps1` before counted as a real tier. |
| CF-26 | **Closed --- answered with data** | Clean VM = 28 findings; dev box = 79. Difference is dev-tool noise, not heuristic regression. Operate on clean baselines for tuning. |

### New

| ID | Title | Surface | Action |
|----|-------|---------|--------|
| CF-28 | LOLBinInArgs detector dominates top-5 on clean VM with five identical Microsoft-built-in scheduled-task findings | `Invoke-BotnetTriage` U-ScheduledTasks + `config/exclusions.json` | Add `Authors` allowlist to exclusions schema (e.g. `"Microsoft Corporation"`, `"Microsoft"`); skip LOLBinInArgs flagging when task Author matches. Re-run on clean VM, expect top-5 to diversify. Do **not** fix via top-5 deduplication --- that hides a noisy detector behind cosmetics. |
| CF-29 | ListeningPorts fires on 22% of input on clean Win11 (>10% phase06#3 ceiling) | `Invoke-BotnetTriage` U-ListeningPorts + `config/exclusions.json` | Audit which built-in services trigger `ListeningOnAllInterfaces` and `HighPortNonServerProcess`. Allowlist by image-path for `svchost.exe` hosting standard NT services. Re-run, target <10% fire rate. |
| CF-30 | phase05_shared_helpers.md#3 (bash + pwsh -Command) has been re-applied 3x and is invisible at the AI-subject-file layer | `lessons_learned/INDEX.md` Foundation table + `ai/powershell.md` | Promote to Foundation tier in next graduation pass. Add to `ai/powershell.md` Bash Interop section as a stronger rule (currently a single went-well entry). |

---

## Permissions Gap Report

**None requested at start. None needed.** Read-only against `lessons_learned/`, `phase11_ps51_encoding_fix.md`, the user's pasted VM run output. Write to `lessons_learned/phase12_diagnostic_playbook.md` + Edit to `lessons_learned/INDEX.md` + Edit to `lessons_learned/ai/powershell.md` and `lessons_learned/ai/process.md` (rule extraction). No new permissions surfaced.

---

## Summary

| Metric | Value |
|--------|-------|
| Diagnostic playbook steps | 13 |
| Time from user error report to root-cause hypothesis | ~20 seconds (mojibake fingerprint) |
| Files audited (encoding) | 6 shipping text files |
| Files audited (link integrity, post-doc-update) | 18 markdown files |
| New verification rules extracted | 11 (added to AI subject files) |
| New CFs | 3 (CF-28, CF-29, CF-30) |
| Closed CFs | 1 (CF-26 --- dev box noise confirmed) |
| Mojibake fingerprints documented in cheat-sheet | 9 |
| Tier coverage gap documented | CF-25 (still open until codified) |
| Foundation graduation candidates surfaced | 1 strong (phase05#3 bash interop, 3rd re-app) |
| Operator clean-VM baseline (HIGH/MED/LOW) | 0 / 22 / 6 (28 total) |
| Dev-box noise overhead vs clean baseline | 51 findings (~182%) |

---
