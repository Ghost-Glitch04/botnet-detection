---
name: phase04_iocs_template
description: Populated iocs/ with the canonical IOC file template and an operator-facing README
type: reflection
---

# phase04_iocs_template — IOC Template + README

> **Scope:** Write `iocs/iocs_template.txt` (format-documented blank) and `iocs/README.md` (operator guidance for IOC staging, distribution, and cross-reference semantics).
> **Date:** 2026-04-09

---

## Applied Lessons

| Rule (file → heading) | Outcome | Note |
|------------------------|---------|------|
| phase03_config_files.md#3 — "Already done" prior files need re-verification | **Applied and resolved** | Before writing `iocs/README.md`, I re-read the committed `.gitignore` to verify that `!iocs/README.md` existed. It did (line 79). The phase03 pitfall triggered the check, the check passed, and CF-3 from phase03 is now closed — the `.gitignore` is already complete beyond what PHASE1_PLAN.md's "final" block specified. |
| phase01_doc_realignment.md#2 — Grep for stale identifiers after edits | Applied | Used `Grep` on `iocs_template\|IOC.*format\|iocs/README` across all `.md` before writing, to surface every place the planning docs already constrained this step. That's what uncovered the PHASE1_PLAN.md `.gitignore` block that doesn't list `iocs/README.md`. |
| phase03_config_files.md#2 — Reconcile planning doc divergence | Applied | REPO_PLAN.md (`iocs/*.txt` block-only) and PHASE1_PLAN.md (`iocs/*` block-all + allowlist) disagreed on the `.gitignore` iocs rules. Resolved by checking what was *actually* in the committed `.gitignore` rather than picking between the two planning docs. Ground truth beats both plans when they conflict. |

---

## What Went Well

### 1. Ground truth beat both planning docs when they disagreed
<!-- tags: process,docs,verification -->

REPO_PLAN.md and PHASE1_PLAN.md gave different `.gitignore` patterns for `iocs/`:

- REPO_PLAN.md: `iocs/*.txt` + `!iocs/iocs_template.txt` (blocks `.txt` files specifically)
- PHASE1_PLAN.md: `iocs/*` + allowlist for `.gitkeep` and `iocs_template.txt` only (blocks everything, missing `iocs/README.md`)

Neither plan was obviously right — PHASE1_PLAN.md was stricter (safer) but missed `README.md`; REPO_PLAN.md was narrower (would let README through) but also let through any non-`.txt` engagement file (e.g. `.csv` IOC dumps). Instead of choosing between the two plans, I read the actual committed `.gitignore` — which turned out to be *more complete than either plan*, containing `iocs/*` + allowlists for all three intended files. The committed file is the ground truth.

**Lesson:** When two planning docs disagree about a file's contents, don't pick between them — go read the file. Planning docs describe intent; the committed file describes reality. Where they diverge, reality wins for the current step.

---

### 2. Documenting what the IOC file *means* semantically, not just its format
<!-- tags: docs,ioc,design -->

The easy write for `iocs_template.txt` would have been a 10-line file with just the comment prefix convention and a few example IPs. I went longer (~50 lines) to document two things that weren't obvious from format alone:

1. **Which data sources each indicator type is cross-referenced against** — e.g. "IPs → TCP connection remotes + DNS cache; Domains → DNS cache + hosts file; URLs → task/service command lines."
2. **The semantic weight of a match** — "IOC match is a score *multiplier*, not a standalone finding. The module flags suspicious state regardless; IOCs amplify."

An operator who knows only the format but not the semantics will misuse the tool — they'll assume that "no IOC matches" = "clean host", when in reality the triage module finds things without any IOC list at all. Baking the semantics into the template file itself means every new engagement IOC file starts from a document that explains what the file is *for*.

**Lesson:** When writing a template file, document the semantics of how the file is consumed, not just its syntax. Format docs prevent typos; semantic docs prevent misuse.

---

## Bugs and Pitfalls

### 3. PHASE1_PLAN.md's `.gitignore` block is missing `!iocs/README.md`
<!-- tags: docs,git,planning -->

PHASE1_PLAN.md's `### .gitignore (final)` block doesn't list `!iocs/README.md` in the iocs allowlist, even though the same plan's deliverables table (row 6) clearly intends `iocs/README.md` to exist. This is a latent doc bug — if an operator ever regenerated `.gitignore` from the plan's "final" block, they'd lose `!iocs/README.md` and silently ignore a file that should be tracked.

The committed `.gitignore` is already correct, so nothing broke today. But if I had naively trusted PHASE1_PLAN.md and written a new `.gitignore` from it, I would have introduced the bug. Cost: a doc fix to PHASE1_PLAN.md in Step 11 or later, to add `!iocs/README.md` to that block.

Filing as CF-5.

**Lesson:** A "final" labeled block in a planning doc can still be incomplete. Diff the labeled block against the actual committed file before trusting either — divergence usually means the committed file evolved after the plan was written, and the plan should be patched to match.

---

## Design Decisions

### 4. README.md over CHEATSHEET.md for IOC operator guidance
<!-- tags: docs,planning -->

REPO_PLAN.md's Phase 6 mentions `docs/CHEATSHEET.md` which will have an "IOC file format reminder" section. That raises an obvious question: why does `iocs/README.md` exist at all if the cheatsheet will cover IOC format?

Rationale for shipping both:

- `iocs/README.md` is *in-place documentation* — an operator who `cd`s into `iocs/` or uses `ls iocs/` sees it without having to know that `docs/CHEATSHEET.md` exists. It's discovery-friendly.
- `docs/CHEATSHEET.md` is a *one-page field reference* — it covers all 5 modules and all workflows, with IOC format as one section among many.
- The two have different audiences at different moments. README = "I'm about to populate this folder, what do I do?" Cheatsheet = "I'm in the middle of an engagement, I need a quick reminder."

Sync obligation: the two documents must agree on IOC format. I'll route this to Step 10's lessons-learned finalization as a cross-doc consistency check, and to Step 6 of Phase 6 (cheatsheet creation) as a reference: copy the format table from `iocs/README.md`, don't re-derive it.

**Lesson:** Co-located documentation (`iocs/README.md`) and centralized documentation (`docs/CHEATSHEET.md`) serve different access patterns and both can exist — but only if you name a single source of truth for any shared content and treat the other as a derived copy.

---

## Carry-Forward Items

- **CF-3 (from phase03)** — **CLOSED.** Committed `.gitignore` was verified and is more complete than PHASE1_PLAN.md's "final" block.
- **CF-4 (from phase03)** — still open: REPO_PLAN.md `exclusions.json` schema divergence. Not relevant to this step.
- **CF-5 (NEW):** PHASE1_PLAN.md `.gitignore (final)` block is missing `!iocs/README.md`. Patch in Step 11 (or earlier if touching PHASE1_PLAN.md for any other reason). Low priority — committed `.gitignore` is already correct.
- **CF-6 (NEW):** `iocs/README.md` and `docs/CHEATSHEET.md` (Phase 6 deliverable) both cover IOC format. When the cheatsheet is written, declare `iocs/README.md` as the source of truth and treat the cheatsheet section as a derived copy. Add to Step 10's cross-doc consistency check.

---

## Metrics

| Metric | Value |
|--------|-------|
| Files created | 3 (`iocs/iocs_template.txt`, `iocs/README.md`, this reflection) |
| Files modified | 0 |
| Planning doc divergences found | 2 (`.gitignore` iocs rules differ; PHASE1_PLAN.md missing `!iocs/README.md` allowlist) |
| Planning doc divergences resolved by ground truth | 1 (committed `.gitignore` trumped both plans) |
| Prior-phase rules applied | 3 (phase01 #2, phase03 #2, phase03 #3) |
| Prior-phase carry-forwards closed | 1 (CF-3 from phase03) |
| Phase outcome | iocs/ has canonical format template + operator README; `.gitignore` verified to protect engagement IOC files while allowing template + README + .gitkeep |
