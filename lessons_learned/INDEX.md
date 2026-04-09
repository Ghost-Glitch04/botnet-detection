# Lessons Learned — Index

> **Project:** botnet-detection (Network Forensics Toolkit)
> **Naming convention:** Sequential (`phaseNN_shortname.md`)
> **Git-tracked:** yes
> **Initialized:** 2026-04-09

## Quick Reference — AI Subject Files

| File | Rules | Topics / Keywords |
|------|-------|-------------------|

*(populated as AI files are created)*

## Tag Vocabulary

```
powershell, forensics, botnet, triage, beacon, ioc, config, secrets,
error-handling, logging, testing, security, git, deploy, network,
process, remote-shell, standalone-fallback, scaffolding, docs
```

Tags are lowercase, hyphenated compounds, 1–3 per entry with primary tag first.
The vocabulary grows naturally — when a new concept appears, add the tag and
note it in the current phase file.

---

## Active

| tags | description | source | type |
|------|-------------|--------|------|
| process,docs | Prefer surgical Edit over wholesale Write when re-aligning large planning docs — diff scope = edit scope | phase01_doc_realignment.md#1 | went-well |
| process,docs,verification | After a global rename/architecture swap, Grep the modified files for old identifiers — each stale hit is a bug | phase01_doc_realignment.md#2 | went-well |
| process,lessons-learned | On bootstrap phases, keep the Applied Lessons table with a placeholder row — don't drop format sections silently | phase01_doc_realignment.md#3 | went-well |
| docs,refactoring | When restructuring module-specific content, generic infrastructure blocks nearby need an explicit scope label + intentional placement | phase01_doc_realignment.md#4 | pitfall |
| config,naming | Prefer per-module config files over cramming unrelated fields into one shared file — config ownership follows module ownership | phase01_doc_realignment.md#5 | pitfall |
| docs,planning | Strategic docs (repo blueprint) include future-phase content; tactical per-phase docs scope strictly to their phase | phase01_doc_realignment.md#6 | design |
| config,security,contract | Committed `.env.example` / config stubs ship at the phase that first *creates the expectation*, not the phase that first *reads* it | phase01_doc_realignment.md#7 | design |
| process,scaffolding,verification | Before writing files to a new directory tree, run a single Glob sweep to confirm current state and rule out overwriting in-progress work | phase02_directory_scaffold.md#1 | went-well |
| process,scaffolding,tools | On Windows, prefer `Write` at nested paths over Bash `mkdir` — directory creation is implicit and avoids shell portability concerns | phase02_directory_scaffold.md#2 | went-well |
| scaffolding,git,docs | Use `.gitkeep` for transient empty dirs; reserve per-directory READMEs for folders where operator guidance is load-bearing | phase02_directory_scaffold.md#3 | design |
| process,config,verification | Validate JSON/YAML/TOML syntax in the same step you write it by hand — cheapest moment to catch a typo is right after typing | phase03_config_files.md#1 | went-well |
| config,docs,verification | When two planning docs describe the same config file, read both and reconcile divergence — label winner by role (tactical > strategic for implementation) | phase03_config_files.md#2 | went-well |
| config,git,verification | "Already done" prior-phase files need re-verification if the current step depends on a specific property of them | phase03_config_files.md#3 | pitfall |
| config,docs | Prefer in-file `Description` fields over sidecar docs for config files — travels with the file, survives tool transformations | phase03_config_files.md#4 | design |
| config,docs,planning | Tactical-extends-strategic is legitimate but creates a sync obligation — either keep in lockstep or explicitly label the divergence | phase03_config_files.md#5 | design |

## Foundation

| tags | description | source | type |
|------|-------------|--------|------|

## Reference

| tags | description | source | type |
|------|-------------|--------|------|
