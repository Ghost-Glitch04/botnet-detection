---
name: process
description: Process rules covering pre-write verification sweeps, scaffold/bootstrap discipline, and the lessons-learned cadence itself.
type: ai-subject
---

# Process — Subject Rules

Rules for *how* to work, not *what* to build. Anchor topics: verify-before-write sweeps, tool selection on Windows, scaffolding hygiene, and the lessons-learned discipline.

---

## Verify Before Writing

### Glob sweep before writing files into a new directory tree

**When:** Starting a phase that creates files in a new or sparsely-populated directory tree.
**Rule:** Run a single `Glob` over the target tree first to confirm current state. Catches in-progress work you might overwrite, surfaces leftover scaffold from a previous attempt, and excludes the "wait, this file already exists" class of bug. Costs <1s.

*Source: phase02_directory_scaffold.md#1*

---

### Validate JSON/YAML/TOML in the same step you write it

**When:** Hand-authoring a structured config file (JSON, YAML, TOML).
**Rule:** Round-trip parse it (`Get-Content | ConvertFrom-Json`, etc.) immediately after `Write` finishes. The cheapest moment to catch a typo is right after typing it. Same principle as parser-validation for `.ps1` and link-checking for `.md`.

*Source: phase03_config_files.md#1*

---

### "Already done" prior-phase files need re-verification when a current step depends on them

**When:** A planning doc says a file from a prior phase is "complete," but the current step depends on a specific property of that file.
**Rule:** Re-read it. Prior-phase "complete" labels are not load-bearing. Verify the property the current step depends on is actually present, not just that the file exists.

*Source: phase03_config_files.md#3*

---

### When two planning docs disagree, read the committed file then reconcile

**When:** Mid-phase, two planning docs describe the same file's contents differently.
**Rule:** Read the committed file (ground truth), then update the wrong plan(s) to match. Label the winner by role: tactical doc wins for implementation details, strategic doc wins for architecture. See also: docs.md "When two planning docs disagree about a file, read the committed file."

*Source: phase03_config_files.md#2*

---

## Scaffolding & Tools

### Prefer Write at nested paths over Bash mkdir on Windows

**When:** Creating a new directory tree on Windows.
**Rule:** Use `Write` with the full nested path — directory creation is implicit. Avoids bash/PowerShell shell portability concerns and quoting around paths with spaces. Only fall back to a `mkdir` Bash call if the directory must be empty (use `.gitkeep` instead).

*Source: phase02_directory_scaffold.md#2*

---

### .gitkeep for transient empty dirs; READMEs only when guidance is load-bearing

**When:** Creating an empty directory that needs to exist in git (`output/`, `iocs/`, `logs/`).
**Rule:** Use a `.gitkeep` file. Reserve per-directory `README.md` for folders where operator guidance — file conventions, naming, security — is genuinely load-bearing. Empty README scaffolds rot.

*Source: phase02_directory_scaffold.md#3*

---

## Lessons-Learned Cadence

### On bootstrap phases, keep Applied Lessons table with a placeholder row

**When:** Writing the very first phase reflection (no prior phases to apply lessons from).
**Rule:** Keep the `Applied Lessons` table with one placeholder row (`| (none — first phase) | — | — |`). Don't silently drop format sections. The cadence *is* the discipline.

*Source: phase01_doc_realignment.md#3*

---
