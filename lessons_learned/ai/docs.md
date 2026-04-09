---
name: docs
description: Documentation rules covering planning-doc reconciliation, scoping (strategic vs tactical), verification at write-time, and operator-facing README design.
type: ai-subject
---

# Docs — Subject Rules

Rules for writing planning docs, READMEs, lessons-learned reflections, and templates. Anchor topics: write-time verification (link-check, plan-vs-file diff), strategic-vs-tactical scoping, and operator experience.

---

## Verification at Write-Time

### Markdown link-checking belongs in the same step as writing the file

**When:** Finishing a `Write` to any markdown file with internal links.
**Rule:** Extract `\]\(([^)]+)\)` matches with `Select-String`, filter to non-`http*` non-`#anchor` paths, `Test-Path` each. Run it the moment after `Write` completes. <1s, catches dead links before they ship. Same principle as parser-validation for scripts.

```powershell
Select-String -Path .\README.md -Pattern '\]\(([^)]+)\)' -AllMatches |
  ForEach-Object { $_.Matches.Groups[1].Value } |
  Where-Object { $_ -notmatch '^(http|#)' } |
  ForEach-Object { [PSCustomObject]@{Link=$_; OK=(Test-Path $_)} }
```

*Source: phase09_readme_expansion.md#1*

---

### Surgical Edit beats wholesale Write for re-aligning large planning docs

**When:** Updating an existing planning doc (REPO_PLAN, PHASE_PLAN) where the change is bounded — a section rewrite, a table update, a rename pass.
**Rule:** Use `Edit` (or multiple Edits), not `Write`. Diff scope = edit scope. Preserves untouched content verbatim, makes the review trivial, and avoids accidentally regenerating sections you didn't intend to touch.

*Source: phase01_doc_realignment.md#1*

---

### After global rename or architecture swap, grep modified files for old identifiers

**When:** Just finished a multi-file rename (e.g. `Invoke-C2BeaconHunt` → `Invoke-BotnetTriage`) or an architecture swap.
**Rule:** Run `Grep` over the modified files for the old identifier. Each stale hit is a bug. Cheap, exhaustive, and the only way to catch stragglers in tables, footnotes, and link text.

*Source: phase01_doc_realignment.md#2*

---

### When two planning docs disagree about a file, read the committed file

**When:** Two planning docs (e.g. REPO_PLAN.md and PHASE1_PLAN.md) describe the same file's contents differently.
**Rule:** Read the committed file. Ground truth beats both plans. Then update the wrong plan(s) to match — or label the divergence explicitly if the divergence is intentional (tactical-extends-strategic).

*Source: phase04_iocs_template.md#1*

---

### "Final" labels in planning docs are not load-bearing

**When:** A planning doc has a code block labeled "final," "approved," or "shipping" describing a file's contents.
**Rule:** Diff the labeled block against the committed file before trusting either. The label can be stale; the file is canonical. The label is a hint, not a guarantee.

*Source: phase04_iocs_template.md#3*

---

## Scoping — Strategic vs Tactical

### Strategic docs include future phases; tactical docs scope strictly to one phase

**When:** Deciding whether a planning artifact belongs in `REPO_PLAN.md` (strategic, multi-phase architecture) or `PHASE_N_PLAN.md` (tactical, single-phase build steps).
**Rule:** Strategic docs name future-phase content as such. Tactical docs include only what's being built in the current phase — anything else is noise that goes stale within a phase.

*Source: phase01_doc_realignment.md#6*

---

### Tactical-extends-strategic creates a sync obligation

**When:** A tactical doc adds detail to (or differs from) the strategic doc on the same topic.
**Rule:** Either keep them in lockstep on every edit, or label the divergence explicitly with a "diverges from REPO_PLAN.md §3 because…" inline note. Silent divergence rots into contradiction.

*Source: phase03_config_files.md#5*

---

### Module/feature tables must distinguish shipped from planned in the same column

**When:** Building a README or planning doc table that lists modules, features, or capabilities.
**Rule:** Put status in the same column as the name (`1 — Shipped` / `2 — Planned`), not in a separate "status" line that scanning eyes skip. If a feature isn't callable, label it where the operator reads its name.

*Source: phase09_readme_expansion.md#2*

---

### Don't pre-extract reference docs until 2+ consumers exist

**When:** Tempted to create a `MODULE_REFERENCE.md` or similar reference file for a single module's parameters/schema.
**Rule:** Inline it in the README. One consumer doesn't earn its own file — operators have to chase a link. When the second module ships, *that's* the trigger to extract.

*Source: phase09_readme_expansion.md#3design*

---

### Restructured doc blocks need explicit scope labels

**When:** Refactoring a planning doc and a generic infrastructure block (e.g. "Logging") sits adjacent to module-specific content.
**Rule:** The generic block needs an explicit scope label (e.g. "Applies to: all modules") and intentional placement. Without the label, the next reader binds it to the nearest module by proximity and propagates the misreading.

*Source: phase01_doc_realignment.md#4*

---

## Templates — Semantics over Syntax

### Template files document semantics, not just syntax

**When:** Authoring a template file (e.g. `iocs_template.txt`, `config.example.json`).
**Rule:** Comment-document *how the file is consumed* and *what a match means*, not just *what valid lines look like*. Syntax templates prevent typos; semantic templates prevent misuse — and misuse is the more common failure.

*Source: phase04_iocs_template.md#2*

---

### Co-located README + central cheatsheet OK if one is the source of truth

**When:** Choosing between a per-directory README (e.g. `iocs/README.md`) and a central cheatsheet (e.g. `docs/CHEATSHEET.md`).
**Rule:** Both can exist, but pick one as the source of truth for shared content and have the other link back. Two independent versions of the same conventions will diverge within one phase.

*Source: phase04_iocs_template.md#4*

---

## Operator Experience

### Multiple deployment paths → parallel siblings, not primary + footnotes

**When:** A tool has meaningfully different deployment paths (e.g. git clone vs IOC engagement vs standalone paste).
**Rule:** Document them as parallel **Path A / Path B / Path C** sections with paste-able commands at the top of each. Operators scanning at 3am should find their path in <10 seconds. Don't bury alternatives in sidebars.

*Source: phase09_readme_expansion.md#3*

---

### Standalone-paste path documents paste, not iwr | iex

**When:** Documenting a no-clone fallback path for a security tool published on GitHub.
**Rule:** Describe **paste from clipboard**, not `iwr <raw-url> | iex`. `iwr | iex` from a security tool to a GitHub raw URL pattern-matches as a malicious dropper in any half-decent EDR; pasting forces the operator to look at the version they're running and creates an explicit human gate.

*Source: phase09_readme_expansion.md#2design*

---

## Lessons-Learned & Planning Hygiene

### Bug-specific troubleshooting entries have a half-life

**When:** Tempted to add "Pre-Phase-N build had bug X — `git pull` to fix" entries to a Troubleshooting table.
**Rule:** Useful immediately, stale within months. Either schedule a periodic prune, move them to `CHANGELOG.md` keyed by version, or delete at the next minor-version cut. Track the prune as a CF.

*Source: phase09_readme_expansion.md#1pitfall*

---

### Public docs that link to scheduled-for-reorg artifacts → CF before reorg

**When:** A README or other public doc links to internal artifacts (e.g. `lessons_learned/phase06_*.md`) that are scheduled to be reorganized.
**Rule:** Capture the dependency in a CF *before* the reorg starts. The reorg owns the lockstep update — not the public doc. Caught early because the link is named.

*Source: phase09_readme_expansion.md#2pitfall*

---

### Bootstrap phases keep the Applied Lessons section, with a placeholder row

**When:** Writing a phase reflection for a phase that has no prior phases to apply lessons from.
**Rule:** Keep the `Applied Lessons` table format with a single placeholder row (`| (none) | first phase | — |`). Don't drop the section silently — the cadence is part of the discipline, and the format normalizes to other phases.

*Source: phase01_doc_realignment.md#3*

---
