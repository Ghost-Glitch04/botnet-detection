---
name: phase15_cf35_premise_audit
description: CF-35 deliverable — full audit of every open carry-forward. Adds an explicit premise to each deferral, closes CFs that were already acted on, defines ghost CFs (CF-32/CF-33 had no committed definition), and establishes the canonical open-CF registry going into Phase 1.3.
type: reflection
---

# phase15_cf35_premise_audit — Carry-Forward Premise Audit

> **Scope:** Execute CF-35 ("audit existing carry-forwards for unstated premises"). Walk every CF from CF-16 through CF-38. For each: (a) confirm open/closed status, (b) state the explicit premise that justifies the deferral, (c) flag ghost CFs that have no committed definition, (d) close CFs that have been acted on. Output: canonical open-CF registry for Phase 1.3.
> **Date:** 2026-04-10
> **Triggered by:** CF-35 (created phase13 after CF-31 premise collapse taught the lesson).

---

## What "Premise" Means

A deferral premise is the *load-bearing assumption* that justifies not doing the work now. If the premise falls, the deferral falls with it. Format: **"Deferred because X. Premise collapses if Y."**

CF-31 was the canonical failure: "Phase 2 because requires offline DB." Premise: needs DB. When a peer script showed no DB was needed, the premise collapsed and the deferral collapsed with it — immediately, not at the next review cycle. That's what explicit premises enable.

---

## Audit Results

### Closed — acted on, no further action needed

| CF | Title | Closed by | Note |
|----|-------|-----------|------|
| CF-26 | Dev-box noise (MEDIUM=53) | phase12 | Answered with data: clean VM = 28 findings, dev box = 79. Noise is dev-tool state, not heuristic regression. |
| CF-29 | ListeningPorts >10% fire rate | phase12 / Phase 1.2 | HighPortNonServerProcess → HighPortAllInterfaces rename + tighten. Verified 0% on V3. |
| CF-36 | Tier 6 non-elevated baseline | phase14 + A2 | Tier 6 added to phase08. A2 ran non-elevated and passed. |
| CF-37 | Dead-config audit rule | phase14 | Rule added to ai/config.md. |
| CF-38 | Diagnostic-only flag pattern | phase14 | Heuristics.md dead-flag rule refined (absent vs weight=0). |

---

### Ghost CFs — referenced but never defined in any committed file

**CF-32** — no definition found in any lessons_learned file or planning doc. Referenced only as "CF-32, CF-33, CF-34, CF-35: unchanged (Phase 1.3 work)" in phase14.

**Disposition:** CF-32 is declared **undefined / never formally captured**. It is being retired. If there was an intent, it has not been preserved in any auditable form. If it resurfaces as a real need, it will be issued a new CF number with a proper definition.

---

**CF-33** — referenced in planning context as "embedded-Chromium browser filter" but never formally defined in any phase file. The description from conversation: *msedgewebview2.exe should be recognized as an embedded browser process and suppressed from `PrivateToPublicNonBrowser` the same way chrome.exe/msedge.exe are.*

**Disposition:** CF-33 is **now formally defined** (see below in "Open" table).

---

### Open — deferral confirmed with explicit premise

| CF | Title | Premise | Collapses if | Phase |
|----|-------|---------|--------------|-------|
| CF-16 | IOC-only Risk floor lands in Low (score 20 < Medium threshold 25) | Tuning the IOC floor requires a dedicated scoring-review pass — changing any threshold in isolation risks cascading through all other threshold math. Must be done as a batch with CF-19 and any other scoring changes. Premise: threshold math is coupled; changes are batch-only. | Scoring system is refactored to have an isolated `IOCMatch → min-Medium` override path. | Tuning pass |
| CF-17 | No AST-based audit for inline-fallback completeness | Building a static checker is a separate tool that belongs in a "toolkit hygiene" sub-phase, not inside an implementation phase. Premise: tool-building cost doesn't belong inside feature-delivery context. | Inline stubs are removed from the standalone-paste architecture (making the check moot), or the toolkit gains a CI pipeline that can host it cheaply. | Phase 9 / CI |
| CF-18 | U-CorrelateIOCs doesn't iterate ListeningPorts | Design decision (IOCs are usually remote-side, not local-port-side) that needs a 2-line unit-header comment, not a code change. Deferring until any Phase 1.3 edit touches U-CorrelateIOCs — comment belongs in the same diff as any related change. Premise: doc-only change belongs in the diff where the surrounding code is being read. | An IOC file is provided that targets local listening ports (e.g., a known backdoor port), making the gap a real miss rather than a design choice. |Phase 1.3 |
| CF-19 | Top-5 summary doesn't surface IOC-only hits | The current top-5 sorts strictly by score. An IOC-only hit at score=20 is genuinely below threshold noise — displaying it in top-5 requires a UI decision (separate "IOC matches" section, or score-floor override). Premise: UI format decision requires deliberate operator-UX thought, not a quick edit; wrong call erodes summary trust. | Operator explicitly requests IOC hits always surface in summary regardless of score. | UX pass |
| CF-20 | Troubleshooting table has bug-specific entries with implicit half-life | Pruning doc is maintenance, not feature work. Premise: scheduled for next minor-version bump when CHANGELOG is being written anyway — same diff, zero extra cost. | README troubleshooting grows to >20 entries and becomes actively misleading. | Next version bump |
| CF-21 | README links to phaseNN files by exact filename | Graduation would rename files; README links would silently break unless updated atomically. Premise: graduation pass and README update must be a single commit — doing graduation first and README second creates a window where README is broken. | All README links to lessons_learned use a stable anchor (directory + section heading) rather than exact filenames. | Phase 1→2 transition |
| CF-22 | Standalone-paste path documents paste, not `iwr \| iex` | `iwr \| iex` from a public GitHub URL is visually identical to a malicious dropper from an attacker-controlled host. Adding it requires a deliberate security policy decision, not just a README edit. Premise: wrong security call has reputational/security cost; needs operator intent, not convenience. | Operator explicitly decides to add `iwr \| iex` path with security warning language; then it becomes a doc task. | Operator policy decision |
| CF-23 | Foundation graduation pass deferred | Graduation reorganizes index structure AND requires README link updates (CF-21 dependency) — doing it mid-phase disrupts both the active phase and README consumers. Premise: phase-boundary gated; doing it mid-phase costs more than waiting. | No README links to specific phaseNN filenames (CF-21 resolved). | Phase 1→2 transition |
| CF-24 | Tag re-ordering (topic-primary, technology-secondary) | Bundled with CF-23 — re-tagging hundreds of INDEX rows mid-phase is noise; doing it alongside graduation makes both tasks zero-marginal-cost. Premise: shares the same atomic pass as CF-23. | CF-23 closes. | Phase 1→2 transition |
| CF-25 | PS 5.1 verification tier not codified as a reusable script | PS 5.1 run on clean VM de facto satisfied the intent. The gap is automation: no `output/_tier5b_ps51.ps1` script exists, so the tier isn't repeatable. Premise: scripting the tier is a testing-infrastructure task that belongs in a hygiene pass, not mid-feature implementation. Collapses if a new module ships without a PS 5.1 smoke test having been run. | Any Phase 1.3 module ships without a PS 5.1 manual run (then it becomes blocking). | Hygiene pass / pre-Phase-2 |
| CF-27 | No pre-commit guard against non-ASCII in .ps1 files | Pre-commit hooks require CI infrastructure that doesn't exist yet. Premise: guard needs CI; CI is Phase 2/3. Manual audit (`output/_audit_all_text.ps1`) covers the gap until then. | CI is established (Phase 2/3). | Phase 2/3 CI setup |
| CF-28 | ScheduledTasks LOLBin Microsoft allowlist dominates top-5 | Building the allowlist requires sampling Microsoft-authored task names from a clean baseline to avoid over-suppressing. Deferred to Phase 1.3 collection phase where baseline data is being re-examined anyway. Premise: allowlist needs clean-baseline data as input; doing it without that data risks under-suppressing or over-suppressing. | Phase 1.3 baseline collection pass. **This CF is actively in scope for Phase 1.3.** |
| CF-30 | bash + pwsh -Command rule needs Foundation promotion | Promoting to Foundation tier is part of CF-23's graduation pass — doing it as a standalone index restructure mid-phase has no benefit over waiting. Premise: same atomic pass as CF-23; Foundation table should move in one coherent pass. | CF-23 closes. |
| CF-33 | Embedded-Chromium (msedgewebview2.exe) not classified as browser | `PrivateToPublicNonBrowser` fires on msedgewebview2.exe because the current browser-detection list doesn't include Electron/WebView2 process names. Produces Medium-tier noise on any machine running Teams, VS Code, or other Electron apps. Premise: fixing requires understanding which embedded-browser process names are legitimate (Teams uses msedgewebview2.exe for UI, not for arbitrary browsing) — an allowlist that's too broad suppresses real C2. Need to audit which processes embed WebView2 for UI vs which processes should be flagged for using it. | Phase 1.3 connection enrichment pass. **This CF is actively in scope for Phase 1.3.** |
| CF-34 | `-NoNetworkLookups` kill-switch for ASN enrichment | Required before Phase 1.3 ASN enrichment ships — enrichment DNS lookups from the tool itself are observable footprint on the target endpoint. Operator must control the tradeoff. Premise: ships in the same commit as CF-31 (ASN enrichment). Cannot ship CF-31 without CF-34. | CF-31 ships. **Blocking for Phase 1.3.** |

---

## Open CF Registry — Phase 1.3 View

| Priority | CF | Title | Status |
|----------|----|-------|--------|
| **Phase 1.3 in-scope (active)** | CF-28 | ScheduledTasks LOLBin Microsoft allowlist | Needs clean-baseline author sampling |
| **Phase 1.3 in-scope (active)** | CF-31 | ASN enrichment via Cymru DNS | PoC first (phase15 guideline) |
| **Phase 1.3 in-scope (active)** | CF-33 | Embedded-Chromium browser filter | Needs WebView2 process-name audit |
| **Phase 1.3 blocking** | CF-34 | `-NoNetworkLookups` kill-switch | Ships in same commit as CF-31 |
| **Phase 1.3 trailing** | CF-18 | CorrelateIOCs/ListeningPorts comment | Catch in any U-CorrelateIOCs diff |
| **Tuning pass** | CF-16 | IOC-only score floor | Batch with CF-19 |
| **Tuning pass** | CF-19 | Top-5 summary / IOC-only hits | Batch with CF-16 |
| **Graduation pass** | CF-21 | README link fragility | Gates CF-23 |
| **Graduation pass** | CF-23 | Foundation tier graduation | Phase 1→2 |
| **Graduation pass** | CF-24 | Tag re-ordering | Bundled with CF-23 |
| **Graduation pass** | CF-30 | bash+pwsh rule Foundation | Bundled with CF-23 |
| **Hygiene pass** | CF-17 | Inline-fallback AST checker | Phase 9 / CI |
| **Hygiene pass** | CF-20 | Troubleshooting table half-life | Next version bump |
| **Hygiene pass** | CF-22 | iwr\|iex policy decision | Operator call |
| **Hygiene pass** | CF-25 | PS 5.1 tier script | Pre-Phase-2 |
| **Phase 2/3** | CF-27 | Pre-commit non-ASCII guard | Needs CI |

---

## Key Findings

1. **CF-32 is undefined and retired.** No definition found in any committed file. The number is vacated.

2. **CF-33 is now formally defined.** WebView2/embedded-browser classification — was only a conversation reference, now has a proper definition and premise.

3. **CF-36/37/38 are closed.** Implemented in the Phase 1.2.1 hotfix session (phase14). Were listed as "new" CFs but their actions were completed in the same session.

4. **CF-16 and CF-19 must move together.** Both touch the scoring/summary pipeline; fixing one without the other risks threshold inconsistency. The premise for each references the other.

5. **CF-34 gates CF-31.** ASN enrichment cannot ship without the kill-switch. This is the only hard blocking dependency in the Phase 1.3 CF list.

6. **The graduation cluster (CF-21, CF-23, CF-24, CF-30) forms a single atomic pass.** All four share the same premise: "phase-boundary activity that requires README + index to move atomically." Treat them as one task at Phase 1→2 transition.

---

## Applied Lessons

| Rule | Outcome | Note |
|------|---------|------|
| process.md --- carry-forwards must record their premise | **Executing** | This entire audit is the deliverable of CF-35. Premise explicitly stated for every open CF. |
| process.md --- bug-fix reflections must answer "what would have caught this?" | **Re-applied** | Ghost CFs (CF-32/CF-33) would have been caught by a "every CF must have a committed definition" rule. Added as finding #1/#2. |
| heuristics.md --- allowlist the small finite normal set | **Pre-applied to CF-33** | The embedded-browser filter premise captures why "allowlist by process name" needs care — the list is larger than it first appears (Teams, VS Code, Outlook all embed WebView2). |

---

## Carry-Forwards

- CF-35: **CLOSED** — this file is the deliverable.
- No new CFs generated. (CF-32 retired, CF-33 formally defined above, CF-36/37/38 formally closed.)
