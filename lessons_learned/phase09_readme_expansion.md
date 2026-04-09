---
name: phase09_readme_expansion
description: Expanded README.md from 2-line stub to a 275-line operator-facing quick-start, parameter reference, output schema, troubleshooting table, and link map. Validated all internal links resolve before commit.
type: reflection
---

# phase09_readme_expansion — `README.md` Expansion

> **Scope:** Replace the 2-line README stub with a complete operator-facing document: quick start (3 deployment paths), requirements, module table, parameter reference, output schema, configuration table, verification status, repo layout, troubleshooting, and project-document link map.
> **Date:** 2026-04-09

---

## Applied Lessons

| Rule (file → heading) | Outcome | Note |
|------------------------|---------|------|
| phase01_doc_realignment.md#2 — verify after rename/architecture swap | **Applied** | Wrote a one-liner that extracts every internal link and `Test-Path`-es it. All 16 resolved on first run. Caught 0 bugs but excluded a class. |
| phase04_iocs_template.md#1 — read both planning docs and reconcile | Applied | The module table is sourced from REPO_PLAN.md and PHASE1_PLAN.md. Where they disagreed (`scoring-weights.json` in REPO_PLAN.md vs only `triage-weights.json` in PHASE1_PLAN.md for Phase 1), README sided with PHASE1_PLAN.md (the tactical doc that drove the actual build). |
| phase04_iocs_template.md#4 — name a single source of truth for shared content | **Applied** | README is the operator's entry point and references the three deeper docs (REPO_PLAN, PHASE1_PLAN, lessons_learned/) for canonical source — README does not duplicate their content beyond what the operator needs at first contact. |
| phase06_invoke_triage_build.md#1 — bracket smoke tests with START/END trailers | N/A | No code in this phase. |
| phase08_verification_tiers.md#1 — multi-tier verification | N/A | No code in this phase. The "link resolution" check is the documentation analog: a single sweep that excludes a single bug class. |

---

## What Went Well

### 1. Internal-link sweep at write-time, not publish-time
<!-- tags: docs,verification,powershell -->

Wrote a one-line PowerShell pipeline (`Select-String -Pattern '\]\(([^)]+)\)' -AllMatches`) that extracts every markdown link, filters to internal paths (rejecting `http*` and `#anchor` links), and `Test-Path`-es each one. Ran it immediately after `Write` finished. Result: 16/16 links resolved. The check took <1s and runs against the exact filesystem state the README will be committed with — catching a dead link here is free, catching it from a contributor's bug report is expensive.

**Lesson:** Markdown link-checking belongs in the same step as writing the file, same as parser validation belongs in the same step as writing a script (phase05_shared_helpers.md#1). The cheapest moment to catch a dead link is right after typing it.

---

### 2. Module table reflects real status, not aspirational status
<!-- tags: docs,planning,scoping -->

The README's module table shows **1 module shipped, 4 modules planned**. It would have been tempting to write the table as if the architecture were complete and qualify it elsewhere — that pattern oversells the project at the most public-facing surface, and any operator who reads it will then be surprised by `command not found` for `Invoke-C2BeaconHunt`. Instead the table column is `Phase` with explicit values: `1 — Shipped`, `2 — Planned`, etc. The asymmetry is the point.

**Lesson:** A README's module/feature table should distinguish *shipped* from *planned* in the same column, not in a separate "status" line that readers may skim past. If a module isn't callable, label it as such where the operator reads its name.

---

### 3. Three quick-start paths instead of one canonical path
<!-- tags: docs,deployment,operator-experience -->

The deployment reality has three distinct paths: `git clone` (ideal), `git clone` + IOC file (engagement use), and standalone-paste (when `git clone` is blocked). Earlier drafts tried to collapse these into one canonical path with sidebars for the alternatives — operators would have had to read the whole section to find theirs. Final version splits them as **Path A / Path B / Path C** with the actual paste-able commands at the top of each block. An operator scanning the README on a phone screen at 3am can find their path in <10 seconds.

**Lesson:** When multiple deployment paths exist and they're meaningfully different, document them as parallel siblings, not as a primary + footnotes. The operator's time-to-first-command is the metric, not the document's tidiness.

---

## Pitfalls

### 1. Troubleshooting table contains "Phase 8 fixes" entries
<!-- tags: docs,planning,ephemeral-context -->

The Troubleshooting table includes three entries pointing to specific bugs that were fixed during Phase 8 verification (e.g. "Pre-Phase-8 build with the StrictMode CIM-polymorphism bug — `git pull`"). These are useful **right now** because anyone with a stale checkout will hit exactly those errors with exactly those messages. They will become **stale** as the bugs age out of memory and "Phase 8" stops being a meaningful reference point.

I kept them because the immediate value (operator with stale checkout instantly diagnoses) outweighs the future cost (a refresh pass). But there's no automated mechanism to prune them — and a README without such pruning will accumulate ephemeral context until it's hard to read.

**Lesson:** Bug-specific troubleshooting entries in a README have a half-life. Either:
1. Keep them and schedule a periodic prune (no mechanism today),
2. Move them to a `CHANGELOG.md` keyed by version, or
3. Delete them at the next minor-version cut.

CF-20 tracks this.

---

### 2. README links to specific lessons-learned phase files
<!-- tags: docs,planning,coupling -->

Three of the README's project-document links point to specific `lessons_learned/phaseNN_*.md` files. The lessons-learned graduation pass scheduled for Step 10 may reorganize, rename, or graduate those files into other locations — at which point the README links will break and the link-resolution check will catch it.

This is acceptable coupling for a Phase-1 project (pre-graduation) but it's a constraint on Step 10: any reorganization needs to either preserve the linked filenames or update README in lockstep. Caught early because I named the dependency.

**Lesson:** When a public-facing doc links to internal artifacts that are scheduled to be reorganized, the upcoming reorganization owns the rename — not the public doc. Capture the dependency in a CF before the reorg starts, not during.

CF-21 tracks this.

---

## Design Decisions

### 1. README references `lessons_learned/` from a public-facing doc
<!-- tags: docs,transparency,planning -->

Most projects bury their build process and post-mortems below the fold or in a private wiki. This README links to phase06/07/08 reflections directly from the public surface — the project wears its build process as documentation. The intent is both transparency (operators know how the toolkit was built and verified, not just what it does) and a forcing function (knowing the lessons files are reachable from README discourages writing them as throwaway notes). Tradeoff: increases the surface area that has to stay coherent across reorgs (see Pitfall #2).

---

### 2. Quick-start Path C describes "paste" rather than `iwr | iex`
<!-- tags: docs,security,deployment -->

The standalone-paste path is documented as "paste the entire content of `modules/Invoke-BotnetTriage.ps1`". A more elegant alternative would be `Invoke-WebRequest <raw-github-url> | Invoke-Expression`. I chose paste because:
1. The tool is intended for environments where outbound HTTPS may be **filtered or monitored**, and `iwr | iex` from a security tool to a GitHub raw URL looks identical to a malicious dropper in any half-decent EDR alert.
2. Pasting requires the operator to have already authenticated to GitHub through a browser to grab the file, so there's an explicit human gate.
3. `iwr | iex` would also bypass any pinned-commit validation; pasting forces the operator to look at the version they're running.

Future README revisions may add `iwr | iex` as an *additional* path with explicit warnings, but it should never be the only documented path.

CF-22 tracks the question of whether to add it at all.

---

### 3. Output schema documented inline in README, not in a separate `MODULE_REFERENCE.md`
<!-- tags: docs,planning,scoping -->

REPO_PLAN.md anticipates a `docs/MODULE_REFERENCE.md` for detailed parameter docs and output schema. For Phase 1 (one shipped module), splitting the schema across two files would be premature — operators would have to follow a link to understand what the JSON contains. The README inlines the top-level schema sketch and the parameter table directly. When Phase 2 ships and `Invoke-C2BeaconHunt` adds another module's worth of schema, the inline section will be the trigger to extract `MODULE_REFERENCE.md`.

**Lesson:** Don't pre-extract reference documentation until it has at least two consumers. One module's reference belongs in the README. Two or more modules earn their own file.

---

## Carry-Forwards (new)

| ID | Title | Surface | Action |
|----|-------|---------|--------|
| CF-20 | Troubleshooting table has bug-specific entries with implicit half-life | `README.md` Troubleshooting section | At next minor-version bump, move to CHANGELOG.md or prune |
| CF-21 | README links to specific `phaseNN_*.md` files — lessons-learned reorg can break them | `README.md` Project Documents section | Step 10 graduation pass MUST update README links in same commit as any rename |
| CF-22 | Standalone-paste path C documents paste-from-clipboard, not `iwr \| iex` | `README.md` Quick Start | Decide whether to add `iwr \| iex` as an additional path with security warnings, or keep it intentionally absent |

---

## Permissions Gap Report

**None requested at start. None needed.** Read-only against tracked files (`README.md`, `REPO_PLAN.md`, `PHASE1_PLAN.md`, `modules/_Shared.ps1`) + `Write` to `README.md` and the new phase09 reflection + `Edit` to `INDEX.md`. No new permissions surfaced.

---

## Summary

| Metric | Value |
|--------|-------|
| README before | 2 lines |
| README after | 275 lines |
| Internal links validated | 16 / 16 OK |
| Quick-start paths documented | 3 (clone, IOC, standalone-paste) |
| Modules in module table | 5 (1 shipped, 4 planned) |
| Parameters documented | 8 |
| Exit codes documented | 6 |
| Troubleshooting entries | 5 |
| Bugs found in this phase | 0 (pure docs phase) |
| New CFs | 3 (CF-20, CF-21, CF-22) |
