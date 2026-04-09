# AI Subject Files — Overview

Subject files group lessons-learned rules by primary topic so an AI assistant can load only what it needs for the task at hand. Route by primary technology or concern. Each file uses the When/Rule template — quick to scan, source-cited.

| File | Rules | Topics / Keywords |
|------|-------|-------------------|
| [powershell.md](powershell.md) | 21 | strict-mode, scoping, dot-source, standalone-fallback, inline stubs, CIM/WMI perf, phase-gate error handling, library shape, bootstrap launcher, AST parsing, bash interop, smoke testing |
| [docs.md](docs.md) | 17 | markdown link checking, surgical Edit vs Write, plan-vs-file reconciliation, strategic-vs-tactical scoping, module/feature tables, template semantics, operator experience, paste vs iwr\|iex, troubleshooting half-life |
| [process.md](process.md) | 7 | pre-write Glob sweep, JSON/YAML validate-at-write, prior-phase re-verification, Windows Write over mkdir, .gitkeep vs README, lessons-learned cadence |
| [config.md](config.md) | 6 | per-module ownership, in-file Description, .env contract timing, tactical-extends-strategic sync, write-time validation |
| [testing.md](testing.md) | 7 | multi-tier non-redundancy, mock-data realism, AST parse-check, standalone-paste isolation, fresh pwsh child, helper-stub guard invisibility, fixture privacy |
| [heuristics.md](heuristics.md) | 5 | false-positive ceiling (>10%), dead-flag detection, threshold/floor math, cross-stage data-flow pitfalls, fallback concentration |

## Concern Maps

Concern maps surface companion clusters — rules that span 2+ subject files and reinforce each other. Route to a concern map when the question crosses topic boundaries.

| Concern | Rules | Description |
|---------|-------|-------------|
| **standalone-fallback** | powershell.md (Get-Command guards, helpers throw not exit, library stubs warn-not-throw, helpers degrade gracefully, Get-Variable -Scope 1) + testing.md (Tier 5 non-optional, helper-stub invisibility, fresh pwsh child) + heuristics.md (concentrate fallback on canonical path) | The toolkit's load-bearing "paste into remote shell when git clone is blocked" path. Inline stubs only execute via standalone-paste, so only Tier 5 can verify them. Concentrate complexity on the one file that IS the fallback. |
| **verify-at-write-time** | docs.md (markdown link sweep) + process.md (JSON/YAML round-trip parse, Glob sweep) + powershell.md (parser validation, smoke tests with positive+negative) + testing.md (AST parse-check before re-running tier) | The cheapest moment to catch a bug is the moment after typing the line that introduced it. Validation belongs in the same step as the write — link-check after writing markdown, parser-check after writing PS1, schema-check after writing JSON. |
| **plan-vs-truth reconciliation** | docs.md (read committed file when plans disagree, "final" labels not load-bearing) + process.md (prior-phase "complete" needs re-verification) + config.md (reconcile against committed file) | Planning docs drift, especially across tactical/strategic pairs. Ground truth is the committed file. Read it, update the wrong plan(s), label intentional divergence inline. |

---

## Graduation Notes

Foundation tier currently empty in INDEX.md — Phase 1 has 9 phases of accumulated rules but the project is in pre-graduation state. The following rules have been re-applied successfully across ≥2 phases and are graduation candidates for the next pass:

- **Verify after rename/architecture swap** — phase01#2 → phase04#1 → phase09#1 (link sweep)
- **Validate at write-time** — phase03#1 (JSON) → phase05#1 (parser) → phase09#1 (markdown links)
- **Plan-vs-file reconciliation** — phase03#2 → phase04#1 → phase08 (architecture pitfall)
- **Smoke test with positive AND negative cases** — phase05#2 → phase06#1went
- **Get-Command-guarded inline fallback stubs** — phase05#7 → phase06#2design → phase08#4

These remain in Active for now (CF-21 keeps phase06/07/08 filenames stable until README re-link); a Foundation graduation pass is the next natural cycle.
