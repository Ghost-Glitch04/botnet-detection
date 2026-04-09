# Bootstrap — Initialize Lessons Learned for a New Project

Run this once when a project does not yet have a `lessons_learned/` directory.

---

## Step 1: Create the Directory Structure

```bash
mkdir -p lessons_learned/ai
```

---

## Step 2: Choose a Naming Convention

Phase files need a consistent naming scheme. Choose one at project start
and document it in INDEX.md. Do not mix conventions within a project.

| Convention | Format | Best for |
|-----------|--------|----------|
| Sequential | `phase{NN}_{name}.md` | Milestone-driven projects with clear phases |
| Date-based | `{YYYY-MM-DD}_{name}.md` | Continuous delivery, sprint-based work |
| Feature-based | `feat_{name}.md` | Feature-branch workflows |

**Default:** Sequential (`phase01_`, `phase02_`...) unless the project has
a clear reason to prefer another. Zero-pad to two digits so filesystem
listings sort correctly beyond 9 phases. The source pointers in INDEX.md
and AI files use whatever convention the project chose.

---

## Step 3: Generate the Tag Vocabulary

Scan the project to build an initial tag set. Tags should cover:
- Primary languages and frameworks used (from package files, imports)
- Infrastructure (docker, ci, cloud provider)
- Cross-cutting concerns (testing, security, logging, config, error-handling)
- Always include: `process` (for methodology lessons)

```bash
# Discover languages by file extension
find . -maxdepth 3 -name "*.py" -o -name "*.js" -o -name "*.ts" \
  -o -name "*.go" -o -name "*.rs" -o -name "*.cs" -o -name "*.java" \
  -o -name "*.rb" 2>/dev/null | sed 's/.*\.//' | sort -u

# Discover frameworks from dependency files
cat package.json 2>/dev/null | head -30
cat requirements.txt Pipfile pyproject.toml 2>/dev/null | head -30
cat go.mod Cargo.toml Gemfile *.csproj 2>/dev/null | head -20

# Discover infrastructure
ls Dockerfile docker-compose* Makefile .github/workflows/* \
  terraform/ ansible/ 2>/dev/null
```

Record the tag vocabulary in the INDEX.md file (see Step 4).
Keep tags lowercase, single-word or hyphenated. Aim for 15-30 tags.
The vocabulary grows naturally — when a new technology appears, add
the tag and note it in the current phase file.

**Tag rules:**
- 1-3 tags per entry, primary technology first
- `process` for methodology/workflow lessons regardless of technology
- No spaces, lowercase, hyphenated compounds (`error-handling`, not `error handling`)

---

## Step 4: Decide on Version Control

Before creating files, decide whether `lessons_learned/` is tracked in git:
- **Track it** (recommended): Lessons are reviewed alongside code, diffs
  show what knowledge was added, and the conflict avoidance workflow in
  SKILL.md Section 3c works with `git diff`.
- **Exclude it:** Add `lessons_learned/` to `.gitignore`. Use this if
  lessons contain sensitive operational details or if the team prefers
  to manage knowledge separately.

Document this decision in the INDEX.md header.

---

## Step 5: Create INDEX.md

````markdown
# Lessons Learned — Index

> **Project:** {project name}
> **Naming convention:** {sequential | date-based | feature-based}
> **Git-tracked:** {yes | no}
> **Initialized:** {YYYY-MM-DD}

## Quick Reference — AI Subject Files

| File | Rules | Topics / Keywords |
|------|-------|-------------------|

*(populated as AI files are created)*

## Tag Vocabulary

```
process, testing, security, error-handling, config, logging,
{add project-specific tags here}
```

---

## Active

| tags | description | source | type |
|------|-------------|--------|------|

## Foundation

| tags | description | source | type |
|------|-------------|--------|------|

## Reference

| tags | description | source | type |
|------|-------------|--------|------|
````

---

## Step 6: Create _overview.md

```markdown
# AI Subject Files — Overview

| File | Rules | Topics / Keywords |
|------|-------|-------------------|

*(populated as AI files are created)*

## Concern Maps

| Concern | Rules | Description |
|---------|-------|-------------|

*(populated as companion clusters emerge — see SKILL.md Section 3a Step 22)*
```

---

## Step 7: First Phase File

Create the first phase file using the template in `templates.md` (sibling
to this file, also in `reference/`).

- If the project already has significant history (50+ commits, established
  patterns, known pitfalls), read `reference/retroactive.md` instead — it
  walks through capturing institutional knowledge from an existing codebase.
- If reflecting on recently completed work, proceed directly to the full
  reflection workflow in SKILL.md Section 3a.

---

## Step 8: Seed from Prior Project (optional)

If a prior project produced an `export.md` (see SKILL.md Section 7),
use it to pre-populate this project's lessons learned:

1. Copy Foundation-tier rules from the export into the new project's
   `ai/process.md`, `ai/security.md`, or other appropriate AI files
2. Add corresponding INDEX.md Foundation-tier rows
3. Import concern maps into `_overview.md` — rename or adjust any that
   don't fit the new project's scope, omit any whose constituent rules
   were excluded in step 1
4. Update `_overview.md` rule counts and keywords
5. Omit rules that are irrelevant to the new project's tech stack

This gives a new project the benefit of proven lessons without carrying
project-specific noise.

---

## Post-Bootstrap Checklist

- [ ] `lessons_learned/` directory exists with `ai/` subdirectory
- [ ] Git tracking decision made and documented in INDEX.md header
- [ ] `INDEX.md` created with naming convention documented and empty tier tables
- [ ] `ai/_overview.md` created with empty table
- [ ] Tag vocabulary seeded from project scan
- [ ] Naming convention chosen and recorded
- [ ] (If applicable) Prior project export reviewed and relevant rules seeded
