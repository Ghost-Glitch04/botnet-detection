# Network Forensics Toolkit — Botnet Detection

PowerShell-based first-responder triage for suspected botnet infections on
workgroup Windows endpoints. Designed to be deployed via `git clone` (or
pasted directly) into a remote shell session — SentinelOne, N-Able, or any
other RMM that gives you a `pwsh` prompt — and produce a prioritized
**High / Medium / Low** verdict in 30–60 seconds per host.

> **Status:** Phase 1 complete — `Invoke-BotnetTriage` ships and is
> verification-tested. Modules 2–5 are planned (see [REPO_PLAN.md](REPO_PLAN.md)).

---

## Quick Start

### Path A — `git clone` (preferred)

```powershell
git clone https://github.com/<owner>/botnet-detection.git
cd botnet-detection
. .\Deploy.ps1
Invoke-BotnetTriage
```

What you get on the console:

```
================================================================
  BOTNET TRIAGE VERDICT: <HOSTNAME>
================================================================
  HIGH:    3
  MEDIUM:  7
  LOW:    12
----------------------------------------------------------------
  TOP 5 FINDINGS (by score):
  1. [High  ] score=70  Connections - PrivateToPublicNonBrowser,ProcessInTempOrAppData
  2. [High  ] score=55  Services    - UserWritablePath,Unsigned
  ...
================================================================
  JSON artifact: .\output\BotnetTriage_<HOST>_<TIMESTAMP>.json
```

A structured JSON artifact lands in [output/](output/) for evidence
preservation. The runtime log lands beside it as `triage_<HOST>_<TIMESTAMP>.log`.

### Path B — IOC correlation

If you have indicators from a prior incident (IPs, CIDRs, domains, URLs):

```powershell
# Copy iocs/iocs_template.txt to a new engagement-specific file
Copy-Item .\iocs\iocs_template.txt .\iocs\acme_2026-04.txt
# Edit the new file — one indicator per line, # for comments
notepad .\iocs\acme_2026-04.txt

Invoke-BotnetTriage -IOCFile .\iocs\acme_2026-04.txt
```

IOC matches act as a **score multiplier**, not a separate finding category —
the heuristics still flag suspicious state on their own, and a matching IOC
amplifies the score on top of that. A row that matches an IOC but otherwise
looks benign is still retained in the output (CF-16 is tracking the Risk-bucket
floor for those).

Engagement-specific IOC files live in [iocs/](iocs/) and are
**gitignored** — only the template ships in the repo.

### Path C — Standalone paste (no `git clone`)

When `git clone` is blocked but you have a `pwsh` prompt:

```powershell
# Paste the entire content of modules/Invoke-BotnetTriage.ps1 into the shell.
# It dot-sources its own inline fallback helpers and runs against $env:TEMP.
Invoke-BotnetTriage
```

The module embeds inline fallback stubs for every helper it needs. When
no `_Shared.ps1` is loaded, configuration falls back to hardcoded defaults
and the JSON artifact lands in `$env:TEMP\BotnetTriage_*.json`. The JSON's
`meta.configSource` field will read `inline-fallback` so you can tell at a
glance which path was used.

This path is verification-tested (Tier 5).

---

## Requirements

| Component   | Minimum                | Notes |
|-------------|------------------------|-------|
| OS          | Windows 10 / Server 2016 | Earlier may work but is untested |
| PowerShell  | 5.1 (built-in) or 7.x  | Validated on 7.6 |
| Privileges  | Standard user runs     | Some data sources (CIM, accounts) return partial results without admin — `NOT_ELEVATED` warning is logged |
| Network     | None required          | Triage is offline; Phase 2 will add optional API enrichment |
| Disk        | <100 KB script + ~50 KB JSON per run | Output dir grows with engagement size |

No external modules, no Pester dependency, no Internet during execution.

---

## Modules

| # | Module | Phase | Purpose |
|---|--------|-------|---------|
| 1 | [`Invoke-BotnetTriage`](modules/Invoke-BotnetTriage.ps1) | **1 — Shipped** | Wide-shallow single-pass sweep across 8 surfaces (connections, listening ports, scheduled tasks, services, autoruns, DNS cache, hosts file, local accounts) → High/Med/Low verdict |
| 2 | `Invoke-C2BeaconHunt` | 2 — Planned | Deep multi-sample beacon detection (periodicity / coefficient-of-variation) + threat-intel enrichment (VirusTotal, AbuseIPDB, Scamalytics, geo) — escalation tool for hosts Module 1 flags |
| 3 | `Invoke-IOCSweep` | 3 — Planned | Bulk IOC sweep across connections, DNS, scheduled tasks, services, hosts file |
| 4 | `Invoke-LateralMovementHunt` | 4 — Planned | East-west traffic, admin-share access, new accounts, RDP history, firewall delta |
| 5 | `Invoke-BaselineCapture` | 5 — Planned | Snapshot for cross-host / cross-time comparison |

See [REPO_PLAN.md](REPO_PLAN.md) for the full architecture and
[PHASE1_PLAN.md](PHASE1_PLAN.md) for the tactical plan that built Phase 1.

---

## `Invoke-BotnetTriage` Reference

### Parameters

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `-OutputDir` | `..\output` relative to module | Where the JSON + log land |
| `-IOCFile` | (none) | Optional indicator file — see [iocs/iocs_template.txt](iocs/iocs_template.txt) for format |
| `-ExclusionsFile` | `..\config\exclusions.json` | Known-good processes / ports / signers |
| `-WeightsFile` | `..\config\triage-weights.json` | Per-flag risk weights + verdict thresholds |
| `-DaysBackForAccounts` | `7` | Look-back window for "recent" account activity |
| `-StopAfterPhase` | `None` | Phase gate: `Preflight`, `Collection`, `Processing`, `Output`, or `None` |
| `-DryRun` | off | Logs would-be writes with `[DRY-RUN]` prefix; no files created |
| `-DebugMode` | off | Promote DEBUG log entries to console |

### Exit codes

| Code | Meaning |
|------|---------|
| 0  | Success (or clean phase-gate exit) |
| 10 | Input / config error (e.g. unreadable IOC file, output dir denied) |
| 11 | Malformed input (JSON parse failure beyond fallback) |
| 20 | Processing error (currently not used — units fault-tolerate individually) |
| 40 | Output verification failed (JSON missing, empty, malformed) |
| 99 | Unhandled exception |

### Output schema (top level)

```jsonc
{
  "meta":     { "module", "version", "hostname", "timestamp", "durationSeconds",
                "exclusionsLoaded", "iocsLoaded", "configSource" },
  "verdict":  { "high", "medium", "low", "topFindings": [...] },
  "findings": {
    "connections":     { "count", "items" },
    "listeningPorts":  { "count", "items" },
    "scheduledTasks":  { "count", "items" },
    "services":        { "count", "items" },
    "autoruns":        { "count", "items" },
    "dnsCache":        { "count", "items" },
    "hostsFile":       { "count", "items" },
    "localAccounts":   { "count", "items" }
  },
  "errors":   [ /* per-unit failures, e.g. CIM access denied */ ]
}
```

Each finding item carries `Flags`, `Score`, `IOCMatch`, and `Risk`
(`High`/`Medium`/`Low`) so the JSON is enough to reconstruct the verdict
without re-running the tool.

---

## Configuration

| File | Purpose | Tracked? |
|------|---------|----------|
| [config/exclusions.json](config/exclusions.json) | RMM/AV processes, benign ports, trusted signers, private subnets | yes |
| [config/triage-weights.json](config/triage-weights.json) | Per-flag risk weights and `High` / `Medium` thresholds | yes |
| [config/config.example.json](config/config.example.json) | Global defaults template | yes |
| `config/config.local.json` | Per-host overrides | **gitignored** |
| [.env.example](.env.example) | API-key contract for Phase 2 | yes |
| `.env` | Real API keys for Phase 2 | **gitignored** |

`Invoke-BotnetTriage` falls back to hardcoded defaults if any of the JSON
config files are missing. The fallback path is what the standalone-paste
test (Tier 5) exercises — `meta.configSource` in the output JSON tells you
which was used.

To tune for an engagement: copy [config/config.example.json](config/config.example.json)
to `config/config.local.json` and edit. The local file is gitignored so
engagement-specific knobs never leak upstream.

---

## Verification

Phase 1 verification follows a tiered plan documented in
[lessons_learned/phase08_verification_tiers.md](lessons_learned/phase08_verification_tiers.md).
All five executable tiers pass on the dev workstation:

| Tier | Test | Status |
|------|------|--------|
| 1   | Dry-run end-to-end (`-DryRun -DebugMode`) | PASS |
| 1a  | Phase gates (`-StopAfterPhase` × Preflight/Collection/Processing) | PASS |
| 2   | Real run, no IOCs, lab host | PASS |
| 2a  | Real run with mock IOC file | PASS |
| 3   | JSON artifact schema inspection | PASS |
| 4   | `git status --ignored --untracked-files=all` privacy check | PASS |
| 5   | Standalone-paste from `$env:TEMP` in fresh `pwsh -NoProfile` child | PASS |
| 6   | Cross-host diff | DEFERRED (needs ≥2 hosts) |

Tier scripts live in [output/](output/) (gitignored). Re-run any tier with:

```powershell
pwsh -NoProfile -File .\output\_tier1_dryrun.ps1
pwsh -NoProfile -File .\output\_tier1a_gates.ps1
pwsh -NoProfile -File .\output\_tier2_realrun.ps1
pwsh -NoProfile -File .\output\_tier2a_realrun_iocs.ps1
pwsh -NoProfile -File .\output\_tier5_standalone.ps1
```

---

## Repo Layout

```
botnet-detection/
├── Deploy.ps1                          # Bootstrap launcher (9 units)
├── README.md                           # This file
├── REPO_PLAN.md                        # Strategic 5-module architecture
├── PHASE1_PLAN.md                      # Phase 1 tactical plan
├── modules/
│   ├── _Shared.ps1                     # Authoritative helper library
│   └── Invoke-BotnetTriage.ps1         # Phase 1 module (4 phases × 18 units)
├── config/
│   ├── exclusions.json
│   ├── triage-weights.json
│   └── config.example.json
├── iocs/
│   ├── iocs_template.txt               # Format documentation
│   └── README.md                       # IOC file conventions
├── output/                             # gitignored — JSON + logs land here
├── lessons_learned/
│   ├── INDEX.md                        # Cross-phase rules index
│   └── phaseNN_*.md                    # Per-phase reflections
├── .env.example
└── .gitignore
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Invoke-BotnetTriage : The term ... is not recognized` after dot-sourcing Deploy.ps1 | Dot-source ran in a function scope, not script scope | Run `. .\Deploy.ps1` at the prompt, not from inside another function |
| `WARN: NOT_ELEVATED` followed by `LOCAL_USERS_UNAVAILABLE` or partial CIM results | Standard-user session | Re-run from an elevated `pwsh` prompt |
| `UNIT_FAILED: U-ScheduledTasks ... 'Execute' cannot be found` | Pre-Phase-8 build with the StrictMode CIM-polymorphism bug | `git pull` — fixed in the Phase 8 verification pass |
| `IOC_CORRELATED: 0 finding(s)` despite a known IOC being in the live DNS cache | Pre-Phase-8 build with the cross-stage filter bug | `git pull` — fixed in the Phase 8 verification pass |
| Standalone paste fails with `Invoke-PhaseGate : ... not recognized` | Pre-Phase-8 build missing inline phase-gate stubs | `git pull` — fixed in the Phase 8 verification pass |

---

## Project Documents

- [REPO_PLAN.md](REPO_PLAN.md) — strategic 5-module architecture
- [PHASE1_PLAN.md](PHASE1_PLAN.md) — Phase 1 tactical plan
- [lessons_learned/INDEX.md](lessons_learned/INDEX.md) — cross-phase lessons
- [lessons_learned/phase06_invoke_triage_build.md](lessons_learned/phase06_invoke_triage_build.md) — module build reflection
- [lessons_learned/phase07_deploy_launcher.md](lessons_learned/phase07_deploy_launcher.md) — launcher build reflection
- [lessons_learned/phase08_verification_tiers.md](lessons_learned/phase08_verification_tiers.md) — verification reflection
- [iocs/README.md](iocs/README.md) — IOC file conventions

---

## License

See [LICENSE](LICENSE).
