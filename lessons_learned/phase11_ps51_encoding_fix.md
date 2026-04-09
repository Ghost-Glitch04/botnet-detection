---
name: phase11_ps51_encoding_fix
description: Phase 1.1 hot-fix — Deploy.ps1 (and 5 other shipping text files) contained UTF-8-encoded em-dashes, arrows, and box-drawing characters with no BOM. PowerShell 5.1 read the bytes as Windows-1252, mojibake corrupted parser state, Deploy.ps1 failed to parse on the first VM test. ASCII-replaced 175 non-ASCII bytes across 6 files. Validated parser-clean + Tier 1 dry-run still passes.
type: reflection
---

# phase11_ps51_encoding_fix --- PowerShell 5.1 + UTF-8-without-BOM Hot-Fix

> **Scope:** Operator ran `. .\Deploy.ps1` from a fresh `powershell.exe` (Windows PowerShell 5.1) session on a Windows 11 test VM. Parser blew up with cascading "Expressions are only allowed as the first element of a pipeline" errors. Root cause: UTF-8 em-dashes in comments/log-messages, no BOM, PS 5.1 reads `.ps1` files as Windows-1252 by default.
> **Date:** 2026-04-09
> **Triggered by:** First out-of-dev-box test run.

---

## Applied Lessons

| Rule (file → heading) | Outcome | Note |
|------------------------|---------|------|
| phase08_verification_tiers.md#1 — each tier excludes a different bug class | **Validated by failure** | Phase 1 had no PS-5.1 tier. The "Windows PowerShell 5.1 + UTF-8-without-BOM" bug class was uncovered by every existing tier because the dev box runs PS 7. Operator's first VM test was the *de facto* PS-5.1 tier — and it caught the bug. The lesson re-applies as a *predictive* warning: any uncovered bug class will surface on the first encounter with the environment that exposes it. |
| phase05_shared_helpers.md#3 — never cram multi-line pwsh into bash-quoted -Command | **Re-applied** | First diagnostic attempt used `pwsh -NoProfile -Command "..."` from Bash with a regex containing `\\\\output\\\\`. Bash mangled the backslash escaping → `Invalid pattern '\output\' at offset 2`. Switched to `Write` a `.ps1` then `pwsh -File`. Worked first try. Same lesson, third phase. Should be a Foundation-tier rule. |
| phase06_invoke_triage_build.md#3 — corpus-check heuristics against a clean baseline | **Surfaced unrelated finding** | Tier 1 dry-run on the dev box (post-fix) returned `HIGH: 3, MEDIUM: 53, LOW: 23`. 53 medium findings is well over the >10% ceiling rule. Not a regression from this phase, but worth a CF for Phase 1.2. |
| phase09_readme_expansion.md#1 — verification belongs in the same step as the change | **Applied** | Built three diagnostic scripts (`_audit_encoding.ps1`, `_audit_chars.ps1`, `_parser_check.ps1`) in lockstep with the fix. Each one excludes a sub-class: byte-level audit catches "any non-ASCII," char-level audit names the codepoints, parser check catches "did the substitution break syntax." All three ran sub-second; combined they took less time than the original bug report. |

---

## What Went Well

### 1. Mojibake signature in the error output named the bug class instantly
<!-- tags: powershell,encoding,debugging -->

The user's pasted error contained `non-fatal â€" Phase 1 has no API dependencies`. The `â€"` sequence is the unmistakable Windows-1252 rendering of UTF-8-encoded U+2014 (em-dash, three bytes: `0xE2 0x80 0x94`). Diagnosis took ~20 seconds: the cascading parser errors at line 253 were downstream noise; the smoking gun was in the *quoted* error text the user had pasted with the report.

**Lesson:** When PowerShell 5.1 produces "Expressions are only allowed as the first element of a pipeline" combined with `Missing closing '}'` on functions far above the cited line, scan the *entire* error output for `â€"`, `â€™`, `â€œ`, `â€`, `Â`, or any other Windows-1252-rendering-of-UTF-8 sequence. Those strings name the encoding bug; the parser cascade is just collateral damage from a multi-byte sequence eating delimiters.

---

### 2. Codepoint enumeration before bulk fix
<!-- tags: powershell,encoding,debugging -->

Before writing any replacement code, I ran `_audit_chars.ps1` to enumerate every non-ASCII codepoint in the affected files and count occurrences. Result across the 6 shipping text files:

| Codepoint | Char | Count | ASCII map |
|-----------|------|-------|-----------|
| U+2014 | em-dash `--` | 65 | `--` |
| U+2192 | right arrow `->` | 15 | `->` |
| U+2190 | left arrow `<-` | 1 | `<-` |
| U+2500 | box-drawings horizontal `-` | 74 | `-` |

Four codepoints, total. *Knowing* the bounded set let me write a deterministic replacement map (`@{ [char]0x2014 = '--'; ... }`) instead of a fuzzy "strip everything non-ASCII" pass. The fix script is auditable: anyone can read the map and reproduce the substitution.

**Lesson:** Before bulk-fixing an encoding problem, enumerate the codepoints and counts. The temptation is to write `[regex]::Replace($text, '[\u0080-\uFFFF]', '?')` and call it done — but that erases information you may need later. Bounded substitution maps are reversible; greedy strip-and-replace is not.

---

### 3. Proactive audit of non-PS1 text files prevented a round-trip bug
<!-- tags: powershell,encoding,verification -->

After fixing the three `.ps1` files and verifying parser-clean, the temptation was to declare done. Instead I audited *all* shipped text files (`config/*.json`, `iocs/*.txt`, `.env.example`). Found three more files with non-ASCII bytes. None were functional bugs (em-dashes lived in `Description` JSON fields and comment lines), but PS 5.1's `Get-Content -Raw` would render them as mojibake when reading the configs at runtime — and the user would *see* the mojibake on the VM and reasonably wonder "is this another bug?"

Fixing them now closed the loop in one round-trip. If I'd shipped only the PS1 fix, the user would have run `Invoke-BotnetTriage` on the VM, seen `Description: "Risk weights for Invoke-BotnetTriage â€" tunable per engagement"` in the log, and we'd be on round 2 of the same hot-fix.

**Lesson:** When the root cause is "PS 5.1 + UTF-8-without-BOM", the fix scope is *every text file the operator might read*, not just the ones the parser chokes on. Cosmetic mojibake on a security tool erodes trust as fast as a real bug — operators don't know which is which.

---

## Pitfalls

### 1. Phase 1 verification ran entirely on PowerShell 7
<!-- tags: testing,powershell,verification -->

Tiers 1, 1a, 2, 2a, 3, 4, 5 all ran on the dev box's `pwsh.exe` (PowerShell 7.6). The README's Requirements table claims `PowerShell 5.1 (built-in) or 7.x` and was *labeled validated*, but no tier ran under PS 5.1. The encoding bug was undetectable on the dev box because PS 7 reads UTF-8-without-BOM correctly — and the dev box doesn't have `powershell.exe` in a state where we'd think to invoke it.

This is exactly the multi-tier rule (phase08#1) re-applied: each tier must exclude a different bug class. We had no tier excluding "PS 5.1 reads `.ps1` files with the wrong encoding." The bug was unowned, so it shipped.

**Lesson:** Add a Tier 5b — "Run Tier 5 standalone-paste from `powershell.exe` (Windows PowerShell 5.1), not just `pwsh.exe`." This is the only way to catch encoding bugs that PS 7's UTF-8 tolerance hides. Track as **CF-25**.

---

### 2. The lesson "tag with the topic the rule teaches" (CF-24) hits another dead-zone
<!-- tags: lessons-learned,scoping,encoding -->

Where should the encoding bug rule live in the AI subject files? It's a **PowerShell** rule (`powershell.md`) by technology, but it's a **testing** rule (`testing.md`) by topic — "tier coverage gap caused this bug" is what makes the rule actionable. CF-24 already flagged that primary tags should name the topic the rule teaches; this phase is the second example of the same gap.

The encoding rule belongs in *both* `powershell.md` (under a new "Encoding & BOM" section) and `testing.md` (cross-listed in the multi-tier discussion). I'll add it to both during the next graduation pass — for now, INDEX backfill captures it once.

---

### 3. Diagnostic script `Contains('?')` round-trip check was a false positive
<!-- tags: powershell,verification,defensive -->

The first version of `_fix_encoding.ps1` had a "safety net":

```powershell
$back = $ascii.GetString($bytes)
if ($back.Contains('?')) {
    Write-Host "WARN: $f contains chars that ASCII can't represent — investigate"
}
```

The intent was to catch cases where the substitution map missed a codepoint and ASCII encoding silently substituted `?`. But the source files contain *legitimate* `?` characters (regexes, conditionals, doc comments) — so the check fired every time and was meaningless.

**Lesson:** Round-trip equality checks should compare the *original-with-substitutions-applied* against the *bytes-decoded-back*, not against a magic char. Use `if ($text -ne $back) { WARN }`, not `if ($back.Contains('?')) { WARN }`. The bug was harmless (re-audit caught it) but the WARN line undermined trust in the script's other output.

---

## Design Decisions

### 1. ASCII replacement, not UTF-8 BOM
<!-- tags: powershell,encoding,deployment -->

Two valid fixes existed: (a) replace non-ASCII with ASCII equivalents, (b) re-save files as UTF-8 *with* BOM (which PS 5.1 honors). I chose (a) because:

1. **Standalone-paste path is load-bearing.** Pasting a UTF-8-with-BOM file into a remote shell session means the BOM bytes (`0xEF 0xBB 0xBF`) get pasted as the first three characters of the script. Some shells render them as `ï»¿`; some swallow them silently; some break on them. ASCII has no such failure modes.
2. **Diff tools and heredocs.** Many diff tools display BOMs as visible cruft. Bash heredocs preserve BOMs literally. Git treats BOM-vs-no-BOM as a content change. ASCII sidesteps all of this.
3. **The non-ASCII characters were decorative.** Em-dashes in comments, arrows in flow descriptions, box-drawings in `.env.example` separators. None were domain content. The substitution loses zero information.
4. **Future-proofing.** A pure-ASCII repo can be edited by *any* editor on *any* OS without encoding-discipline lectures. A UTF-8-with-BOM repo requires every contributor to have their editor configured correctly.

The downside is aesthetic: `--` is uglier than `—`, `->` is uglier than `→`. For a security tool that runs in operator terminals, that's the right tradeoff.

---

### 2. Fix script lives in `output/`, not in repo root
<!-- tags: testing,git,privacy -->

`_fix_encoding.ps1`, `_audit_encoding.ps1`, `_audit_chars.ps1`, `_audit_chars2.ps1`, `_audit_all_text.ps1`, `_parser_check.ps1` — all six diagnostic scripts went into `output/` (gitignored), same convention as Phase 8's tier scripts. The fix has been *applied* (the source files in the repo root are clean); the *script that applied it* doesn't need to ship. If the bug recurs in Phase 2, re-derive the script — that's cheaper than carrying maintenance burden on a one-shot tool.

Phase 8 design rule "test fixtures live in unconditionally-ignored dirs" generalizes: *one-shot diagnostic scripts* live there too. Scripts that earn ongoing use graduate to `tools/` or similar.

---

### 3. Did not bump version or modify README
<!-- tags: docs,planning,scoping -->

Considered editing `README.md` to mention the encoding fix in a Troubleshooting entry ("Phase 1.1 — encoding fix for PS 5.1 — `git pull`"). Decided against:

1. Phase 9's CF-20 already flagged that bug-specific troubleshooting entries have a half-life and accumulate. Adding another now contradicts the spirit of that CF.
2. The fix is a hot-fix on top of the Phase 1 commit, not a Phase 1.5 or 1.1 release. There's no version to bump.
3. Operators on the next clone get the fix automatically; operators on a stale clone get a clear parser error pointing at the problem file.

If we accumulate three or more hot-fixes before Phase 2 ships, the right move is a CHANGELOG.md, not Troubleshooting-table accretion.

---

## Carry-Forwards (new)

| ID | Title | Surface | Action |
|----|-------|---------|--------|
| CF-25 | No verification tier covers Windows PowerShell 5.1 | Verification plan in `lessons_learned/phase08_verification_tiers.md` + README Verification section | Add **Tier 5b**: re-run Tier 5 (standalone-paste) using `powershell.exe -NoProfile -File ...` instead of `pwsh.exe`. Required before Phase 2 ships any new module. |
| CF-26 | Tier 1 dry-run on dev box now reports MEDIUM=53 — far above the >10% fire-rate ceiling (phase06#3) | `Invoke-BotnetTriage` heuristics + `config/triage-weights.json` thresholds | Investigate whether the dev box has acquired noise (new dev tools, services) since Phase 8 ship, or whether a heuristic regressed. Run on the clean VM to get a baseline number; compare. |
| CF-27 | No pre-commit / CI guard against re-introducing non-ASCII content into shipping `.ps1` files | Repo root | Add `output/_audit_all_text.ps1`-equivalent to a pre-commit hook (when CI is set up in Phase 2/3). Until then, run the audit manually before any commit that touches `Deploy.ps1`, `_Shared.ps1`, or module files. |

---

## Permissions Gap Report

**None requested at start. None needed.** Read+Write to existing tracked files (`Deploy.ps1`, `modules/*.ps1`, `config/triage-weights.json`, `iocs/iocs_template.txt`, `.env.example`) + Write to `output/_*.ps1` diagnostic scripts (gitignored) + Write to `lessons_learned/phase11_ps51_encoding_fix.md` + Edit to `lessons_learned/INDEX.md`. No new permissions surfaced.

---

## Summary

| Metric | Value |
|--------|-------|
| Files containing non-ASCII bytes (before) | 6 (3 .ps1 + 1 .json + 1 .txt + 1 .example) |
| Total non-ASCII bytes (before) | 388 (213 in .ps1 files + 3 in .json + 27 in .txt + 145 in .example) |
| Distinct codepoints found | 4 (U+2014, U+2190, U+2192, U+2500) |
| Files containing non-ASCII bytes (after) | 0 |
| Replacements applied | 155 chars across 6 files |
| Parser-check post-fix | PASS (3/3 .ps1 files) |
| JSON parse-check post-fix | PASS (3/3 config files) |
| Tier 1 dry-run post-fix | PASS (rc=0, 18 units, total duration 11.22s) |
| Diagnostic scripts written | 6 (in `output/`, gitignored) |
| New CFs | 3 (CF-25, CF-26, CF-27) |
| Bug class previously uncovered by any tier | "Windows PowerShell 5.1 + UTF-8-without-BOM" → CF-25 owns it now |

---
