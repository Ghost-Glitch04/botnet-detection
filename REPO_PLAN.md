# Network Forensics Toolkit — Repo Blueprint

## Overview

PowerShell-based network forensics toolkit designed for botnet incident
response. Deployed via `git clone` onto Windows endpoints accessed through
SentinelOne or N-Able remote shells. All modules are standalone-capable
functions AND loadable via a single launcher script.

**Primary use case:** multi-machine botnet infections on workgroup networks
with limited RMM/EDR coverage, accessed via remote shell from beachhead
machines.

---

## Repo Structure

```
network-forensics/
├── Deploy.ps1                          # Launcher — dot-sources all modules, creates output dir
├── README.md                           # Repo overview, quick start, requirements
├── modules/
│   ├── _Shared.ps1                     # Authoritative helper library (dot-sourced first by Deploy.ps1)
│   ├── Invoke-BotnetTriage.ps1         # Module 1: Wide-shallow single-pass triage → High/Med/Low verdict
│   ├── Invoke-C2BeaconHunt.ps1         # Module 2: Deep multi-sample beacon detection + threat-intel enrichment
│   ├── Invoke-IOCSweep.ps1             # Module 3: IOC sweep across connections, DNS, tasks, hosts file
│   ├── Invoke-LateralMovementHunt.ps1  # Module 4: East-west traffic, admin shares, new accounts
│   └── Invoke-BaselineCapture.ps1      # Module 5: Snapshot connections, ports, services, autoruns
├── iocs/
│   ├── iocs_template.txt               # Blank IOC file with format documentation
│   └── .gitkeep                        # Preserve folder in repo (actual IOC files are .gitignored)
├── config/
│   ├── exclusions.json                 # Known-good process/port exclusions (configurable per engagement)
│   ├── triage-weights.json             # Risk scoring weights for Module 1 (Invoke-BotnetTriage)
│   └── scoring-weights.json            # Heuristic weight tuning for Module 2 (Invoke-C2BeaconHunt) scoring engine
├── docs/
│   ├── CHEATSHEET.md                   # Field quick-reference — commands, invocation examples, decision tree
│   ├── FINDINGS_TEMPLATE.md            # Findings report scaffold (markdown)
│   └── MODULE_REFERENCE.md             # Detailed parameter docs + output schema for each module
├── output/                             # .gitignored — runtime output lands here
│   └── .gitkeep
└── .gitignore
```

---

## Build Phases — Priority Order

> **Architecture note (2026-04-09):** Phase 1 was originally anchored on
> `Invoke-C2BeaconHunt` for maximum code reuse from the upstream network-dfir
> library. Re-evaluation determined that the first-responder workflow calls
> for a *wide shallow* triage tool before a *narrow deep* beacon hunter —
> operators need a fast "is this host worth investigating?" verdict across
> 10+ endpoints per engagement, not a slow deep-dive on one. The toolkit
> now ships **5 modules**, with `Invoke-BotnetTriage` as the Phase 1 anchor
> and `Invoke-C2BeaconHunt` as the Phase 2 escalation tool. See
> `PHASE1_PLAN.md` for the Phase 1 tactical plan.

### Phase 1: Scaffolding + Module 1 (Invoke-BotnetTriage)

**Files to create:**
- Repo structure (all directories + .gitkeep + .gitignore)
- `Deploy.ps1` — launcher script
- `modules/_Shared.ps1` — authoritative helpers (inlined stubs used by paste-path; full implementations for Phase 2+ live here)
- `modules/Invoke-BotnetTriage.ps1` — wide-shallow single-pass triage module, 4 phases × ~16 units, offline-capable
- `config/exclusions.json` — default known-good exclusions (RMM/AV, benign ports, private subnets)
- `config/triage-weights.json` — risk scoring weights for Invoke-BotnetTriage
- `.env.example` — Phase 2 API-key placeholders (unused in Phase 1, shipped for the contract)
- `config/config.example.json` — global defaults
- `README.md` — quick start
- `iocs/iocs_template.txt` — blank IOC file with format documentation
- `lessons_learned/INDEX.md` + `lessons_learned/ai/_overview.md` — lessons scaffold

**Design notes for Module 1 (Invoke-BotnetTriage):**
- **Offline-capable:** no API key dependencies, no network calls beyond local DNS cache reads — triage must work when the endpoint has no outbound connectivity.
- **Single-pass:** no sampling loop. One snapshot per data source, scored immediately.
- **8 collection units:** connections, listening ports, scheduled tasks, services, autoruns, DNS cache, hosts file, local accounts.
- **Verdict-first output:** console summary shows `High / Med / Low` counts + top 5 findings before the operator has to open a JSON file.
- **Config-driven:** reads `config/exclusions.json` for known-good filtering and `config/triage-weights.json` for scoring; falls back to hardcoded defaults if files are absent.
- **Standalone-capable:** if pasted into a remote shell without `Deploy.ps1`, inline fallback helpers activate and the module runs against `$env:TEMP`.
- **Launcher behavior unchanged:** `Deploy.ps1` dot-sources the module but does NOT auto-execute — the operator chooses when to invoke.

**Deploy.ps1 behavior (ships in Phase 1, applies to all phases):**
1. Detect script root (`$PSScriptRoot`)
2. Create `output/` if missing
3. Dot-source `modules/_Shared.ps1` first, then all `modules/Invoke-*.ps1`
4. Load `config/exclusions.json` into `$script:Exclusions` (available to all modules)
5. Load `config/triage-weights.json` into `$script:TriageWeights` (Phase 2 adds `config/scoring-weights.json` → `$script:ScoringWeights` alongside)
6. Print loaded module list + available commands
7. Does NOT auto-run anything — operator chooses what to invoke

**Standalone fallback pattern (every module must implement):**
```powershell
# If loaded via Deploy.ps1, config is already in $script:Exclusions
# If pasted standalone, detect and use built-in defaults
if (-not $script:Exclusions) {
    $configPath = Join-Path (Split-Path $PSScriptRoot -Parent) "config\exclusions.json"
    if (Test-Path $configPath) {
        $script:Exclusions = Get-Content $configPath -Raw | ConvertFrom-Json
    } else {
        # Hardcoded fallback — functional without any config files
        $script:Exclusions = @{ Processes = @(); Ports = @() }
    }
}
```

### Phase 2: Module 2 (Invoke-C2BeaconHunt)

**Purpose:** Deep multi-sample beacon detection for hosts that `Invoke-BotnetTriage` flagged as worth investigating. Uses periodicity analysis (coefficient of variation on inter-arrival deltas) + threat-intel enrichment (VirusTotal, AbuseIPDB, Scamalytics) + geo enrichment.

**Reuses from upstream network-dfir library (lift-as-is):** `Test-IsPrivateIP`, `Get-ProcessDetails`, connection harvest pattern, `Invoke-GeoEnrichment`, `Invoke-VirusTotalLookup`, `Invoke-AbuseIPDBLookup`, `Invoke-ScamalyticsLookup`, `Invoke-HeuristicScoring`, HTML dark-theme template, base64 export block.

**Parameters:** `-Samples <int=5>`, `-IntervalSeconds <int=15>`, `-IOCFile <string>`, `-SkipApiLookup`, `-OutputDir`, plus the standard `-DryRun` / `-DebugMode` / `-StopAfterPhase`.

**Output:** JSON + HTML (dark theme) + base64 for remote-shell exfil.

### Phase 3: Module 3 (Invoke-IOCSweep)

**Purpose:** Sweep multiple forensic data sources against a loaded IOC list.

**Data sources to sweep:**
- Active TCP connections (remote IPs)
- DNS client cache (resolved domains + IPs)
- Hosts file (`C:\Windows\System32\drivers\etc\hosts`) — attackers modify this for redirection
- Scheduled tasks — command lines containing IOC domains/IPs
- Startup entries (Run/RunOnce registry keys) — persistence mechanisms
- Services — binaries in suspicious paths or with IOC-matching command lines

**Parameters:**
- `-IOCFile` (mandatory) — path to IOC text file
- `-OutputDir` — defaults to repo `output/` or `$env:TEMP\BotnetForensics`
- `-SkipServices` — flag to skip service enumeration (slow on some endpoints)

**Output:** Console log + JSON with per-source match results.

### Phase 4: Module 4 (Invoke-LateralMovementHunt)

**Purpose:** Detect signs of lateral movement on the local machine.

**Units:**
- **East-west connections:** Established TCP connections where BOTH local and remote IPs are RFC1918. Flag SMB (445), RDP (3389), WinRM (5985/5986), WMI (135).
- **Admin share access:** Check for recent access to `C$`, `ADMIN$`, `IPC$` via security event logs (Event ID 5140/5145 if auditing enabled).
- **New/modified local accounts:** `Get-LocalUser` — flag accounts created or modified in last 7 days (configurable). Attackers commonly reset the local Administrator password — this unit would flag that.
- **RDP session history:** Registry key `HKCU:\Software\Microsoft\Terminal Server Client\Servers` for outbound RDP history. Event logs for inbound sessions.
- **Firewall rule changes:** `Get-NetFirewallRule` — flag rules created recently or rules that allow inbound on suspicious ports.

**Parameters:**
- `-DaysBack` — how far back to check account/rule changes (default: 7)
- `-OutputDir`

### Phase 5: Module 5 (Invoke-BaselineCapture)

**Purpose:** Snapshot the current state for delta comparison across time or across machines.

**Captures:**
- All established TCP connections (same format as Module 1 snapshot)
- All listening ports with owning process
- All running services (name, display name, path, start type, status)
- Startup entries (Run, RunOnce, Startup folder, scheduled tasks with triggers)
- Local user accounts (name, enabled, last logon, password last set)
- Network adapter config (IP, gateway, DNS servers — useful for DNS hijack detection)
- Installed software (from registry Uninstall keys)

**Output:** Single comprehensive JSON file. Designed so two captures from different machines or different times can be diff'd externally.

**Parameters:**
- `-OutputDir`
- `-Tag` — optional string appended to filename (e.g., machine name, case number)

### Phase 6: Documentation

**Files:**
- `docs/CHEATSHEET.md` — single-page field reference
  - Clone + deploy steps
  - One-liner invocations for each module
  - Decision tree: "What do I run first?" based on engagement type
  - IOC file format reminder
  - Common N-Able/SentinelOne shell gotchas

- `docs/FINDINGS_TEMPLATE.md` — report scaffold
  - Executive summary section
  - Affected hosts table
  - IOC table
  - Timeline of events
  - Remediation recommendations
  - Evidence appendix (reference JSON output paths)

- `docs/MODULE_REFERENCE.md` — technical parameter + output docs
  - Each module: purpose, all parameters with types/defaults, output schema (JSON structure), exit codes, example invocations

- `README.md` — repo landing page
  - What this is
  - Requirements (PowerShell 5.1+, Administrator recommended)
  - Quick start (clone, Deploy.ps1, run)
  - Module summary table
  - Link to CHEATSHEET.md for field use

---

## Scripting Standards Compliance

Every module MUST implement (per project scripting standards):

1. **Script header** — `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, `.NOTES`
2. **Error code reference** — documented at top of each function
3. **Unit structure** — labeled `#region` blocks with Purpose/Inputs/Outputs/Depends
4. **Write-Log helper** — consistent across all modules (defined once in Deploy.ps1, fallback in each module)
5. **Fail-fast validation** — inputs checked before work begins in each unit
6. **Performance timers** — per-unit and overall script stopwatches
7. **Unit lifecycle logging** — entry, exit, duration, error context
8. **$results = @() pattern** — no cross-closure piping (N-Able shell constraint)

---

## Config File Schemas

### config/exclusions.json
```json
{
    "Description": "Known-good processes and ports to exclude from analysis",
    "Processes": [
        "SentinelAgent",
        "SentinelServiceHost",
        "SentinelStaticEngine",
        "SentinelRemoteShellHost",
        "N-AbleAgent",
        "BASupSrvc",
        "BASupApp",
        "SophosFS",
        "SophosAgent",
        "SophosCleanM",
        "SophosFileScanner",
        "MsMpEng"
    ],
    "Ports": [
        7680
    ],
    "PrivateSubnets": [
        "10.0.0.0/8",
        "172.16.0.0/12",
        "192.168.0.0/16"
    ]
}
```

### config/triage-weights.json (Phase 1 — Invoke-BotnetTriage)
```json
{
    "Description": "Risk weights for Invoke-BotnetTriage (wide-shallow triage module)",
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
        "RecentlyCreated":    30,
        "RecentPasswordSet":  20,
        "NewAdminGroupMember":45
    },
    "Thresholds": {
        "High":   50,
        "Medium": 25
    }
}
```

### config/scoring-weights.json (Phase 2 — Invoke-C2BeaconHunt)
```json
{
    "Description": "Heuristic weights for Invoke-C2BeaconHunt scoring engine",
    "SuspiciousPath": 20,
    "NonStandardPort": 15,
    "HighBeaconRate": 30,
    "MediumBeaconRate": 15,
    "LOLBin": 25,
    "IOCMatch": 50,
    "PathAccessDenied": 10,
    "ProcessGone": 15,
    "Thresholds": {
        "HighRisk": 50,
        "MediumRisk": 25,
        "HighBeaconPercent": 80,
        "MediumBeaconPercent": 50
    }
}
```

---

## .gitignore

```
# Runtime output — never committed
output/*.json
output/*.log
output/*.csv

# Active IOC files — may contain engagement-specific sensitive data
iocs/*.txt
!iocs/iocs_template.txt

# OS artifacts
Thumbs.db
.DS_Store
desktop.ini
```

---

## N-Able / SentinelOne Shell Constraints (Build Rules)

These constraints apply to EVERY module:

1. **No cross-closure piping** — collect into `$results = @()` arrays inside loops, pipe completed array after
2. **No interactive prompts** — `Read-Host` is forbidden; all input via parameters
3. **No module imports** — `Import-Module` may fail in sandboxed shells; use inline functions only
4. **Console output is critical** — `Write-Log` must always write to `Write-Host` even if log file fails
5. **Graceful degradation** — if a WMI/CIM query fails (access denied in sandboxed shell), log the failure and continue; never abort the whole script because one data source is inaccessible
6. **File paths must use variables** — never hardcode user profile paths; always use `$env:TEMP`, `$env:COMPUTERNAME`, `$PSScriptRoot`
7. **Function-wrapped** — every module is a single function; paste the definition, then call it. No loose code at script scope.

---

## Deployment Workflow

### Full deployment (git available)
```powershell
cd $env:TEMP
git clone https://github.com/OWNER/network-forensics.git
cd network-forensics
. .\Deploy.ps1
```

### Manual deployment (no git — paste via shell)
```
1. Paste _Shared.ps1 content (helper library)
2. Paste desired module function(s) — e.g. Invoke-BotnetTriage
3. Call: Invoke-BotnetTriage                         # Phase 1 — fast wide-shallow triage
       # Invoke-C2BeaconHunt -Samples 3 -IntervalSeconds 15   # Phase 2 — deep escalation
```

### IOC file prep (before engagement)
```
1. Populate iocs/<engagement>.txt with known-bad indicators
2. Keep engagement IOC files local (gitignored) or distribute out-of-band
3. Reference: Invoke-BotnetTriage -IOCFile ".\iocs\<engagement>.txt"
```
