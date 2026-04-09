# Botnet Detection Toolset — Phase 1 Plan

## Context

**Why this exists.** The toolkit targets multi-machine botnet infections on
workgroup networks with limited RMM/EDR coverage. Operational reality: access
is via N-Able / SentinelOne remote shells from beachhead machines, file
transfer is often blocked, and endpoints have limited RMM/EDR coverage.
The toolkit must be droppable from a public GitHub repo, bootstrap into
working order in seconds, and produce evidence usable for both triage and
reporting.

**What already exists in design.** `REPO_PLAN.md` describes **5 modules**
(botnet triage, C2 beacon hunt, IOC sweep, lateral movement, baseline
capture), config-driven exclusions/weights, a standalone-paste fallback
pattern, and a `Deploy.ps1` launcher. Reusable building blocks from an
upstream network-dfir library will be lifted in for Phase 2+: threat
intel enrichment, geo enrichment, persistence checks, event log
correlation, HTML templating, base64 export, IOC matching, DNS cache
checks, and MITRE mapping patterns.

**Architecture re-evaluation (2026-04-09).** Phase 1 was originally
anchored on `Invoke-C2BeaconHunt` for maximum upstream code reuse. That
choice optimized for code reuse, not first-responder workflow. The
deployment reality — remote shell into 10+ workgroup endpoints per
engagement, constrained time per host — calls for a *wide shallow*
triage tool first, and a *narrow deep* beacon hunter as an escalation
path. Phase 1 now ships `Invoke-BotnetTriage`; `Invoke-C2BeaconHunt`
shifts to Phase 2.

**What this plan does.** Delivers a working Phase 1 — scaffolding, shared
helpers, `Deploy.ps1`, and a single production-ready module
(`Invoke-BotnetTriage`) — aligned with project scripting standards and
GitHub security standards. Modules 2–5 (`Invoke-C2BeaconHunt`,
`Invoke-IOCSweep`, `Invoke-LateralMovementHunt`, `Invoke-BaselineCapture`)
are explicitly out of scope for Phase 1.

**Intended outcome.** At the end of Phase 1:
`git clone` → `. .\Deploy.ps1` → `Invoke-BotnetTriage -IOCFile .\iocs\<engagement>.txt`
→ JSON in `output/` + console verdict summary (`3 HIGH / 7 MED / 12 LOW` + top 5 findings), ready to run across affected hosts in under 60 seconds per host.

---

## Deliverables — Phase 1 File List

All paths relative to repo root.

**Creation order (gitignore-first):**

| # | File | Purpose |
|---|------|---------|
| 1 | `.gitignore` | Must exist before any ignored file |
| 2 | `.env.example` | Committed credentials contract |
| 3 | `config/config.example.json` | Committed ops-values schema |
| 4 | `config/exclusions.json` | Committed known-good defaults |
| 5 | `config/triage-weights.json` | Committed heuristic weights for Invoke-BotnetTriage (Phase 2 adds `scoring-weights.json` for Invoke-C2BeaconHunt) |
| 6 | `iocs/.gitkeep` + `iocs/iocs_template.txt` | Preserve dir, document format |
| 7 | `output/.gitkeep` | Preserve dir, contents ignored |
| 8 | `modules/_Shared.ps1` | Helper library (authoritative implementations + Phase 2 stubs) |
| 9 | `modules/Invoke-BotnetTriage.ps1` | The Phase 1 module — wide-shallow single-pass triage |
| 10 | `Deploy.ps1` | Launcher |
| 11 | `README.md` | Quick-start + requirements |
| 12 | `lessons_learned/INDEX.md` + `ai/_overview.md` + `phase01_bootstrap.md` | Lessons scaffold |

**Never committed (gitignored):** `.env`, `config/config.local.json`,
`iocs/<engagement>.txt`, `output/*`, `lessons_learned/private_*.md`.

---

## Shared Helper Strategy — Hybrid

`modules/_Shared.ps1` is authoritative. Each module also embeds a minimal
inline stub of the helpers it needs, so it can be pasted raw into a remote
shell without `Deploy.ps1`.

**Rule:** if a helper is under ~30 lines and the module cannot function
without it, inline it. Otherwise it lives in `_Shared.ps1` with
graceful-degradation fallback.

| Helper | Location | Rationale |
|---|---|---|
| `Write-Log` | Inline stub + `_Shared.ps1` | Every module needs it; small |
| `Get-Secret` | Inline stub + `_Shared.ps1` | Every module needs it; small |
| `Test-IsPrivateIP` | Inline (lift from upstream network-dfir library) | ~10 lines |
| `Get-ProcessDetails` | Inline (lift from upstream network-dfir library) | Critical path, moderate size |
| `Resolve-Config` | Inline | Tiny glue to `$script:Exclusions` / `$script:TriageWeights` (Phase 2 will add `$script:ScoringWeights` alongside) |
| `Invoke-WithRetry` | `_Shared.ps1` only | Used only by API callers |
| `Import-DotEnv` | `_Shared.ps1` only | Deploy-time only |
| `Import-LocalConfig` | `_Shared.ps1` only | Deploy-time only |
| `Get-MaskedParams` | `_Shared.ps1` only | Deploy-time only |
| `Invoke-GeoEnrichment` | `_Shared.ps1` only (lifted) | Large, optional |
| `Invoke-VirusTotalLookup` | `_Shared.ps1` only (lifted) | Large, optional, needs secret |
| `Invoke-AbuseIPDBLookup` | `_Shared.ps1` only (lifted) | Large, optional, needs secret |
| `Invoke-ScamalyticsLookup` | `_Shared.ps1` only (lifted) | Large, optional, needs secret |
| HTML template block | `_Shared.ps1` only (`ConvertTo-HtmlReport`) | Large |
| Base64 export block | `_Shared.ps1` only (`Export-Base64Report`) | Moderate |

**Module preamble pattern:**
```powershell
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    # --- inline Write-Log stub ---
}
if (-not (Get-Command Get-Secret -ErrorAction SilentlyContinue)) {
    # --- inline Get-Secret stub ---
}
# For optional enrichers, detect and skip gracefully:
$HasThreatIntel = [bool](Get-Command Invoke-VirusTotalLookup -ErrorAction SilentlyContinue)
```

---

## Deploy.ps1 Structure

Units in strict order (each a `#region` block per scripting standards):

1. **U-Init** — `$ErrorActionPreference='Stop'`, overall stopwatch, `$PSScriptRoot`, param block (`-DebugMode`, `-DryRun`, `-OutputDir`).
2. **U-Logging** — Initialize `Write-Log` with file target `output/deploy_<timestamp>.log`. Emit `SCRIPT_START`.
3. **U-EnvSnapshot** — Emit `ENV_SNAPSHOT` (PS version, OS, host, user, elevation, cwd, script path).
4. **U-ImportDotEnv** — `Import-DotEnv $PSScriptRoot\.env`. Missing file → `CONFIG_MISSING` (WARN, not FATAL). Standalone-paste path still works.
5. **U-ImportLocalConfig** — Merge `config/config.example.json` ← `config/config.local.json` (local wins).
6. **U-MaskedParams** — Emit `PARAMS` via `Get-MaskedParams` using canonical pattern list (`key`, `secret`, `password`, `token`, `credential`, `pwd`, `apikey`, `auth`, `bearer`, `conn_str`, `connection_string`, `certificate`, `pat`, `sas`).
7. **U-OutputDir** — Create `output/` if missing (honor `-DryRun`).
8. **U-DotSourceModules** — `_Shared.ps1` first, then `modules/Invoke-*.ps1`. Per-file `UNIT_FAILED` on error but continue.
9. **U-LoadConfig** — Populate `$script:Exclusions` and `$script:TriageWeights` from `config/exclusions.json` and `config/triage-weights.json`. Hardcoded fallbacks when files absent. (Phase 2 will add `$script:ScoringWeights` from `config/scoring-weights.json`.)
10. **U-Announce** — Print available commands (`Get-Command Invoke-* | Where Source -eq ...`), final status (`FULL_SUCCESS` / `PARTIAL_SUCCESS`).

Bootstrap sequence matches the project GitHub security standards:
args → logging → DotEnv → LocalConfig → masked PARAMS → dot-source → announce.

**Exit codes:** 0 success, 10 config missing (non-fatal → continue as 0),
20 module dot-source failure, 99 unhandled.

---

## Invoke-BotnetTriage — Phase/Unit Breakdown

**Parameters:** `-OutputDir <string>`, `-IOCFile <string>` (optional),
`-ExclusionsFile <string>`, `-WeightsFile <string>`,
`-DaysBackForAccounts <int=7>`, `-DryRun`, `-DebugMode`,
`-StopAfterPhase <Preflight|Collection|Processing|Output>`.

**No API-key parameters in Phase 1.** Triage is explicitly offline-capable;
VirusTotal / AbuseIPDB / Scamalytics enrichment lives in
`Invoke-C2BeaconHunt` (Phase 2).

**Exit codes:** 0 success, 10 input error, 11 malformed input,
20 processing error, 40 verification failure, 99 unhandled. No 30
(connection) since no network calls; no 50 (retry exhausted) since
no retries.

### Phase A — PREFLIGHT
- **U-ParamValidate** — fail-fast: `IOCFile` readable if specified, `OutputDir` writable, admin token check (warn if not elevated — some data sources degrade without it). Exit 10 on failure.
- **U-LoadConfig** — load `exclusions.json` + `triage-weights.json`; if either missing, inline hardcoded defaults and log `configSource=inline-fallback`. Populate `$script:Exclusions` and `$script:TriageWeights`.
- **U-LoadIOCs** — if `-IOCFile` provided, parse (one indicator per line, `#` comments) into a hashset. Soft-fail (warn + continue) if absent.
- **Gate:** `-StopAfterPhase Preflight` exits 0 with `PHASE_GATE`.

### Phase B — COLLECTION (single-pass, no sampling loop)
Each unit is one `Get-*` + enrichment, writes to its own keyed section in `$script:triageData`. No cross-unit coupling. If one unit fails (e.g. access denied on CIM) it logs `UNIT_FAILED` and continues — the whole triage does not abort on a single data-source failure.

- **U-ConnectionsSnapshot** — `Get-NetTCPConnection -State Established` + inline `Get-ProcessDetails`. Flag private→public on non-browser process; process path in `%TEMP%`, `%APPDATA%`, `ProgramData`.
- **U-ListeningPorts** — `Get-NetTCPConnection -State Listen`. Flag high ports (>49152) owned by non-standard processes; listening on `0.0.0.0` for non-server procs.
- **U-ScheduledTasks** — `Get-ScheduledTask` + `Get-ScheduledTaskInfo`. Flag author not Microsoft/SYSTEM; action path in user-writable dirs; LOLBin in args (`powershell -enc`, `rundll32`, `regsvr32`, `mshta`).
- **U-Services** — `Get-CimInstance Win32_Service`. Flag `PathName` in user-writable dirs; unsigned binary (best-effort `Get-AuthenticodeSignature`); service name pattern anomaly.
- **U-Autoruns** — Registry `HKLM/HKCU\...\Run`, `...\RunOnce`, Startup folders. Same path / LOLBin rules as tasks.
- **U-DnsCache** — `Get-DnsClientCache`. Flag entry matches IOC; entry is raw IP; suspicious TLD (optional, config-driven).
- **U-HostsFile** — `Get-Content C:\Windows\System32\drivers\etc\hosts`. Any non-default non-comment entry is a flag (default hosts file has none).
- **U-LocalAccounts** — `Get-LocalUser`, `Get-LocalGroupMember Administrators`. Flag accounts created or password set within `$DaysBackForAccounts`; new Administrators group member.
- **Gate:** `-StopAfterPhase Collection`.

### Phase C — PROCESSING
- **U-ApplyExclusions** — strip known-good processes / ports from each collected section before scoring (`$script:Exclusions.Processes`, `.Ports`, `.TrustedSigners`).
- **U-ScoreFindings** — apply per-category weights from `$script:TriageWeights`; produce numeric risk score per finding.
- **U-CorrelateIOCs** — if IOCs loaded, mark any finding whose connection / DNS / task / service matches. IOC match is a score *multiplier*, not a separate signal.
- **U-ClassifyRisk** — bucket each category into High / Medium / Low based on weight thresholds (`$script:TriageWeights.Thresholds.High` / `.Medium`).
- **Gate:** `-StopAfterPhase Processing`.

### Phase D — OUTPUT
- **U-WriteJson** — full structured findings → `output/BotnetTriage_<COMPUTERNAME>_<timestamp>.json`. Honor `-DryRun` with `[DRY-RUN]` logs.
- **U-WriteSummary** — terse console verdict: top-line counts (`3 HIGH / 7 MED / 12 LOW`) + top 5 highest-scored findings with one-line justification each. Web-shell friendly fixed-width format.
- **U-VerifyArtifacts** — `Verify-FileExists`, non-empty, required top-level keys present (`meta`, `verdict`, `findings`, `errors`) → `VERIFY_OK` or `VERIFY_FAILED` exit 40.

**Reuse from upstream network-dfir library (inline stubs only for Phase 1):**
- `Test-IsPrivateIP` (inlined, ~10 lines)
- `Get-ProcessDetails` (inlined, ~25 lines)

**Phase 2 helpers shipped as empty stubs in `_Shared.ps1` for later fleshing-out:**
- `Invoke-GeoEnrichment`, `Invoke-VirusTotalLookup`, `Invoke-AbuseIPDBLookup`, `Invoke-ScamalyticsLookup`, `Invoke-HeuristicScoring`, `ConvertTo-HtmlReport`, `Export-Base64Report`

**Build new (Phase 1 original work):** 8 collection units with per-source scoring, single-pass architecture (no sampling loop), `Resolve-Config` glue, `-StopAfterPhase` gating, `Write-Log` with DEBUG-to-file-only, `Verify-*` output units.

### JSON Output Schema

```jsonc
{
  "meta": {
    "module": "Invoke-BotnetTriage",
    "version": "1.0.0",
    "hostname": "...",
    "timestamp": "ISO8601",
    "durationSeconds": 42.3,
    "exclusionsLoaded": true,
    "iocsLoaded": false,
    "configSource": "file"  // or "inline-fallback"
  },
  "verdict": {
    "high": 3,
    "medium": 7,
    "low": 12,
    "topFindings": [ /* top 5 highest-scored */ ]
  },
  "findings": {
    "connections":    { "count": N, "items": [ ... ] },
    "listeningPorts": { "count": N, "items": [ ... ] },
    "scheduledTasks": { "count": N, "items": [ ... ] },
    "services":       { "count": N, "items": [ ... ] },
    "autoruns":       { "count": N, "items": [ ... ] },
    "dnsCache":       { "count": N, "items": [ ... ] },
    "hostsFile":      { "count": N, "items": [ ... ] },
    "localAccounts":  { "count": N, "items": [ ... ] }
  },
  "errors": [ /* UNIT_FAILED entries — access denied, etc. */ ]
}
```

No HTML, no base64 in Phase 1. Both defer to Phase 2 alongside
`Invoke-C2BeaconHunt`, which reuses the upstream network-dfir HTML
template and base64 exporter.

---

## Config Schemas

### `.env.example` (committed)
```
# ── VirusTotal ──
VT_API_KEY=

# ── AbuseIPDB ──
ABUSEIPDB_API_KEY=

# ── Scamalytics ──
SCAMALYTICS_USERNAME=
SCAMALYTICS_API_KEY=

# ── ip-api.com (free tier, no key required) ──
# IPAPI_KEY=
```

### `config/config.example.json` (committed)
```json
{
  "DefaultSamples": 5,
  "DefaultIntervalSeconds": 15,
  "DefaultOutputDir": "output",
  "ApiRateLimitSeconds": { "VirusTotal": 15, "AbuseIPDB": 1, "Scamalytics": 2 },
  "PartialSuccessFailureThreshold": 0.25,
  "RetryAttempts": 3,
  "RetryInitialDelayMs": 1000
}
```

### `config/exclusions.json` (extensions beyond REPO_PLAN.md)
```json
{
  "Processes": ["SentinelAgent", "SentinelServiceHost", "SentinelStaticEngine",
                "SentinelRemoteShellHost", "N-AbleAgent", "BASupSrvc", "BASupApp",
                "SophosFS", "SophosAgent", "SophosCleanM", "SophosFileScanner", "MsMpEng"],
  "Ports": [7680],
  "LocalOnlyPorts": [135, 139, 445, 5355, 5357],
  "PrivateSubnets": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"],
  "TrustedSigners": ["Microsoft Corporation", "Microsoft Windows",
                     "SentinelOne, Inc.", "Sophos Ltd", "N-able Technologies, Inc."],
  "BeaconWhitelist": [
    { "Process": "svchost", "RemotePort": 443, "Reason": "Windows Update" }
  ]
}
```

### `config/triage-weights.json` (Phase 1 — Invoke-BotnetTriage)
```json
{
  "Description": "Risk weights for Invoke-BotnetTriage",
  "Connections": {
    "PrivateToPublicNonBrowser": 25,
    "ProcessInTempOrAppData":    30,
    "IOCMatchMultiplier":         2.0
  },
  "ListeningPorts": {
    "HighPortNonServerProcess": 15,
    "ListeningOnAllInterfaces": 10
  },
  "ScheduledTasks": {
    "NonMicrosoftAuthor":     10,
    "UserWritableActionPath": 25,
    "LOLBinInArgs":           35
  },
  "Services": {
    "UserWritablePath": 30,
    "Unsigned":         20,
    "SuspiciousName":   15
  },
  "Autoruns": {
    "UserWritablePath":  25,
    "LOLBinInCommand":   35
  },
  "DnsCache": {
    "RawIPEntry":         10,
    "IOCMatchMultiplier":  2.0
  },
  "HostsFile": {
    "AnyNonDefaultEntry": 40
  },
  "LocalAccounts": {
    "RecentlyCreated":     30,
    "RecentPasswordSet":   20,
    "NewAdminGroupMember": 45
  },
  "Thresholds": {
    "High":   50,
    "Medium": 25
  }
}
```

Weights are tunable per engagement. Phase 2 will add `config/scoring-weights.json` for `Invoke-C2BeaconHunt` with beacon-periodicity-specific fields (`HighBeaconRate`, `MediumBeaconRate`, `BeaconCoefficientOfVariationThreshold`, `MinSamplesForBeaconDetection`, etc.) — that schema is documented in Phase 2's plan.

### `.gitignore` (final)
```
# Secrets & local config — MUST be first
.env
.env.*
!.env.example
config/config.local.json
config/*.local.json

# Runtime output
output/*
!output/.gitkeep
*.log
*.b64.txt

# IOC files (may contain engagement-sensitive data)
iocs/*
!iocs/.gitkeep
!iocs/iocs_template.txt

# Lessons learned private notes
lessons_learned/private_*.md

# PowerShell artifacts
*.ps1xml.bak

# OS artifacts
Thumbs.db
.DS_Store
desktop.ini
$RECYCLE.BIN/

# Editor
.vscode/
.idea/
*.swp
*~
```

---

## Lessons Learned Bootstrap

Per the `lessons-learned` skill — create scaffold so future sessions run the
lookup protocol before writing code.

**Files to create:**
- `lessons_learned/INDEX.md` — three tiers (Active / Foundation / Reference), empty rows, Quick Reference table
- `lessons_learned/ai/_overview.md` — inventory of AI files with topic keywords; empty concern maps table
- `lessons_learned/ai/powershell.md` — seeded with any lessons surfaced during Phase 1 implementation
- `lessons_learned/phase01_bootstrap.md` — phase file for this initial build (Applied Lessons table empty for now, filled at reflection)

---

## Verification Plan (End-to-End)

**Dry-run tier:**
1. `. .\Deploy.ps1 -DryRun -DebugMode` → verify `SCRIPT_START`, `ENV_SNAPSHOT`, masked `PARAMS`, module dot-source, announcement, exit 0; no files written.
2. `Invoke-BotnetTriage -DryRun -StopAfterPhase Preflight` → exits cleanly after preflight gate, no files.
3. Same with `-StopAfterPhase Collection` — verifies all 8 collection units run, `UNIT_START`/`UNIT_END` emitted per unit, still no output files.
4. Same with `-StopAfterPhase Processing` — verifies exclusions / scoring / IOC correlation / classification all run.

**Real-run tier (isolated test VM):**
5. Known-clean lab VM, no `-IOCFile` → `Invoke-BotnetTriage` → JSON in `output/`, `verdict.high == 0` (or documented false positives only), console summary matches JSON, `VERIFY_OK` emitted, exit 0.
6. Create mock `iocs/test_iocs.txt` (loopback + a public IP under operator control, plus a DNS entry you know is in the host's DNS cache).
7. Same VM with `-IOCFile .\iocs\test_iocs.txt` → JSON shows IOC match in `findings.dnsCache.items`, verdict bumps accordingly, `meta.iocsLoaded == true`.

**Artifact tier:**
8. Manually inspect `output/BotnetTriage_<host>_<ts>.json`: all 8 `findings.*` sections present, `meta.configSource` reflects whether config files were used or inline-fallback, `errors` array populated if any CIM call was access-denied.
9. Log file grep: `SCRIPT_START`, `PHASE_END`, `VERIFY_OK`, terminal status prefix, no leaked credentials anywhere in the log.
10. Exit code assertion: `$LASTEXITCODE -in @(0,11)`.

**Git hygiene tier:**
11. `git status --ignored --untracked-files=all` — confirm `.env`, `config/config.local.json`, `output/*`, `iocs/test_iocs.txt` all ignored; `.claude/skills/**` still trackable.
12. Before commit: grep staged content for any non-empty API key values, identifying names, internal IPs, or user-profile paths.
13. Enable GitHub secret scanning + push protection on the repo (Settings → Code security).

**Standalone-paste tier (load-bearing):**
14. Paste `Invoke-BotnetTriage.ps1` into a bare pwsh session with no `Deploy.ps1`, no `config/` directory, no `.env` file. Function defines, runs with inline fallback config, produces JSON to `$env:TEMP`, logs `configSource: inline-fallback`. This validates the "paste into remote shell when `git clone` is blocked" path — the critical deployment mode for N-Able / SentinelOne engagements.

**Cross-host tier (production use):**
15. Run on one known-good lab machine → confirm baseline (no `high` verdict findings, or only documented false positives).
16. Run on a known-infected host → compare output; expected `high` verdict findings in relevant categories.
17. Diff JSONs from multiple affected hosts side by side — schemas identical, differences are signal. Formal aggregation waits for Phase 5 (`Invoke-BaselineCapture`) + external aggregator.

---

## Scope Boundaries — OUT of Phase 1

- Modules 2–5 (`Invoke-C2BeaconHunt`, `Invoke-IOCSweep`, `Invoke-LateralMovementHunt`, `Invoke-BaselineCapture`). Phase 2 helpers (`Invoke-GeoEnrichment`, `Invoke-VirusTotalLookup`, `Invoke-AbuseIPDBLookup`, `Invoke-ScamalyticsLookup`, `Invoke-HeuristicScoring`, `ConvertTo-HtmlReport`, `Export-Base64Report`) ship as empty stubs in `_Shared.ps1` so dot-sourcing succeeds; they are fleshed out in Phase 2.
- API-based threat intel enrichment of any kind — Phase 1 triage is strictly offline-capable. `.env.example` ships for the Phase 2 contract, but Phase 1 never reads it.
- HTML report output, base64 export for remote-shell exfil — both ship in Phase 2 alongside `Invoke-C2BeaconHunt`.
- Multi-sample connection analysis, beacon periodicity detection (CV engine) — core of `Invoke-C2BeaconHunt`, Phase 2.
- `Aggregate-Findings.ps1` cross-machine correlator.
- `docs/CHEATSHEET.md`, `docs/FINDINGS_TEMPLATE.md`, `docs/MODULE_REFERENCE.md` (beyond minimal README).
- Pre-commit hooks (gitleaks / detect-secrets / trufflehog) — recommended but deferred.
- GitHub Actions CI.
- Signed PowerShell module manifest (`.psd1` / `.psm1`).
- Pester tests.
- Automated IOC feed ingestion (MISP, OTX, URLhaus).
- Remediation automation — Phase 1 is detect-only.
