---
name: reflect
description: >
  Capture and retrieve institutional knowledge from project work using a
  structured Lessons Learned system. This skill covers both WRITING new
  lessons (reflection) and READING existing lessons (lookup before work).
  Trigger: user says "Reflect", "capture lessons", "what did we learn",
  "lessons learned", "retro", "retrospective", "post-mortem", "debrief",
  "knowledge transfer", "document this for next time", or asks to review
  what went well/poorly. Also trigger when starting significant work on
  a project that has a lessons_learned/ directory — run the lookup protocol
  first. Apply whenever the user wants to capture or retrieve institutional
  knowledge.
---

# Reflect — Lessons Learned Skill

Teaches two workflows: **lookup** (retrieve knowledge before working) and
**capture** (record knowledge after working). Both use the same three-layer
system optimized for grep-based discovery.

This system captures **project-level** institutional knowledge — what was
built, what broke, what was decided. For user preferences and personal
context, use your environment's memory or preferences system instead.

Read this document fully before writing or reading any entries.

---

## 1. System Architecture — Three Layers

The lessons learned system stores knowledge in three formats. Each is
optimized for a different access pattern.

### Layer 1: Phase Files (narrative source of truth)
**Location:** `lessons_learned/{phase_id}_{short_name}.md`
**Access pattern:** Read when you need the full story behind a rule.
**Format:** Markdown sections with numbered entries, tag comments, and
bold `**Lesson:**` takeaways. One file per major unit of work.

### Layer 2: INDEX.md (grep-optimized discovery router)
**Location:** `lessons_learned/INDEX.md`
**Access pattern:** `grep` target. Every row is one self-contained line
with tags, description, source pointer, and type. A grep hit gives you
enough to decide whether to read deeper.
**Structure:** Three tiers — **Active** (recent), **Foundation** (proven
recurring), **Reference** (stable/completed).

### Layer 3: AI Subject Files (structured recall)
**Location:** `lessons_learned/ai/{topic}.md`
**Access pattern:** Read 1-2 targeted files for actionable rules in
**When/Rule** format. A cold-start session reads a topic file and gets
working knowledge without narrative overhead.
**Inventory:** `lessons_learned/ai/_overview.md` lists all files with
rule counts and topic keywords — grep this to find the right file.
Also contains **concern maps**: named clusters of rules across multiple
files that together address a design concern (e.g., "resilience,"
"data integrity"). A grep hit on a concern map returns a pre-curated
set of rules — the most efficient enrichment path.

**Relationship:** Phase files are the source of truth. INDEX.md points
into them. AI files extract actionable rules from them. A single lesson
appears in all three layers in different formats.

---

## 2. Lookup Protocol — Retrieve Knowledge Before Working

This is how accumulated experience improves current work. At the start
of a new session, check whether `lessons_learned/` exists. If it does,
run a lookup scoped to the current task before writing code.

### When to look up
- **Always:** Before any task that creates, modifies, or deletes logic
- **Always:** When stuck on a problem or choosing between design options
- **Skip:** Formatting changes, documentation typos, dependency bumps
  with no behavioral change

### Choosing keywords
Pick 2-3 keywords from different angles of the task. Good keywords come
from three sources:

| Source | Example | Why it works |
|--------|---------|-------------|
| Technology/framework being touched | `sqlalchemy`, `docker`, `auth` | Matches the tag column in INDEX.md directly |
| Problem class (not the specific error) | `timeout`, `race-condition`, `validation` | Matches the description column — how lessons are worded |
| Architectural layer or concern | `api`, `migration`, `deploy`, `testing` | Catches cross-cutting rules that span technologies |

Avoid: specific variable names, error codes, file paths — these are too
narrow and won't match how lessons are written.

### Quick lookup
```bash
# 1. Search the index with 2-3 keywords from different angles
grep -i "keyword1\|keyword2" lessons_learned/INDEX.md
# 2. If hits: identify which AI file covers the topic
#    Also check for concern map hits — a concern map returns a curated
#    set of rules across multiple files, pre-selected to work together
grep -i "keyword" lessons_learned/ai/_overview.md
# 3. If a concern map matched: load the listed rules directly from their
#    respective AI files — this is cheaper than loading entire files
# 4. If individual file matched: read that AI file, check **When:** and
#    **Not when:** before reading full body. Skip if Not-when matches.
# 5. Apply relevant rules before writing code
# 6. If a loaded rule has a **Companions:** line, load those rules too —
#    they address related facets the primary rule doesn't cover alone
```

### Deep lookup (when stuck or before major design decisions)
```bash
# Search across all AI files for broader matches
grep -rn "keyword" lessons_learned/ai/
# Scan a specific AI file's table of contents without loading it
grep "^### " lessons_learned/ai/{topic}.md
# If you need the full narrative behind a rule, follow its Source pointer
# to the phase file — read only that section
```

### Refining results

**Zero hits — broaden the search:**
1. Check the tag vocabulary in INDEX.md for the closest matching tag —
   your keyword may not match the project's terminology
2. Try synonyms or the broader problem class: `timeout` → `performance`,
   `auth` → `security`, `flaky` → `testing`
3. Scan AI file headings directly for related concepts:
   `grep "^### " lessons_learned/ai/*.md | grep -i "keyword"`
4. If still nothing, the system has no knowledge on this topic — proceed
   carefully, and note the gap so the next reflection can fill it

**Too many hits — narrow without losing relevance:**
```bash
# Combine two keywords with piped grep (AND logic)
grep -i "keyword1" lessons_learned/INDEX.md | grep -i "keyword2"
# Search only the Active tier (most recent and relevant)
sed -n '/^## Active/,/^## Foundation/p' lessons_learned/INDEX.md | grep -i "keyword"
# Check concern maps first — if one matches, it pre-selects the best subset
grep -i "keyword" lessons_learned/ai/_overview.md
```

**Ambiguous hits — determine relevance cheaply:**
- Read only the `**When:**` and `**Not when:**` lines before loading any
  full rule body — this costs ~20 tokens per rule skimmed
- If your task matches a Not-when condition, skip the rule immediately
- For remaining candidates, scan the `**Symptom:**` line — if the failure
  mode described is impossible in your context, the rule is likely noise

### The grep contract
INDEX.md and AI files are formatted so grep results are immediately useful:
- **INDEX.md rows:** All metadata on one pipe-delimited line — tags,
  description (under 120 chars, key concept frontloaded), source pointer, type
- **INDEX.md tags:** Lowercase, comma-separated, no spaces, primary tag first
- **AI file headings:** `### ` headings contain the searchable keyword so
  `grep "^### " lessons_learned/ai/{topic}.md` produces a scannable table of contents
- **AI file When/Not when:** Each rule's **When:** and optional **Not when:**
  lines are a quick relevance filter — read these before the full rule body.
  If your task matches a Not-when condition, skip the rule without loading
  the rest. This keeps token cost proportional to relevant rules, not total hits.
- **AI file Companions:** Optional pointers to rules in other files that are
  meaningfully interdependent. Follow these to load related context across
  files without broad searching — one targeted read per companion
- **_overview.md:** One line per file with topic keywords so grep tells you
  which file to read without loading any of them
- **_overview.md concern maps:** Named clusters of rules across files. A grep
  hit on a concern name returns a curated multi-file rule set — load only
  those specific rules instead of entire files. Most efficient lookup path.

**Token budget:** A quick lookup costs ~100-200 tokens (grep output + one
AI file section). A full reflection costs more but runs infrequently. The
system is designed so reading is cheap and writing is thorough.

**Track what you load.** During work, keep a running note of which rules
you consulted and whether they influenced your decisions. This feeds the
Applied Lessons section during the next reflection — without it, the
system captures what you *learned* but not what you *used*, and the
feedback loop that makes future lookups smarter is broken.

Track format: `| file.md → "Rule Title" | applied/in place/N/A/missed/contradicted | brief note |`
Full format details in `reference/templates.md` → Applied Lessons Format.

---

## 3. Capture Workflows

### 3a. Full Reflection (end of a work unit)

A "phase" corresponds to a coherent unit of work with a definable scope
and outcome — typically a feature, a refactor, a testing pass, or an
incident response. If in doubt, one phase file per reflection is the
right default.

Read `reference/templates.md` before writing any entries — it has exact
formats for all three layers.

**Step 1 — GATHER (read-only)**
1. `git log --oneline -20` (or relevant range) for the work being reflected on
2. Review notes, test results, error messages from the session
3. Identify which existing lessons were looked up or applied during this work —
   these feed the Applied Lessons section. Include rules that were consulted but
   turned out not to apply, and rules that *should* have been consulted but were
   missed (discovered only now in hindsight).
4. Read the most recent phase file for numbering and format continuity
5. Read `INDEX.md` — scan Active tier for existing coverage (avoid duplicates)
6. Identify which AI subject files are likely affected (1-3 files)

**Step 2 — DRAFT the phase file**
7. Determine the phase identifier (see naming convention in `reference/bootstrap.md`)
8. Write header with scope and date
9. **Applied Lessons:** Fill the table from the GATHER inventory (sub-step 3) —
   which rules were consulted, their outcome (applied / already in place /
   not applicable / missed / contradicted), and a one-line note.
   See `reference/templates.md` for exact format.
   - For any rule marked `contradicted`: the rule was followed and caused a
     failure. Decide whether to update the original rule (add a Not-when
     boundary), or supersede it (see `reference/templates.md` → Superseded Rules).
10. **What Went Well:** 3-5 entries for approaches that worked or decisions validated
11. **Bugs and Pitfalls:** Entries for each non-trivial bug. Focus on the *class* of
   bug, not the instance. Root cause and fix.
12. **Design Decisions:** Entries for non-obvious choices with tradeoffs
13. **Carry-Forward Items:** Open debt (prefix `CF-{N}:`)
    - Check prior phase files for unresolved CF items — mark any that were
      addressed in this phase: `CF-{N}: RESOLVED in {current_phase_id}`
    - Carry unresolved items forward with their original CF number
14. **Metrics:** Fill the metrics table (see `reference/templates.md` for options)

**Step 3 — UPDATE INDEX.md**
15. For each phase file entry, add one row to the **Active** tier
16. Use the entry's tags, a frontloaded description (under 120 chars), source
    pointer, and type classification
17. Check for duplicates — if a rule already exists in INDEX.md, update its source
    pointer to add the new phase reference instead of creating a new row
18. At phase transitions, graduate old Active entries:
    - **Active → Foundation:** Look for Active rows with multi-phase source
      pointers (e.g., `phase03_auth:2, phase07_api:4`) — these were reinforced
      by duplicate detection in Step 17. Multi-phase sources → Foundation.
    - **Foundation → Reference:** Requires both conditions: (a) no new entries
      with that tag in the last 2 phases AND (b) the underlying work area is
      completed or stable — no active development expected. Tag inactivity alone
      is not sufficient; a stable but actively consulted tag (e.g., security)
      stays in Foundation.

**Step 4 — UPDATE AI subject files**
19. For each `rule`, `bug`, or `pattern` entry, write a When/Rule entry in the
    appropriate AI subject file (route by primary technology or concern)
20. For cross-cutting rules, add a short cross-reference in the secondary file:
    `See: {primary_file}.md → "{Rule Title}"` — do not duplicate the full rule
21. Review Applied Lessons from this and prior phases for companion candidates:
    - Rules marked `applied` together in the same phase across 2+ reflections
      are strong companion candidates
    - A new rule whose effectiveness depends on an existing rule in a different
      AI file should list that rule as a companion
    - Add `**Companions:**` lines to both rules (mutual linking). See
      `reference/templates.md` for format and guidance. Keep lists to 1-3 entries.
22. Review companion clusters for concern map graduation:
    - If 3+ rules share mutual companions forming a coherent design concern,
      create or update a concern map in `_overview.md`
    - Name the concern by its design purpose, not its technology (e.g.,
      "Resilience" not "retry-timeout-circuit-breaker")
    - See `reference/templates.md` for concern map format
23. Update rule counts in `_overview.md` and the INDEX.md Quick Reference table
24. Verify `_overview.md` Topics/Keywords still reflect each AI file's coverage —
    add keywords for any new concepts introduced by this reflection
25. New AI file threshold: 3+ rules on a topic with no existing file. Create it,
    add to `_overview.md` and INDEX.md Quick Reference.
26. AI file size threshold: if an AI file exceeds ~30 rules, split it by subtopic
    (e.g., `testing.md` → `unit-testing.md` + `e2e-testing.md`). Update all source
    pointers, `_overview.md`, and INDEX.md Quick Reference.

**Step 5 — VERIFY**
27. Run the verification checks in `reference/verify.md`

**If a reflection is interrupted** after writing the phase file but before
completing INDEX.md or AI file updates, run the verification checks on the
next session. Checks 1 and 2 will identify phase file entries missing their
INDEX.md rows or AI file rules. Complete the missing updates before starting
new work.

### 3b. Lightweight Capture (mid-session, single lesson)

When you discover something worth recording *right now* but a full
reflection would break flow:

1. Append one numbered entry to the **current** phase file (create one if
   none exists for this work unit — use `reference/bootstrap.md` for the
   header, leave other sections empty for now)
2. Add one INDEX.md Active row
3. Add one AI subject file rule
4. Skip Metrics and Carry-Forward — those are filled at full reflection.
   If the lesson was triggered by a prior rule you looked up (or failed to
   look up), add a row to the Applied Lessons table (create the table if the
   phase file doesn't have one yet). Leave the Outcome column for the full
   reflection to fill in if uncertain.

This keeps the three-layer contract intact without ceremony. When full
reflection runs later, it fills in the gaps.

### 3c. Conflict Avoidance

Before writing to any lessons learned file, check for concurrent changes:
```bash
# If lessons_learned/ is git-tracked:
git diff --name-only lessons_learned/
# If not git-tracked (new or excluded from repo):
ls -lt lessons_learned/*.md lessons_learned/ai/*.md 2>/dev/null | head -10
```
If files have changed since your last read, re-read before appending.
Append to the end of sections — never rewrite existing entries.

---

## 4. Decision Trees

### 4a. "Is this worth recording?"

**RECORD if:**
- A future session would need this to avoid repeating the mistake
- The fix required understanding not obvious from the code or commit
- A pattern emerged that applies beyond this specific instance
- A decision was made between alternatives with non-obvious tradeoffs
- Something worked unexpectedly well and the approach should be repeated

**When recording, also consider:** If this rule uses broad keywords that
could match unrelated contexts in this project, define a `**Not when:**`
boundary in the AI file entry. Check Applied Lessons — if a prior rule
was frequently marked `not applicable`, it likely needs a Not-when added.

**DO NOT RECORD:**
- Facts derivable from reading current code or `git log`
- The debugging journey — record only what worked and why
- Ephemeral task details (retried a command, changed a file path)
- Operational incidents without structural lessons
- Library version choices without non-obvious compatibility constraints

### 4b. "What type is this?"

| Type | Definition | Example |
|------|-----------|---------|
| **rule** | Prescriptive: "always X" or "never Y." Violating causes predictable failure. | "Validate UUID before any DB query" |
| **bug** | Specific failure encountered and fixed. Record failure mode + root cause. | "Batch insert silently drops rows over 1000" |
| **pattern** | Reusable approach that worked. Not prescriptive — alternatives exist. | "Fixture-driven parser testing" |

**Default to `rule`** when uncertain. Most entries are rules. If you
encounter a meta-observation about process or architecture, tag it as
`pattern` with a `process` tag.

### 4c. "Which AI subject file?"

Route by the **primary** technology or concern. Use the project's existing
AI files as the routing table:
```bash
cat lessons_learned/ai/_overview.md
```

General routing principles:
- Lesson about how a specific technology behaves → `{technology}.md`
- Testing any technology → `testing.md`
- Process/methodology regardless of tech → `process.md`
- Security regardless of tech → `security.md`
- Cross-cutting rules → write the full When/Rule entry in the **primary** file.
  In the secondary file, add only a one-line cross-reference at the bottom
  under a `## See Also` heading:
  `- See: security.md → "Sanitize inputs at all database boundaries"`
  This keeps the secondary file lean and avoids duplicate maintenance.

**New file vs. new section:** If a topic is a specialization of an existing
file (e.g., graph-api rules within a broader `powershell.md`), add a `##`
section header within the existing file until the subtopic crosses 3 rules.
At 3+ rules, split it into its own file.

### 4d. "Which INDEX.md tier?"

| Tier | Criteria |
|------|----------|
| **Active** | From current or recent work (last 2 phases). New entries always start here. |
| **Foundation** | Recurred across 2+ phases, or universal (security, validation). Graduate from Active when proven durable. |
| **Reference** | From completed, stable work. Graduate when tag is inactive for 2+ phases AND the work area is complete. |

---

## 5. Anti-Patterns — What NOT to Save

- **"Fixed the import error"** — Only record if it reveals a systemic pattern.
- **"Tried X, didn't work, tried Y"** — Record only Y and why. The journey is ephemeral.
- **"Changed file X line 42"** — Git knows the what. Record the WHY.
- **"Service was down, restarted it"** — Only record if it reveals a missing health check.
- **Duplicating an existing rule** — grep INDEX.md first. If it exists, update the source pointer.
- **Saving patterns visible in the code** — The codebase documents itself. Record what isn't obvious from reading the implementation.

---

## 6. Quick Reference Card

```
LOOKUP:    grep INDEX.md → grep _overview.md (files + concern maps) → filter When/Not-when → follow Companions → track
CAPTURE:   phase file → INDEX.md → ai/{topic}.md → companions → concern maps → _overview.md
Sections:  Applied Lessons / Well / Bugs / Decisions / Carry-Forward / Metrics
Entry:     ### N. Title  /  <!-- tags: -->  /  narrative  /  **Lesson:**
INDEX row: | tags | description (<120ch, frontloaded) | source | type |
AI rule:   ### Title  /  **When:**  /  **Not when:**  /  **Rule:**  /  code  /  Companions  /  *Source:*  /  ---
Not-when:  One-line boundary condition — skip rule if task matches  (add when keywords overlap unrelated contexts)
Companion: **Companions:** file.md → "Rule Title", file.md → "Rule Title"  (mutual, 1-3 max)
Concern:   | name | file.md → "Rule", file.md → "Rule" | description |  (3+ companion cluster → concern map)
Applied:   | rule (file → heading) | applied|in place|N/A|missed|contradicted | note |
Supersede: **Superseded by:** file.md → "New Rule"  /  INDEX.md prefix: [SUPERSEDED]
Cross-ref: See: {file}.md → "{Rule Title}"  (in secondary file's See Also)
Types:     rule | bug | pattern
Tiers:     Active → Foundation → Reference
Graduate:  Multi-phase source pointers → Foundation; tag inactive 2+ phases AND area complete → Reference
CF:        CF-{N}: description  /  CF-{N}: RESOLVED in {phase_id}
New file:  3+ rules on uncovered topic → create + update _overview + INDEX
Split:     30+ rules in one AI file → split by subtopic
Bootstrap: No lessons_learned/ dir? → read reference/bootstrap.md first
Retroactive: Existing project with history? → read reference/retroactive.md after bootstrap
```

---

## 7. Project Completion — Portable Export

Run this at project completion or before handoff/archiving.

When a project is finished, its Foundation-tier lessons are the most
valuable output — proven rules that apply beyond this specific codebase.
To carry them into future projects:

1. Extract all Foundation-tier rows from INDEX.md into `lessons_learned/export.md`
2. Include the corresponding AI file rules (full When/Rule entries)
3. Include any concern maps from `_overview.md` — these represent proven
   cross-cutting knowledge combinations and are highly portable
4. Strip project-specific source pointers — the rules now stand on their own
5. The export file can seed a new project's lessons learned system at bootstrap

---

## 8. Reference Files

Read these as needed — they are not loaded automatically.

| File | Read when... |
|------|-------------|
| `reference/templates.md` | Before writing any lesson entries (exact formats + worked example) |
| `reference/bootstrap.md` | Initializing lessons learned on a new project, or choosing naming conventions |
| `reference/retroactive.md` | Adding lessons learned to a project with existing history (first-time adoption on a mature codebase) |
| `reference/verify.md` | Running Step 5 — VERIFY, or auditing system integrity |
