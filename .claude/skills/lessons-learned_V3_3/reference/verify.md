# Verify — Integrity Checks for Lessons Learned

Run these checks after every full reflection (SKILL.md Section 3a, Step 5 — VERIFY).
Each check includes the grep/command to run and what a failure looks like.

---

## Check 1: Every phase file entry has an INDEX.md row

```bash
# Extract entry numbers from the current phase file
grep -oE "^### [0-9]+" lessons_learned/{current_phase_file}.md | grep -oE "[0-9]+"

# For each number N, verify it appears in INDEX.md as a source pointer
grep "{phase_id}_{name}:{N}" lessons_learned/INDEX.md
```

**Failure:** A phase file entry number with no INDEX.md hit means a row
is missing. Add it to the Active tier.

---

## Check 2: Every rule/bug/pattern has an AI subject file entry

```bash
# List all entries from the phase file with their type (from INDEX.md)
grep "{phase_id}_{name}" lessons_learned/INDEX.md

# For each entry of type rule, bug, or pattern, verify it has an AI file entry
grep "{phase_id}_{name}:{N}" lessons_learned/ai/*.md
```

**Failure:** An INDEX.md row of type rule/bug/pattern with no AI file hit.
Write the When/Rule entry in the appropriate AI file.

---

## Check 3: AI file Source pointers resolve to real phase entries

```bash
# Extract all Source pointers from AI files
grep -rh "^\*Source:" lessons_learned/ai/ | sort -u

# For each pointer, verify the phase file and entry exist
# Pattern: *Source: {phase_id}_{name}:{entry}*
```

**Failure:** A Source pointer referencing a non-existent phase file or entry
number. Fix the pointer or remove the orphaned AI rule.

---

## Check 4: _overview.md rule counts match actual heading counts

```bash
# Count actual ### headings per AI file, subtracting superseded rules
# (_overview.md rule totals should exclude superseded rules)
for f in lessons_learned/ai/*.md; do
  [ "$(basename "$f")" = "_overview.md" ] && continue
  total=$(grep -c "^### " "$f")
  superseded=$(grep -c "^\*\*Superseded by:\*\*" "$f" 2>/dev/null || echo 0)
  active=$((total - superseded))
  echo "$(basename "$f"): $active (${superseded} superseded)"
done

# Compare against the counts listed in _overview.md
cat lessons_learned/ai/_overview.md
```

**Failure:** A mismatch between the active heading count and the listed count.
Update _overview.md with the correct number. Superseded rules are excluded
from the count — they no longer provide actionable recall (see templates.md
→ Superseded Rules).

---

## Check 5: No duplicate rules in INDEX.md

```bash
# Step 1: Find exact duplicate descriptions
# Note: $3 is the description column because the leading | makes $1 empty
awk -F'|' 'NF>3 {gsub(/^ +| +$/,"",$3); print $3}' lessons_learned/INDEX.md \
  | sort | uniq -d

# Step 2: Near-duplicates (manual scan) — sort descriptions and look for
# adjacent entries addressing the same failure mode or concept
awk -F'|' 'NF>3 {gsub(/^ +| +$/,"",$3); print $3}' lessons_learned/INDEX.md \
  | sort
```

**Failure:** Two rows with identical or near-identical descriptions.
Merge them — keep the one with the broader source pointer
(e.g., `phase03_auth:2, phase07_api:4`). Step 1 catches exact matches
automatically; Step 2 requires scanning the sorted output for entries
that describe the same concept in different words.

---

## Check 6: Cross-references resolve to real AI file rules

```bash
# Extract all See Also references
grep -rn "^- See:" lessons_learned/ai/

# For each, verify the target file and rule title exist
# Pattern: - See: {file}.md → "{Rule Title}"
# Verify: grep "^### {Rule Title}" lessons_learned/ai/{file}.md
```

**Failure:** A See Also reference pointing to a non-existent file or
rule title. Update the reference or remove it.

---

## Check 6b: Companion links resolve and are mutual

```bash
# Extract all Companion references from AI files
grep -rn "^\*\*Companions:\*\*" lessons_learned/ai/

# For each companion target (file.md → "Rule Title"):
# 1. Verify the target file exists
# 2. Verify the rule heading exists: grep "^### {Rule Title}" lessons_learned/ai/{file}.md
# 3. Verify the target rule links back (mutual): grep "Companions:" lessons_learned/ai/{file}.md
```

**Failure modes:**
- Target file or heading doesn't exist → fix the companion reference
- Link is one-directional → add the reciprocal companion to the target rule

---

## Check 7: No orphaned carry-forward items

```bash
# Find all open CF items across all phase files
grep -rn "^CF-" lessons_learned/ | grep -v "RESOLVED"

# These should only appear in the most recent phase file.
# If they appear in older files without a RESOLVED marker in a
# later file, they were dropped — re-add to the current phase.
```

**Failure:** An unresolved CF item in an older phase file that has no
matching `RESOLVED` or re-listing in any subsequent phase file. Carry
it forward to the current phase.

---

## Check 8: _overview.md keywords cover AI file content

```bash
# For each AI file, extract its rule headings and compare to _overview keywords
for f in lessons_learned/ai/*.md; do
  [ "$(basename "$f")" = "_overview.md" ] && continue
  echo "=== $(basename "$f") ==="
  grep "^### " "$f" | head -5
done

# Scan _overview.md to verify keywords match the rule topics
cat lessons_learned/ai/_overview.md
```

**Failure:** An AI file's rules cover a topic not represented in the
_overview.md Keywords column. Add the missing keyword — this is what
the lookup protocol uses to route grep queries to the right file.

---

## Check 9: AI files are not oversized

```bash
# Count rules per AI file — flag any with 30+
for f in lessons_learned/ai/*.md; do
  [ "$(basename "$f")" = "_overview.md" ] && continue
  count=$(grep -c "^### " "$f")
  [ "$count" -ge 30 ] && echo "SPLIT CANDIDATE: $(basename "$f") has $count rules"
done
```

**Failure:** An AI file with 30+ rules is too large for efficient lookup.
Split it by subtopic (e.g., `testing.md` → `unit-testing.md` + `e2e-testing.md`).
Update all source pointers in the split files, `_overview.md`, and INDEX.md
Quick Reference.

---

## Check 10: Concern map rules resolve to real AI file headings

```bash
# Extract all concern map rows from _overview.md (below the Concern Maps heading)
sed -n '/^## Concern Maps/,$p' lessons_learned/ai/_overview.md | grep "→"

# For each rule reference (file.md → "Rule Title"):
# Verify: grep "^### {Rule Title}" lessons_learned/ai/{file}.md
```

**Failure:** A concern map references a rule that doesn't exist — the
rule was renamed, moved during a file split, or deleted. Update the
concern map entry to match the current rule heading.

---

## Check 11: Superseded rules have valid forward pointers

```bash
# Find all superseded rules in AI files
grep -rn "^\*\*Superseded by:\*\*" lessons_learned/ai/

# For each forward pointer (file.md → "New Rule Title"):
# Verify: grep "^### {New Rule Title}" lessons_learned/ai/{file}.md

# Find superseded rows in INDEX.md
grep "\[SUPERSEDED\]" lessons_learned/INDEX.md
```

**Failure modes:**
- Forward pointer targets a non-existent rule → fix the pointer
- INDEX.md row is marked `[SUPERSEDED]` but the AI file rule isn't →
  add `**Superseded by:**` to the AI file rule
- AI file rule is superseded but INDEX.md row isn't marked → add
  `[SUPERSEDED]` prefix to the INDEX.md description
- Superseded rule still has companion links → remove or redirect companions
  to the replacement rule

---

## Quick Pass (abbreviated check)

When time is limited, run Checks 1, 4, and 8 — they catch the most
common issues (missing INDEX rows, stale _overview counts, and stale
_overview keywords that degrade lookup accuracy).
