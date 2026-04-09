# Retroactive First Reflection — Capturing Knowledge from an Existing Project

Use this workflow when adding the lessons learned system to a project that
already has significant history — established patterns, known pitfalls,
past incidents, and design decisions that shaped the architecture but were
never formally recorded.

This is different from the normal capture workflow because there is no
single "phase" that produced these lessons. They accumulated over the
project's lifetime and exist in team knowledge, commit history, PR
discussions, and code comments.

---

## When to Use This

- The project has 50+ commits or multiple contributors
- The team can identify at least 5 lessons they've learned the hard way
- There are known patterns or pitfalls that new team members stumble on
- The project has been through at least one major refactor or incident

If the project is genuinely new (first few weeks of work), use the
standard bootstrap and normal reflection instead.

---

## Step 1: Run Bootstrap First

Complete the full bootstrap workflow in `reference/bootstrap.md` to create
the directory structure, INDEX.md, and `_overview.md`. Then return here.

---

## Step 2: Mine Git History for Milestones

Identify the major units of work in the project's history. These become
your retroactive "phase" boundaries.

```bash
# Find high-activity periods and major changes (adjust range to project age)
git log --oneline | head -50
# Identify files with the most churn (often the most lesson-rich areas)
git log --pretty=format: --name-only | sort | uniq -c | sort -rn | head -20
# Find merge commits that represent completed features or releases
git log --merges --oneline | head -20
```

Look for natural boundaries: releases, major feature completions, large
refactors, incident responses. Aim for 3-5 retroactive phases — don't
try to reconstruct every sprint.

---

## Step 3: Gather Institutional Knowledge

This is the most important step. The goal is to capture what the team
knows but hasn't written down. Sources to mine:

- **Ask the user directly:** "What are the 5-10 most important things a
  new session working on this project would need to know?"
- **PR descriptions and review comments:** Often contain design rationale
  and warnings about tricky areas
- **Issue tracker:** Closed bugs that took disproportionate effort reveal
  systemic patterns
- **Code comments:** `// HACK`, `// WORKAROUND`, `// NOTE` comments often
  mark lessons learned the hard way
- **Config files:** Non-obvious settings usually have a story behind them

```bash
# Find code comments that signal lessons
grep -rn "HACK\|WORKAROUND\|NOTE\|FIXME\|XXX\|TODO" --include="*.py" \
  --include="*.js" --include="*.ts" --include="*.go" --include="*.rs" \
  --include="*.java" --include="*.cs" --include="*.rb" . | head -30
```

---

## Step 4: Write Retroactive Phase Files

For each major milestone identified in Step 2, create a phase file.
Use the standard template from `reference/templates.md` but with these
adjustments:

- The date is the approximate completion date of that milestone
- The scope describes what was built or changed at that point
- Focus on **Bugs and Pitfalls** and **Design Decisions** — these are
  the highest-value sections for retroactive capture
- **What Went Well** may be sparse for older phases — that's fine
- **Applied Lessons** is empty for retroactive phases (no lookup protocol
  was in use yet)
- **Carry-Forward Items** only apply to the most recent retroactive phase
- **Metrics** can be omitted for older phases if the data isn't available

Quality over quantity. A retroactive phase file with 3 strong entries is
better than 10 vague ones.

---

## Step 5: Populate INDEX.md — Foundation Tier

Retroactive lessons differ from normal entries in one important way:
they are **already proven**. They come from lived experience, not a
single recent phase. Route them directly to the appropriate tier:

- Lessons that apply universally across the project → **Foundation** tier
- Lessons specific to a completed area with no active work → **Reference** tier
- Lessons about areas with active ongoing work → **Active** tier

Most retroactive entries will go to Foundation. This is the one case
where entries skip the Active tier.

---

## Step 6: Create AI Subject Files

Follow the normal workflow: write When/Rule entries in the appropriate
AI files, update `_overview.md` counts and keywords.

For retroactive entries, the Source pointer uses the retroactive phase
file: `phase00_initial_patterns:3` or whatever naming convention the
project chose.

---

## Step 7: Verify and Transition

Run the verification checks in `reference/verify.md`.

After the retroactive reflection is complete, all future work uses the
normal capture workflow in SKILL.md Section 3a. The retroactive phase
files become part of the project's permanent record — they anchor the
Foundation tier and provide narrative context for proven rules.

---

## Checklist

- [ ] Bootstrap completed (directory structure, INDEX.md, _overview.md)
- [ ] Git history reviewed for 3-5 milestone boundaries
- [ ] Institutional knowledge gathered from user, PRs, issues, comments
- [ ] Retroactive phase files written with focus on Bugs/Pitfalls and Decisions
- [ ] INDEX.md populated — most entries in Foundation tier
- [ ] AI subject files created with When/Rule entries
- [ ] _overview.md counts and keywords updated
- [ ] Verification checks passed
