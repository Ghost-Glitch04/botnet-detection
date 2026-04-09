# phase01_doc_realignment — REPO_PLAN + PHASE1_PLAN Re-alignment

> **Scope:** Update `REPO_PLAN.md` and `PHASE1_PLAN.md` to reflect the approved 5-module / triage-first architecture. Swap Phase 1 anchor from `Invoke-C2BeaconHunt` to `Invoke-BotnetTriage`, insert `Invoke-C2BeaconHunt` as new Phase 2, renumber Phases 3–6, add `config/triage-weights.json` schema, update Deploy.ps1 description, rewrite verification plan and scope boundaries for the triage module.
> **Date:** 2026-04-09

---

## Applied Lessons

| Rule (file → heading) | Outcome | Note |
|------------------------|---------|------|
| *(none — bootstrap phase, lessons_learned/ was initialized during this phase)* | — | First phase in the project; INDEX.md was empty at start. Lookup protocol will run starting phase02. |

---

## What Went Well

### 1. Surgical Edit over wholesale Write was the right choice for large docs
<!-- tags: process,docs -->

Both `REPO_PLAN.md` and `PHASE1_PLAN.md` contain substantial content that didn't need to change (e.g. `.env.example` schema, N-Able shell constraints, `.gitignore` block, Shared Helper Strategy table most of it, Deploy.ps1 unit breakdown). Doing targeted `Edit` replacements instead of a full `Write` rewrite preserved formatting, section order, and unchanged content exactly as the prior author left it — no accidental drift, and the diff is scoped to what actually changed. The tradeoff is that I had to do ~14 separate edits instead of one, but each is independently reviewable.

**Lesson:** When re-aligning an existing planning doc to a new architecture, prefer surgical `Edit` over wholesale `Write` — the edit trail is the diff, and sections you didn't need to touch should not show up in the diff at all.

---

### 2. Grepping for stale references after editing caught a Deploy.ps1 scoring-weights line I'd missed
<!-- tags: process,docs,verification -->

After finishing the apparent Phase 1 edits, I ran `Grep` for `Invoke-C2BeaconHunt|scoring-weights|ScoringWeights` across both docs. This surfaced three stragglers in `REPO_PLAN.md` that I'd missed on the first pass: a `Load config/scoring-weights.json` line in a generic Deploy.ps1 behavior block, and two `Invoke-C2BeaconHunt` examples at the bottom in the Deployment Workflow section. Without the grep pass, these would have shipped as silent inconsistencies — readers of the updated doc would see `Invoke-BotnetTriage` as Phase 1 anchor but then find `Invoke-C2BeaconHunt` examples in the "how to deploy" section without explanation.

**Lesson:** After editing a large doc for a global rename or architecture swap, always `Grep` for the old identifiers across the modified files — each stale hit is a bug that will confuse the next reader.

---

### 3. The "Applied Lessons" table format degrades gracefully for bootstrap phases
<!-- tags: process,lessons-learned -->

The lessons-learned skill is designed around a lookup-before-work loop: `grep INDEX.md → apply → reflect → update INDEX.md`. On the very first phase, there is nothing in INDEX.md to look up, so the "Applied Lessons" table has no meaningful content. Rather than omit the table (which would break the format contract with future reflections), leaving it as a single `(none — bootstrap phase)` row preserves the structure and documents *why* it's empty. Phase 02 will be the first real test of the lookup protocol.

**Lesson:** Even on a bootstrap phase, keep the Applied Lessons table header and add a placeholder row explaining why it's empty — do not silently drop sections that the format expects.

---

## Bugs and Pitfalls

### 4. Orphaned generic content when restructuring module-specific sections
<!-- tags: docs,refactoring -->

When I reshaped Phase 1 from `Invoke-C2BeaconHunt` to `Invoke-BotnetTriage` in `REPO_PLAN.md`, the original Phase 1 section contained a generic "Deploy.ps1 behavior" block and a "Standalone fallback pattern" code block that were *not* specific to any module — they described the launcher itself. My first edit rewrote the module-specific parts of Phase 1 but left these generic blocks where they were in the document. After I inserted the new Phase 2 section ahead of them, the generic blocks ended up stranded *inside* the Phase 2 section, where they looked like they were describing `Invoke-C2BeaconHunt`'s Deploy.ps1 interaction specifically.

Symptom: a reader going through Phase 2 would see "Deploy.ps1 behavior" listed under it and assume the behavior was Phase 2–specific, when in reality the launcher ships in Phase 1 and the behavior applies to every phase.

The fix was to move the blocks back under Phase 1 with an explicit label: `**Deploy.ps1 behavior (ships in Phase 1, applies to all phases):**`. The explicit label defends against the same ambiguity recurring if the doc is restructured again.

**Lesson:** When moving module-specific content in a planning doc, check whether nearby blocks are *also* module-specific or *generic infrastructure*. Generic blocks should be moved with the infrastructure they describe (not left where they sit) and should carry an explicit scope label so their placement is unambiguous.

---

### 5. Config file naming collision risk — `triage-weights.json` vs. `scoring-weights.json`
<!-- tags: config,naming -->

The original plan had a single `config/scoring-weights.json` that was tightly coupled to `Invoke-C2BeaconHunt`'s beacon-periodicity engine (fields like `BeaconCoefficientOfVariationThreshold`, `MinSamplesForBeaconDetection`). When Phase 1 shifted to `Invoke-BotnetTriage`, the triage module needed a *different* shape of weights (per-category scores for 8 data sources, no beacon fields). I could have reused `scoring-weights.json` and added triage fields to it, but that would have created a ballooning single config as more modules were added, with unused fields for most callers.

The decision: split into `triage-weights.json` (Phase 1) and `scoring-weights.json` (Phase 2). Each module reads exactly one weights file. The downside is that `Deploy.ps1` now has to load N weight files at launch (currently 1, growing to 2 in Phase 2). The upside is that each config file has a single owner and a stable schema — adding a new module doesn't risk breaking an existing module's weight loading.

**Lesson:** When one config file is being reshaped for a new consumer, prefer splitting it into per-module config files over cramming unrelated fields into one shared file. Config ownership should follow module ownership; shared configs (like `exclusions.json`) are only appropriate when the data is genuinely shared across consumers.

---

## Design Decisions

### 6. Keep Phase 2's scoring-weights.json schema in REPO_PLAN.md (visible now) instead of deferring to Phase 2's plan
<!-- tags: docs,planning -->

`REPO_PLAN.md` is the strategic blueprint that spans all 6 phases, so it makes sense to document `scoring-weights.json` (Phase 2) alongside `triage-weights.json` (Phase 1) even though Phase 2 hasn't been built yet. A future reader opening `REPO_PLAN.md` should see both config schemas on one page.

In contrast, `PHASE1_PLAN.md` is the *tactical* plan for Phase 1 specifically. Keeping `scoring-weights.json` out of its Config Schemas section (with a forward reference to Phase 2's plan) keeps the doc focused — Phase 1 isn't going to implement that config, so it shouldn't clutter the Phase 1 file.

The rule: strategic docs include future-phase content; tactical per-phase docs scope themselves strictly to the phase they plan.

**Lesson:** Strategic vs. tactical planning docs have different scope contracts. A repo blueprint should show everything; a per-phase tactical plan should omit future-phase details and reference them forward.

---

### 7. `.env.example` ships in Phase 1 despite being unused in Phase 1
<!-- tags: config,security,contract -->

`Invoke-BotnetTriage` is explicitly offline-capable and reads no API keys. But `.env.example` is listed as a Phase 1 deliverable anyway. Rationale: the `.env.example` file is a *contract* with operators, not a Phase 1 feature. It tells anyone pulling the repo "these are the API keys this toolkit will use." If `.env.example` only appears at Phase 2 launch, operators have no warning that credentials will be needed later. Shipping it empty-but-present in Phase 1 sets the expectation and lets operators populate `.env` (their gitignored file) ahead of the Phase 2 ship.

The cost is near-zero (a tiny committed file); the benefit is that the credentials contract is visible from day one.

**Lesson:** Committed `.env.example` / config stub files should ship at whatever phase *first creates the expectation of that config*, not the phase that first *reads* it. Shipping the contract early gives operators time to prepare.

---

## Carry-Forward Items

- **CF-1:** `lessons_learned/ai/*.md` subject files (e.g. `process.md`, `docs.md`) have not been created yet. Phase 2 reflection should route the rules from this phase into appropriate AI files (see Step 4 of the Full Reflection workflow in SKILL.md). Leaving this deferred for now because Phase 1 was a single doc-editing phase and the rule count is small enough that routing can happen after Phase 2 to avoid premature categorization.

- **CF-2:** Helper / diagnostic tool for grep-sweeping stale identifiers after large edits. Built nothing yet, but lesson #2 above suggests a reusable `scripts/Find-StaleRefs.ps1` or a one-liner script snippet that takes a list of old → new identifier pairs and reports remaining hits. Revisit in Step 6 (Invoke-BotnetTriage build) where a similar post-edit sweep will be needed across the module file. If needed again, promote to a helper.

- **CF-3:** No AI subject files exist yet. The `_overview.md` has empty tables. Per SKILL.md §4c ("Which AI subject file?"), route by primary technology or concern — but with only 4 rules and zero existing files, the threshold for creating any new AI file is 3+ rules on a shared topic. Current rules have tags `process, docs, refactoring, config, security, naming, planning, contract, lessons-learned, verification` — no cluster of 3+ yet in a single coherent topic. Defer AI file creation until Step 10 (Finalize lessons_learned) when more rules have accumulated.

---

## Metrics

| Metric | Value |
|--------|-------|
| Files modified | 2 (`REPO_PLAN.md`, `PHASE1_PLAN.md`) |
| Files created | 3 (`lessons_learned/INDEX.md`, `lessons_learned/ai/_overview.md`, this file) |
| Edit operations | 14 (targeted `Edit` calls) |
| Grep verification passes | 2 (caught 3 stragglers in `REPO_PLAN.md`) |
| Stale references found post-edit | 3 (all fixed) |
| Architectural decisions documented | 2 (config file split, `.env.example` ship timing) |
| Phase outcome | Docs aligned with approved 5-module / triage-first architecture; no stale `Invoke-C2BeaconHunt`-as-Phase-1 references remain |
