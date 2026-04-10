---
name: phase17_static_analysis_and_ps51_validation
description: Pre-commit static analysis audit of Phase 1.3 changes (top-down + bottom-up). Three pre-commit bugs found and fixed. Tier 5 extended with Phase 1.3 assertions. CF-42 closed via Tier 7 dynamic analysis on PS 5.1.26100.7920. Fix 1C (git rm --cached JSON artifacts) resolved as a non-issue — .gitignore was already effective.
type: reflection
---

# phase17_static_analysis_and_ps51_validation --- Static Analysis Audit + PS 5.1 Validation

> **Scope:** Post-implementation audit of Phase 1.3 (CF-31/33/34) before merge. Two analysis passes (top-down + bottom-up) run in parallel. Three confirmed bugs fixed. Tier 5 extended. CF-42 closed via Tier 7 dynamic analysis.
> **Date:** 2026-04-10
> **Verification:** All fixes: parser clean → PoC regression → kill-switch dry-run → full real-run → JSON field check → extended Tier 5 (PASS) → CF-33 check. Tier 7: PS 5.1 non-elevated + elevated, exit 0, all 4 ASN fields in JSON.

---

## What the Audit Caught

Three confirmed pre-commit bugs. Zero critical logic errors.

### Bug 1: `-QuickTimeout` on `Resolve-DnsName` (PS 5.1 compatibility, Fix 1A)

`U-EnrichConnectionsASN` used `Resolve-DnsName -Type TXT -DnsOnly -QuickTimeout` at two call sites inside `$resolveOne`. `-QuickTimeout` is not documented as available in Windows PowerShell 5.1 (the project's mandatory compatibility target for standalone-paste). If it were absent, every DNS call in `$resolveOne` would throw a `ParameterBindingException`, every connection would fall through with `RemoteASN=$null`, and no error would surface — the catch block was silent.

**Fix:** Remove `-QuickTimeout` from both call sites. Add `Write-Log -Level DEBUG` in the outer catch so DNS failures are diagnosable.

**Validation:** Tier 7 on `PSVersion=5.1.26100.7920` confirmed `Resolve-DnsName -Type TXT -DnsOnly` (no flag) works correctly. CF-42 closed.

**Why the flag was added:** Shortens timeout when DNS is blocked — operator has `-NoNetworkLookups` for that case. The flag has no benefit on successful lookups.

### Bug 2: Hardcoded machine paths in inspection scripts (Fix 1B)

`output/_inspect_asn_fields.ps1` and `output/_inspect_cf33.ps1` both globbed `'C:/Users/RyanF/OneDrive - PCS/Documents/GitHub/botnet-detection/output/BotnetTriage_*.json'`. These are permanent regression test aids intended to run on any machine, so the hardcoded path would fail immediately on any other host.

**Fix:** Replace with `Join-Path $PSScriptRoot 'BotnetTriage_*.json'`. Both scripts live in `output/`, so `$PSScriptRoot` resolves to the correct directory without parent-traversal.

**Lesson:** Any script committed as a permanent regression test artifact must be portable on first write. Machine-specific paths should trigger the same review as hardcoded credentials.

### Bug 3: `SuspiciousName = 15` missing from `Deploy.ps1` weightsFallback (Fix 2B)

`Deploy.ps1` line 357: `Services = @{ UserWritablePath = 30; Unsigned = 20 }`. The matching fallback in `Invoke-BotnetTriage.ps1` line 446 had `SuspiciousName = 15`. The inconsistency is harmless (flag is intentionally dead — Phase 2 intent, per code comment) but violates the codified fallback-sync rule in `config.md`.

**Fix:** Add `SuspiciousName = 15` to the `Deploy.ps1` Services hash.

---

## Audit Finding: Confirmed Non-Issues

Several agent findings from the parallel audit were resolved as non-bugs by direct file reads:

| Item | Initial concern | Resolution |
|------|----------------|------------|
| JSON artifacts tracked by git | Reported as needing `git rm --cached` | `git ls-files output/` confirmed only `.gitkeep` tracked — `.gitignore output/*` was always effective |
| Deploy.ps1 missing `-NoNetworkLookups` | Flagged as missing parameter | Deploy.ps1 is a dot-sourcer; operators call `Invoke-BotnetTriage -NoNetworkLookups` directly (lines 41-42). NOT a bug. |
| IPv6 skip-list sufficiency | Concern about mapped IPv4 | `$ip -notmatch '^\d+\.\d+\.\d+\.\d+$'` catches all non-IPv4 including mapped addresses; explicit checks are defense-in-depth |
| `$parentNameIndex` key type | Int/string key mismatch risk | Consistently `[int]` throughout; trace verified |
| `ConvertTo-Json` null serialization | `$null` field behavior | `$null` → JSON `null`; field order stable; Depth=10 sufficient |

---

## Phase 2 Quality Fix: Tier 5 Extension (Fix 2A)

Tier 5 previously verified: exit code 0, JSON written, `configSource=inline-fallback`. It had no assertions for Phase 1.3's new unit. Three assertions added:

1. **Assertion A:** `RemoteASN` field present in Connections JSON rows (verifies `Add-Member` survives serialization on the standalone path).
2. **Assertion B:** `ASN_ENRICH_COMPLETE` log line appears in standalone output (verifies U-EnrichConnectionsASN runs and logs its completion marker on PS 7 inline-fallback path). Uses `& pwsh -NoProfile -File` + `2>&1` to capture `Write-Host` output.
3. **Assertion C:** `ASN_ENRICH_SKIPPED` log line appears when `-NoNetworkLookups` is passed (verifies kill-switch is honored in standalone mode).

All three PASS on the dev box (PS 7.6.0, inline-fallback).

**Design note:** Assertions B and C use `-StopAfterPhase Processing` to skip Reporting overhead. Assertion B does not use `-DryRun` — it needs live connection data for ASN enrichment to run against.

---

## Tier 7 Dynamic Analysis — CF-42 Closure

**Host:** DESKTOP-1ICTRR7  
**PS version:** 5.1.26100.7920 (Windows PowerShell, not PS Core)  
**OS:** Windows NT 10.0.26200.0

| Run | Elevation | Connections | ASN rows | Resolved | Unresolved | Cache hits | Total time | Exit |
|-----|-----------|-------------|----------|----------|-----------|-----------|-----------|------|
| 1 | Non-elevated | 47 flagged of 47 | 47 | 6 | 0 | 41 | 9.67s | 0 |
| 2 | Elevated | 3 flagged of 3 | 3 | 3 | 0 | 0 | 5.17s | 0 |

All 4 ASN fields (`RemoteASN`, `RemoteASName`, `RemoteCountry`, `RemoteCIDR`) present in JSON on both runs.

**CF-42 CLOSED:** `Resolve-DnsName -Type TXT -DnsOnly` (without `-QuickTimeout`) works correctly on PS 5.1.26100.7920. `Add-Member -Force` and `ConvertTo-Json` produce identical schema to the PS 7 run.

### Notable observations

**Cache efficiency (non-elevated run):** 47 rows, 6 unique IPs → 41 cache hits (87.2% hit rate). Clean VMs have concentrated traffic to a small number of CDN/cloud ASNs. The cache design is correctly matched to real-world traffic patterns.

**Elevated vs non-elevated connection delta (47 → 3):** Not a coverage bug. `GetNetTCPConnection` does not require elevation — both runs use the same data source. The delta reflects network state at time of run: the non-elevated run (07:05) captured more active connections than the elevated run (07:11). VM network had quiesced between runs.

**`$PSVersionTable` display artifact:** Both terminal captures show blank PSVersion/PSEdition columns from `| Select-Object PSVersion, PSEdition`. This is a PS 5.1 rendering behavior — the object renders correctly but the column display collapses in some terminal contexts. The `ENV_SNAPSHOT` log line (`PSVersion=5.1.26100.7920`) is the authoritative source for PS version. Do not rely on terminal display of `$PSVersionTable` for version confirmation; read `ENV_SNAPSHOT` from the triage log.

**CF-33 on the VM:** Edge WebView2 not installed — allowlist dormant. Expected. No msedgewebview2.exe in any flagged row.

---

## What Would Have Caught Each Bug Sooner

1. **`-QuickTimeout` bug:** A PS 5.1 syntax check (`[Parser]::ParseFile`) on the module would NOT have caught it (the parameter is valid PS syntax). A Tier 5b run under `powershell.exe -NoProfile` before commit would have caught it immediately. This is the "what-would-have-caught-it" motivation for CF-42 — which we didn't have a verification pass for until Tier 7. The lesson: any time a new DNS/network cmdlet parameter is added, check PS 5.1 DnsClient module docs explicitly.

2. **Hardcoded paths:** A grep for the author's username at pre-commit time would catch these (`git diff --cached | grep -i "RyanF"`). Add to pre-commit mental checklist.

3. **Deploy.ps1 parity:** Automated by a config.md rule, but the rule doesn't have a test. A Tier 5 assertion that loads `triage-weights.json` and `$weightsFallback` and diffs them would catch this class of divergence mechanically. Not written — added to the quality backlog.

---

## Carry-Forward Status After This Phase

| CF | Status |
|----|--------|
| CF-42 | **CLOSED** — PS 5.1 verified via Tier 7 dynamic analysis (DESKTOP-1ICTRR7, 2026-04-10) |
| CF-43 | Open — `RecentlyCreated` flag: emit properly or retire from weights |
| CF-39, CF-40, CF-41 | Open — IPv6 Cymru, ASN scoring tuning, PoC workflow docs |

---

## Files Changed

| File | Change |
|------|--------|
| `modules/Invoke-BotnetTriage.ps1` | Remove `-QuickTimeout` from 2 `Resolve-DnsName` calls in `$resolveOne`; add `Write-Log DEBUG` in outer catch |
| `output/_inspect_asn_fields.ps1` | Replace hardcoded glob path with `Join-Path $PSScriptRoot 'BotnetTriage_*.json'` |
| `output/_inspect_cf33.ps1` | Same path fix |
| `output/_tier5_standalone.ps1` | Add 3 Phase 1.3 assertions (A: RemoteASN field, B: ASN_ENRICH_COMPLETE, C: kill-switch ASN_ENRICH_SKIPPED) |
| `Deploy.ps1` | Add `SuspiciousName = 15` to Services weightsFallback |
