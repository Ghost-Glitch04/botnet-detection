# Templates — Exact Formats for All Three Layers

Read this file before writing any lesson entries. It contains the exact
format for each layer plus a worked example showing one lesson in all three.

---

## Phase File Entry

```markdown
### {N}. {Descriptive Title}
<!-- tags: tag1,tag2,tag3 -->

{1-3 narrative paragraphs explaining what happened, why it matters,
and what the fix or approach was. Write for someone who wasn't there.}

**Lesson:** {One sentence distilling the takeaway. Present tense.
This is what gets extracted into INDEX.md and AI files.}
```

**Rules:**
- Number entries sequentially within each section (What Went Well starts
  at 1, Bugs and Pitfalls continues the sequence)
- Tags: on the line immediately after `###`, in an HTML comment, lowercase,
  no spaces after commas — this makes `grep -r "tag1" lessons_learned/`
  hit both INDEX.md and phase files consistently
- `**Lesson:**` is mandatory — it is the extractable takeaway
- Use past tense for narrative, present tense for the lesson

---

## INDEX.md Row

One row in the appropriate tier table. Every row must be a complete,
self-contained grep result — all metadata on one line.

```markdown
| tags | description (under 120 chars, key concept first) | source_pointer | type |
```

**Grep optimization:** Frontload the description with the core concept.
Good: `Validate UUID before any database query to prevent silent 404s`
Bad: `When working with databases, make sure you validate UUIDs first`

The first version has "Validate UUID" and "database" in the first 50
characters. A grep hit shows the important part immediately.

**Example:**
```markdown
| database,performance | Add indexes for WHERE/ORDER BY columns before load testing; missing indexes invisible at low volume | phase03_api_optimization:4 | rule |
```

---

## AI Subject File Rule

```markdown
### {Rule Title — imperative or descriptive, containing searchable keyword}

**When:** {Specific context or condition when this rule applies}
**Not when:** {Optional: conditions where a keyword match is misleading
and this rule should be skipped}
**Rule:** {The instruction itself, 2-4 sentences. Concrete and actionable.}

{Optional: fenced code block showing the pattern — only if non-obvious}

{Optional: **Symptom:** observable failure mode if this rule is violated}

{Optional: **Companions:** file.md → "Rule Title", file.md → "Rule Title"}

*Source: {phase_id}_{name}:{entry_number_or_section}*

---
```

**Grep optimization for headings:** The `### ` heading should contain
the primary keyword someone would search for. A session can run
`grep "^### " lessons_learned/ai/{topic}.md` to get a scannable table of contents
without loading the file.

Good: `### Validate UUID before database queries`
Bad: `### Important rule about data integrity`

### Not-When Guidance

The `**Not when:**` line is optional. Most rules don't need one — their
`**When:**` condition is specific enough that false matches are rare.

**Add Not-when when:**
- The rule's keywords overlap with a different context that is common in
  the project (e.g., "index" matches both database indexes and array indexes)
- Applied Lessons data shows the rule was marked `not applicable` in 2+ phases —
  this means sessions keep retrieving it unnecessarily
- The rule has a narrow scope but uses broad keywords in its heading

**Keep it to one line.** Not-when is a quick filter, not a detailed explanation.
If the boundary needs more than one sentence, the When condition is probably
too broad and should be tightened instead.

**Examples:**
- `**Not when:** The query targets a read-only view or materialized table with no write path`
- `**Not when:** The service call is fire-and-forget with no response dependency`
- `**Not when:** The column is already covered by an existing composite index`

### Companions Guidance

The `**Companions:**` line is optional. Add it only when rules are
meaningfully interdependent — using one without the other leads to an
incomplete solution or a predictable gap.

**Add companions when:**
- Two rules address different facets of the same failure mode
  (e.g., timeout configuration + retry logic)
- One rule's effectiveness depends on another being in place
  (e.g., index optimization only matters if load testing follows)
- Rules from different AI files were consistently `applied` together
  in Applied Lessons across 2+ phases

**Do not add companions for:**
- Rules that are merely in the same domain (both about databases)
- Rules where the connection is obvious from the topic file structure
  (adjacent rules in the same AI file don't need companions — the
  session already has both loaded)

Companions are directional but should be mutual — if A lists B as a
companion, B should list A. Keep companion lists short: 1-3 entries.
If a cluster grows beyond 3, it's a candidate for a concern map
(see the Concern Maps section below in this file).

---

## Superseded Rules

When a rule is found to be wrong, outdated, or replaced by a better
approach, do not delete it — supersede it. Deletion breaks source
pointers, orphans companion links, and loses the audit trail of why
the rule existed.

**In the AI file,** replace the rule body with a forward pointer:

```markdown
### {Original Rule Title}

**Superseded by:** {file}.md → "{New Rule Title}"

*Original source: {phase_id}_{name}:{N} | Superseded: {phase_id}_{name}:{N}*

---
```

**In INDEX.md,** prefix the description with `[SUPERSEDED]`:

```markdown
| tags | [SUPERSEDED] Original description → see new_rule_source | original_source | rule |
```

The `[SUPERSEDED]` prefix causes grep hits to immediately signal staleness.
A session seeing this in results knows to follow the forward pointer
instead of applying the old rule.

**When to supersede vs. update:**
- **Update** when the rule is mostly correct but needs a narrower scope →
  add a `**Not when:**` boundary or refine the `**Rule:**` text
- **Supersede** when the rule is fundamentally wrong or a different
  approach has replaced it entirely

Superseded rules remain in the system as historical records. Do not count
them in _overview.md rule totals — they no longer provide actionable recall.
Their companion links should be removed or redirected to the replacement rule.

---

## Cross-Reference Entry (for cross-cutting rules)

When a rule lives primarily in one AI file but is relevant to another,
add a one-line reference under `## See Also` at the bottom of the
secondary file. Do not duplicate the full When/Rule block.

```markdown
## See Also

- See: security.md → "Sanitize inputs at all database boundaries"
- See: process.md → "Run smoke tests after every config change"
```

---

## Carry-Forward Resolution

When a carry-forward item from a prior phase is resolved, mark it in
the current phase file's Carry-Forward section:

```markdown
## Carry-Forward Items

CF-3: RESOLVED in phase05_security_hardening
CF-7: Retry logic on 503 responses still needs exponential backoff
CF-8: Load time regression from phase4 — needs profiling
```

Unresolved items keep their original CF number across phases.

---

## Phase File Structure

When creating a new phase file, use this skeleton:

```markdown
# {Phase ID} — {Short Topic Name}

> **Scope:** {1-2 sentence description of what was built or changed}
> **Date:** {YYYY-MM-DD}

---

## Applied Lessons
{Which existing rules were consulted during this work and their outcome}

## What Went Well
{Numbered ### entries with tags and lessons}

## Bugs and Pitfalls
{Numbered ### entries continuing the sequence}

## Design Decisions
{Numbered ### entries for non-obvious choices with tradeoffs}

## Carry-Forward Items
{Prefixed CF-{N}: items that are open debt for the next phase}

## Metrics

| Metric | Value |
|--------|-------|
```

### Applied Lessons Format

This section records which existing rules were consulted during the work
and whether they helped. It serves three purposes:
- Validates that the lookup protocol is working (rules are being found)
- Identifies which rules are frequently used together (affinity signal)
- Reveals when rules are retrieved but don't apply (noise signal)

Each entry is one line in a table. Keep it terse — this is structured
data, not narrative.

```markdown
## Applied Lessons

| Rule (file → heading) | Outcome | Note |
|------------------------|---------|------|
| database.md → "Add indexes for WHERE columns" | applied | Prevented the timeout issue from Phase 2 |
| error-handling.md → "Retry with exponential backoff" | applied | Used together with the index rule for the batch endpoint |
| security.md → "Parameterized queries only" | already in place | Codebase already follows this — confirmed, no action needed |
| testing.md → "Mock external services in unit tests" | not applicable | This phase had no external service calls |
| config.md → "Cache TTL matches data freshness" | contradicted | TTL was set per rule but stale data still served; root cause was a second cache layer |
```

**Outcome values:**
- `applied` — The rule directly influenced a design or implementation decision
- `already in place` — The rule was consulted but the codebase already conforms
- `not applicable` — The rule was retrieved (keyword matched) but didn't apply to this context
- `missed` — A rule that *should* have been consulted but wasn't found or wasn't looked up; discovered only in hindsight during reflection
- `contradicted` — The rule was followed and led to a failure. This is the strongest feedback signal — it means the rule itself is wrong or incomplete for this context

The `missed` outcome reveals gaps in the lookup process. If a rule exists
but wasn't found, the _overview.md keywords or the INDEX.md description
may need improvement. If no rule exists, it's a candidate for a new entry.

The `contradicted` outcome triggers corrective action: either add a
**Not when:** boundary to narrow the rule's scope, update the rule text,
or supersede it entirely (see Superseded Rules above).

Rules that were `applied` together in the same phase are affinity candidates —
they may be natural companions (see Companions Guidance above).

### Metrics Guidance

Choose 3-5 metrics relevant to the work. Common options:

| Metric | When to use |
|--------|-------------|
| Tests before / after | Any phase that adds or changes tests |
| New files / Modified files | Structural changes |
| Coverage delta | Test-focused phases |
| Lines changed | Large refactors |
| Performance benchmark | Optimization work |
| Build/deploy outcome | Infrastructure phases |
| Bugs found / fixed | Stabilization phases |

Do not invent metrics — pick from this list or add project-specific
ones that are objectively measurable.

---

## Worked Example — One Lesson in All Three Formats

**Phase file entry:**
```markdown
### 4. Database query timeouts caused by missing index on status column
<!-- tags: database,performance -->

The /api/orders endpoint began timing out under load. Investigation showed
the query filtering by order status was doing a full table scan. Adding a
composite index on (status, created_at) reduced p95 latency from 1200ms
to 45ms.

**Lesson:** Add database indexes for any column used in WHERE or ORDER BY
clauses before load testing — missing indexes are invisible at low volume.
```

**INDEX.md row:**
```markdown
| database,performance | Add indexes for WHERE/ORDER BY columns before load testing; missing indexes invisible at low volume | phase03_api_optimization:4 | rule |
```

**AI subject file rule (in `ai/database.md`):**
```markdown
### Add indexes for columns used in WHERE and ORDER BY clauses

**When:** Writing or reviewing queries that filter or sort on a column
**Not when:** The column is already covered by an existing composite index
**Rule:** Ensure every column in a WHERE or ORDER BY clause has an
appropriate index. Test with realistic data volume — missing indexes
cause no symptoms at small scale but produce timeouts under load.
Composite indexes should match the query's column order.

**Symptom:** Endpoint works in development but times out in staging/production.

**Companions:** testing.md → "Load test with realistic data volume"

*Source: phase03_api_optimization:4*

---
```

---

## _overview.md Format

Each AI file gets one line. Include topic keywords so `grep` on _overview.md
routes to the right file without loading any of them.

```markdown
# AI Subject Files — Overview

| File | Rules | Topics / Keywords |
|------|-------|-------------------|
| testing.md | 5 | unit tests, fixtures, mocking, coverage, assertions |
| security.md | 3 | auth, secrets, sanitize, injection, CSRF |
| process.md | 4 | workflow, phased approach, review, naming |
```

### Concern Maps

Concern maps live in the same `_overview.md` file, below the file table.
Each map is a named cluster of rules across multiple files that together
address a design concern. They are the highest-efficiency lookup target —
one grep hit returns a curated combination.

```markdown
## Concern Maps

| Concern | Rules | Description |
|---------|-------|-------------|
| Resilience | error-handling.md → "Retry with exponential backoff", error-handling.md → "Circuit breaker for external calls", config.md → "Timeout thresholds per service" | Preventing cascading failures in service calls |
| Data integrity | database.md → "Add indexes for WHERE columns", database.md → "Validate inputs at service boundary", security.md → "Parameterized queries only" | Ensuring data correctness from input to storage |
| Deploy safety | process.md → "Smoke test after every deploy", config.md → "Environment parity staging-prod", testing.md → "Integration suite before merge" | Preventing regressions from reaching production |
```

**Grep optimization:** Name concerns by their design purpose using terms
a session would naturally search for. "Resilience" is better than
"retry-timeout-circuit-breaker" because a session working on service
reliability would grep for "resilien" and hit the map.

**When to create a concern map:**
- 3+ rules across 2+ AI files share mutual companion links
- Applied Lessons data shows the rules are consistently `applied` together
- The combination addresses a recognizable design concern with a natural name

**When NOT to create one:**
- Rules are all in the same AI file (a session already loads them together)
- The grouping is speculative — no Applied Lessons data supports it
- The "concern" is just a technology name (that's what AI files are for)

Concern maps start empty at bootstrap and grow from observed companion
clusters. Do not create them speculatively.

**When to remove a concern map:**
- All constituent rules have graduated to Reference and no active work
  touches the concern
- A constituent rule has been superseded and the remaining valid rules
  number fewer than 3 — the cluster no longer forms a coherent concern
