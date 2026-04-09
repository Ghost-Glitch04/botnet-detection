---
name: phase10_lessons_finalize
description: Built six AI subject files (powershell, docs, process, config, testing, heuristics) covering 63 rules from phases 01-09, populated _overview.md with file inventory + three concern maps, deferred Foundation graduation pass to honor CF-21.
type: reflection
---

# phase10_lessons_finalize — `lessons_learned/` Finalization

> **Scope:** Build the AI subject file layer on top of nine phases of accumulated rules. Tally rules per primary tag, create one AI file per topic with ≥3 rules, surface cross-cutting topics as concern maps, populate `_overview.md`, update INDEX.md Quick Reference, verify all internal links resolve, and honor CF-21 (don't break README's links to `phase06/07/08*.md`).
> **Date:** 2026-04-09

---

## Applied Lessons

| Rule (file → heading) | Outcome | Note |
|------------------------|---------|------|
| phase09_readme_expansion.md#1 — link sweep at write-time | **Applied** | Ran the same `Select-String` + `Test-Path` pipeline against all 16 markdown files in `lessons_learned/` after the new files were written. 0 broken across 6 new files + 10 existing. Same pipeline against `README.md` confirmed CF-21 untouched. |
| phase09_readme_expansion.md#2pitfall — public docs that link to scheduled-for-reorg artifacts → CF before reorg | **Applied** | CF-21 was the trigger to *defer* the Foundation graduation pass. README links to `phase06/07/08_*.md` by filename — graduating those out of `lessons_learned/` root would silently break the README. Recorded the deferral in `_overview.md` Graduation Notes. |
| phase04_iocs_template.md#4 — name a single source of truth for shared content | **Applied** | INDEX.md is the grep router for individual rule lookup; `ai/_overview.md` is the route-by-topic entry point; AI subject files are the canonical narrative. Each layer points to the layers below; no duplication of rule text across layers. |
| phase01_doc_realignment.md#3 — keep Applied Lessons table even on bootstrap phases | N/A | Not a bootstrap phase. |

---

## What Went Well

### 1. Tag-frequency tally drives AI subject file creation
<!-- tags: process,lessons-learned,scoping -->

Counted primary (first) tag for each of the 63 Active rules in INDEX.md. Five tags hit the 3-rule threshold for their own AI subject file: `powershell` (23), `docs` (14), `process` (7), `config` (6), `testing` (6). A sixth — `heuristics`/`security`/`architecture` — had 5 rules between them with overlapping subject matter, so they merged into one file (`heuristics.md`). The whole carve-up was driven by counting, not by guessing which topics "felt important" — and the resulting file sizes are roughly proportional to where the project actually accumulated wisdom.

**Lesson:** When organizing accumulated rules into topic files, count the primary tag first. The `≥3 rules earns a file` threshold from the lessons-learned skill is a real cliff — anything below it sits in INDEX only and bubbles up via grep, anything above it earns a file. Don't pre-decide categories.

---

### 2. Honored CF-21 — Foundation graduation pass deferred
<!-- tags: process,lessons-learned,coupling -->

The natural next step after building AI files would be to *graduate* multi-phase rules from `Active` → `Foundation`. CF-21 (recorded in phase09) said README links to `lessons_learned/phase06/07/08*.md` files by exact filename — any rename/move would break the README's link sweep. So I deferred the graduation pass and recorded the deferral in `ai/_overview.md` under "Graduation Notes," listing the five rules that *would* qualify and pointing at the CF that's blocking them.

This is the second time the CF system has caught a coupling issue *before* I made the breaking change, not after. Carry-forwards earn their keep when they prevent rework, not when they document it.

**Lesson:** Carry-forwards exist to be *consulted before action*, not just appended after. The "before recommending from memory" discipline applies to CFs too: re-read open CFs before each phase, not just at retrospective time.

---

### 3. Link sweep proved its value on a 16-file change set
<!-- tags: docs,verification,powershell -->

Reused the phase09 Select-String + Test-Path pipeline against the entire `lessons_learned/` tree. Six new files, ten pre-existing files, 50+ markdown links in total. Zero broken. <2s end-to-end. The "validate at write-time" pattern (now a multi-phase Foundation candidate — phase03/05/09/10) keeps paying for itself.

**Lesson:** When a verification idiom has worked in 3+ phases, *promote it from a per-phase tactical move to a cross-phase reflex*. The cost of running the sweep is fixed; the cost of NOT running it grows with the change set size.

---

## Pitfalls

### 1. Secondary-tag rules invisible at the AI-file layer
<!-- tags: process,lessons-learned,scoping -->

Rule organization is by *primary* tag only. A rule like phase05#1pitfall (`powershell,security,testing,masking` → camelCase boundary detector) lives in `powershell.md` because `powershell` is its primary tag, even though the substantive content is about heuristics. An AI assistant looking for "heuristic detector pitfalls" would search `heuristics.md` first and miss it.

The concern map system partly addresses this — the rule could be cross-listed in a concern map — but I didn't create a concern map for "detector design" because it would only have ~3 rules and most are already in `heuristics.md`. The structural gap remains: secondary-tag rules are findable via INDEX grep but not via topic browsing.

**Lesson:** Tag the primary slot with the topic the rule *teaches*, not the technology it *uses*. A rule about heuristic design that happens to be implemented in PowerShell should tag `heuristics,powershell`, not `powershell,heuristics`. Phase 1 didn't follow this discipline consistently — flag for retroactive re-tag pass at the same time as the Foundation graduation.

---

### 2. AI file rules count primary tag, not actual rule density
<!-- tags: lessons-learned,planning -->

`docs.md` has 17 rules listed in `_overview.md`'s "Rules" column, but several of those entries (e.g. "two planning docs disagree" and "lessons-learned scaffolding") are also referenced by `process.md` and `config.md` as cross-references. The number is overcounted in aggregate — total rule count across all 6 AI files ≈ 67, but Active table only has 63 entries.

This is harmless for routing (an AI loading `docs.md` still gets the right rules), but the count column oversells how many *unique* rules each file owns. Future graduation passes should recount with deduplication.

---

## Design Decisions

### 1. AI files use When/Rule template, not narrative
<!-- tags: lessons-learned,docs -->

Per `lessons-learned_V3_3/reference/templates.md`, each AI rule is structured as **Title / When / Rule** (with optional Symptom, Companions, code block, Source). This is deliberately terse — the AI subject files are reference material an assistant loads on demand, not narrative reflections. Narrative lives in the per-phase files; the AI files are pure rules.

I considered embedding the full phase-file context inline ("here's the bug we hit, here's the fix") but rejected it: the AI file would balloon to 5x its size and the rule itself would get lost in storytelling. The `*Source: phase08...*` line at the bottom of each rule is the bridge — an assistant that needs context can chase the source back to the narrative.

---

### 2. Concern maps live in `_overview.md`, not separate files
<!-- tags: lessons-learned,scoping -->

Three concern maps emerged: `standalone-fallback`, `verify-at-write-time`, `plan-vs-truth reconciliation`. Each spans 3-4 AI files with mutual companions. I considered breaking each into its own file (`concerns/standalone-fallback.md`) but kept them inline in `_overview.md` because:

1. They're routing hints, not standalone references. An AI reading them wants to know *which AI subject file to load next*, not the rules themselves.
2. Inline keeps `_overview.md` as the single entry point — one read gets you the file inventory + the cross-cutting topics + the graduation status.
3. The concern map "rules" column points by prose ("powershell.md (Get-Command guards, ...)") not by markdown link, so renames won't cascade.

If concern maps grow past ~5 entries each, this decision flips and they earn their own files.

---

### 3. Foundation tier remains empty pending CF-21 resolution
<!-- tags: lessons-learned,coupling,planning -->

The skill's graduation rules say Active → Foundation when a rule has been re-applied across ≥2 phases. I identified five graduation candidates and listed them in `_overview.md` Graduation Notes, but did not perform the move because:

1. CF-21 — README links to specific `phase06/07/08*.md` filenames. Foundation graduation typically involves consolidating multi-phase rules into a Foundation-tier representative entry, which can rename or relocate the source files. README links would break.
2. Foundation tier was empty *because Phase 1 is still in progress*. Graduation makes sense at phase boundaries (between Phase 1 and Phase 2), not mid-phase.
3. The graduation candidates are already discoverable via the `*Source:* phase0X#N` lines in the AI files — readers can chase any rule back to its origin without Foundation tier being populated.

Foundation graduation is the natural Phase-1-to-Phase-2 transition activity, not a Phase-1-finalization activity. Recorded as CF-23.

---

## Carry-Forwards (new)

| ID | Title | Surface | Action |
|----|-------|---------|--------|
| CF-23 | Foundation graduation pass deferred — 5 multi-phase rules listed in `ai/_overview.md` Graduation Notes | `lessons_learned/INDEX.md` Foundation table + AI subject files | At Phase 1 → Phase 2 transition, perform graduation. Update README links in lockstep (CF-21). Re-tag rules with topic-primary, technology-secondary tag order (Pitfall #1). |
| CF-24 | Secondary-tag rules invisible to AI-file topic browsing | `lessons_learned/ai/*.md` + INDEX tag column | Re-tag pass: primary tag = topic the rule teaches, not the technology it uses. Bundle with CF-23 graduation. |

---

## Permissions Gap Report

**None requested at start. None needed.** Read-only against existing `lessons_learned/`, `.claude/skills/lessons-learned_V3_3/SKILL.md`, `.claude/skills/lessons-learned_V3_3/reference/templates.md`, `README.md` + `Write` to six new `ai/*.md` files + `Edit` to `INDEX.md` and `ai/_overview.md`. No new permissions surfaced.

---

## Summary

| Metric | Value |
|--------|-------|
| AI subject files created | 6 (powershell, docs, process, config, testing, heuristics) |
| Total Active rules covered | 63 (100% of INDEX Active table) |
| Concern maps created | 3 (standalone-fallback, verify-at-write-time, plan-vs-truth reconciliation) |
| Foundation graduations performed | 0 (5 candidates listed, deferred per CF-21 → CF-23) |
| Markdown files in `lessons_learned/` after this phase | 17 (10 phase + 1 INDEX + 6 ai/) |
| Internal links validated | 50+ across all 17 files; 0 broken |
| `README.md` link integrity post-change | Confirmed (16/16) |
| INDEX.md line count | 111 (under 200 limit) |
| New CFs | 2 (CF-23, CF-24) |
| Bugs found in this phase | 0 (pure docs/organization phase) |

---
