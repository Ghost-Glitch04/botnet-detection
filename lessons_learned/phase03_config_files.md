---
name: phase03_config_files
description: Created the four Phase 1 config files (.env.example, config.example.json, exclusions.json, triage-weights.json)
type: reflection
---

# phase03_config_files — Config File Creation

> **Scope:** Create the committed config files Phase 1 needs — `.env.example` (Phase 2 credentials contract), `config/config.example.json` (global ops defaults), `config/exclusions.json` (known-good filters), `config/triage-weights.json` (Invoke-BotnetTriage scoring weights).
> **Date:** 2026-04-09

---

## Applied Lessons

| Rule (file → heading) | Outcome | Note |
|------------------------|---------|------|
| phase01_doc_realignment.md#7 — `.env.example` ships at the phase that *creates the expectation* | Applied | Shipped empty-but-present Phase 2 keys in `.env.example` even though Phase 1 reads none of them. Operators pulling the repo today see the credentials contract before Phase 2 lands. |
| phase01_doc_realignment.md#5 — config ownership follows module ownership | Applied | Created `triage-weights.json` as a separate file from the (not-yet-existing) `scoring-weights.json`. Triage module gets one weights file, beacon module will get another. No shared risk-weights file. |
| phase01_doc_realignment.md#6 — strategic vs. tactical docs | Applied (inversely) | When the `exclusions.json` schema diverged between REPO_PLAN.md (5 top-level fields) and PHASE1_PLAN.md (8 top-level fields with `LocalOnlyPorts`, `TrustedSigners`, `BeaconWhitelist` additions), I used PHASE1_PLAN.md as the tactical authority rather than the strategic blueprint. The principle from lesson #6 cuts both ways: implementation follows the tactical doc, not the strategic one. |

---

## What Went Well

### 1. JSON validation via `python -m json.tool` (inline) caught zero bugs — and that's the point
<!-- tags: process,config,verification -->

After writing the 3 JSON files by hand, I ran a Bash one-liner that walked all three through `json.load()`. All three parsed cleanly, but the *value* of the check isn't "finds bugs" — it's that a typo in a JSON file would otherwise surface 4 build steps later when `Deploy.ps1` tries to `ConvertFrom-Json` the file at load time, producing a cryptic launcher failure instead of an immediate "missing comma on line 14" error. Catching JSON validity at write-time is an order of magnitude cheaper than catching it at load-time.

**Lesson:** Any time you write a JSON/YAML/TOML file by hand, validate its syntax in the same step you write it. The cheapest moment to catch a syntax bug is right after you typed it — not when a downstream consumer fails to parse it.

---

### 2. Canonical schema cross-check between REPO_PLAN.md and PHASE1_PLAN.md surfaced a divergence
<!-- tags: config,docs,verification -->

REPO_PLAN.md's `exclusions.json` block had 5 top-level fields (`Description`, `Processes`, `Ports`, `PrivateSubnets`); PHASE1_PLAN.md's version had 8 (adding `LocalOnlyPorts`, `TrustedSigners`, `BeaconWhitelist`). PHASE1_PLAN.md's section was explicitly labeled `### config/exclusions.json (extensions beyond REPO_PLAN.md)`, which resolved the ambiguity — the tactical doc is the superset and the authority during implementation. Without the pre-write Grep/Read of both files, I might have shipped the smaller REPO_PLAN.md version and lost the `TrustedSigners` field that Phase 1's `Services.Unsigned` scoring rule is going to need.

**Lesson:** When two planning docs describe "the same" config file, always read both and look for divergence. Label the winner by its role (tactical > strategic for implementation; strategic > tactical for future-phase context). If the divergence is silent, file a doc-alignment task.

---

## Bugs and Pitfalls

### 3. The existing `.gitignore` was assumed correct but never verified against PHASE1_PLAN.md's "final" block
<!-- tags: config,git,verification -->

PHASE1_PLAN.md contains a `### .gitignore (final)` block with expected contents (`.env`, `.env.*`, `!.env.example`, `config/config.local.json`, `output/*`, `!output/.gitkeep`, `*.log`, etc.). The plan says `.gitignore` is "already done", but I never actually diffed the committed `.gitignore` against that block during this step. If the committed file is missing (for example) `!.env.example`, then the `.env.example` file I just wrote would be silently ignored and would never get committed.

This is a latent bug — not a bug I introduced, but one I failed to catch. Deferred to Step 11 (git hygiene check before commit), where a `git status --ignored --untracked-files=all` will surface it.

**Lesson:** When a prior-phase file is labeled "already done", don't trust the label. If the current step depends on a specific property of that file (here: `.gitignore` must un-ignore `.env.example`), actually verify the property before moving on. "Already done" is not the same as "still correct".

---

## Design Decisions

### 4. Adding explicit `Description` field to every JSON config
<!-- tags: config,docs -->

Each JSON config I wrote has a top-level `Description` string explaining its purpose. The alternative would have been a sidecar comment at the top of the file — but JSON doesn't support comments, and a sidecar `.md` creates two-file sync risk. Putting the description inside the JSON itself means it travels with the file into any tool that reads it (jq queries, PowerShell `ConvertFrom-Json`, etc.) and is immediately visible when an operator `cat`s the file.

The cost is a harmless extra field that consumers ignore. The benefit is that the file is self-documenting at read time.

**Lesson:** Prefer an in-file `Description` / `_comment` field over external documentation for config files, especially when the format (JSON) doesn't support comments. The field is cheap, the file stays self-explanatory, and it survives tool transformations.

---

### 5. Using PHASE1_PLAN.md's superset `exclusions.json` instead of REPO_PLAN.md's minimal version
<!-- tags: config,docs,planning -->

See "What Went Well #2" above for the mechanism. The rule: when the tactical plan explicitly extends a strategic schema ("extensions beyond REPO_PLAN.md"), the tactical version is authoritative for the phase it targets. The strategic doc can lag — and should be updated to match in a future doc-alignment pass, or the divergence should be documented as intentional (e.g., Phase 2 uses REPO_PLAN.md's minimal view).

Action: consider a small REPO_PLAN.md edit in Step 11 to match `exclusions.json` schemas, or explicitly label the REPO_PLAN.md version as "minimal baseline — see PHASE1_PLAN.md for Phase 1 superset".

**Lesson:** Tactical-extends-strategic is a legitimate pattern but creates a sync obligation. Either keep them in lockstep or explicitly label the divergence; silent divergence will confuse future readers.

---

## Carry-Forward Items

- **CF-1 (phase01)** — still deferred. AI subject file creation still waiting for 3+ rule clusters (Step 10).
- **CF-2 (phase01)** — still open. No stale-ref sweep needed this step.
- **CF-3 (NEW):** `.gitignore` contents must be verified against PHASE1_PLAN.md's "final" block before Step 11 commit. If `!.env.example` or `!output/.gitkeep` are missing, the committed-but-ignored trap will hide files from git. Deferred to Step 11 git hygiene pass, but noted here so it isn't forgotten.
- **CF-4 (NEW):** REPO_PLAN.md's `exclusions.json` schema is a strict subset of PHASE1_PLAN.md's. Either reconcile them in Step 11 or explicitly mark the divergence. Low priority (doesn't block Phase 1 build) but cosmetic drift in planning docs.

---

## Metrics

| Metric | Value |
|--------|-------|
| Files created | 5 (4 configs + this reflection) |
| Files modified | 0 |
| JSON validation passes | 1 (all 3 files valid on first try) |
| Schema divergences between planning docs | 1 (`exclusions.json` — PHASE1_PLAN.md superset) |
| Lessons from prior phases applied | 3 (phase01 #5, #6, #7) |
| Phase outcome | 4 config files committed to disk; JSON parses clean; Phase 1 contract for credentials, ops defaults, exclusions, and triage scoring all declared |
