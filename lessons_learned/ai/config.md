---
name: config
description: Config-file rules covering schema ownership, in-file documentation, the .env contract, and tactical-vs-strategic sync.
type: ai-subject
---

# Config — Subject Rules

Rules for designing, naming, and documenting configuration files in this toolkit. Anchor topics: per-module ownership, in-file `Description` over sidecars, the `.env.example` contract, and how config files relate to planning docs.

---

## Ownership & Naming

### Per-module config files over crammed shared files

**When:** Designing a config file for a new module's settings (weights, thresholds, exclusions).
**Rule:** Ship a per-module config (e.g. `triage-weights.json` for `Invoke-BotnetTriage`) instead of cramming unrelated fields into a shared `scoring-weights.json`. Config ownership follows module ownership; modules ship and retire together with their config.

*Source: phase01_doc_realignment.md#5*

---

### Reconcile divergent planning docs against the committed config file

**When:** Two planning docs (REPO_PLAN, PHASE_PLAN) describe a config file's structure differently.
**Rule:** Read the committed file, label the winner by role (tactical doc wins for implementation; strategic doc wins for forward-looking architecture). Update the loser. See `docs.md` for the general rule.

*Source: phase03_config_files.md#2*

---

## In-File Documentation

### Prefer in-file Description fields over sidecar docs

**When:** Documenting a config file's purpose, units, or semantics.
**Rule:** Add a `Description` field at the top of the JSON/YAML/TOML itself. Travels with the file under refactor, survives renames and tool transformations, can't be deleted while the file lives. Sidecar docs (`config_README.md`) drift.

```jsonc
{
  "Description": "Risk weights for Invoke-BotnetTriage. Tunable per engagement.",
  "Connections": { ... }
}
```

*Source: phase03_config_files.md#4*

---

## Tactical vs Strategic Sync

### Tactical-extends-strategic creates a sync obligation

**When:** A tactical phase doc adds a config field the strategic doc doesn't yet name.
**Rule:** Either keep both in lockstep on every edit, or label the divergence inline. Silent divergence is the most common source of "the docs lied" rage in month 2.

*Source: phase03_config_files.md#5*

---

## The .env Contract

### Stub .env.example ships at the phase that creates the expectation, not the phase that reads it

**When:** A future phase will need API keys (VirusTotal, AbuseIPDB), and the current phase has none of those calls yet.
**Rule:** Ship the empty `.env.example` placeholder *now*, the moment the contract is established. Operators should know the API-key shape before the phase that uses them lands. Same principle for config stubs that future phases will populate.

*Source: phase01_doc_realignment.md#7*

---

### Validate at write-time

**When:** Hand-authoring a config file.
**Rule:** Round-trip parse it immediately after writing. See `process.md` "Validate JSON/YAML/TOML in the same step you write it" for details.

*Source: phase03_config_files.md#1*

---
