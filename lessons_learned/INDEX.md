# Lessons Learned — Index

> **Project:** botnet-detection (Network Forensics Toolkit)
> **Naming convention:** Sequential (`phaseNN_shortname.md`)
> **Git-tracked:** yes
> **Initialized:** 2026-04-09

## Quick Reference — AI Subject Files

See [ai/_overview.md](ai/_overview.md) for the full file inventory and concern maps.

| File | Rules | Topics / Keywords |
|------|-------|-------------------|
| [ai/powershell.md](ai/powershell.md) | 21 | strict-mode, scoping, dot-source, standalone-fallback, CIM/WMI perf, phase-gate error handling, library shape, bootstrap, AST parsing, bash interop |
| [ai/docs.md](ai/docs.md) | 17 | link checking, surgical Edit, plan-vs-file reconciliation, strategic-vs-tactical scoping, template semantics, operator experience |
| [ai/process.md](ai/process.md) | 20 | Glob sweep, validate-at-write, prior-phase re-verification, Windows tooling, .gitkeep vs README, diagnostic playbook (13-step), bug-fix reflection rules, peer-code as learning vector, CF premise discipline, proof-of-concept-first development |
| [ai/config.md](ai/config.md) | 7 | per-module ownership, in-file Description, dead-config audit (loaded-but-unread fields), .env contract timing, sync obligations |
| [ai/testing.md](ai/testing.md) | 7 | multi-tier non-redundancy, mock realism, AST parse-check, fresh pwsh child, fixture privacy |
| [ai/heuristics.md](ai/heuristics.md) | 9 | false-positive ceiling, dead-flag (absent vs weight=0 diagnostic-only), threshold/floor math, cross-stage data-flow, fallback concentration, enrichment channel selection (DNS over HTTPS), allowlist-vs-blocklist, fallback semantics, operational footprint |

**Concern maps** (cross-file rule clusters): `standalone-fallback`, `verify-at-write-time`, `plan-vs-truth reconciliation` — see [ai/_overview.md](ai/_overview.md#concern-maps).

## Tag Vocabulary

```
powershell, forensics, botnet, triage, beacon, ioc, config, secrets,
error-handling, logging, testing, security, git, deploy, network,
process, remote-shell, standalone-fallback, scaffolding, docs,
enrichment, asn, dns, external-knowledge, operational-footprint,
elevation, dead-code, diagnostic-flags, signer-cache, poc-first
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
| process,docs,verification | When two planning docs disagree about a file's contents, read the committed file — ground truth beats both plans | phase04_iocs_template.md#1 | went-well |
| docs,ioc,design | Template files should document *semantics* (how the file is consumed, what a match means), not just *syntax* — prevents misuse, not just typos | phase04_iocs_template.md#2 | went-well |
| docs,git,planning | A "final" labeled block in a planning doc can still be incomplete — diff it against the committed file before trusting either | phase04_iocs_template.md#3 | pitfall |
| docs,planning | Co-located README + centralized cheatsheet can both exist, but name a single source of truth for shared content | phase04_iocs_template.md#4 | design |
| powershell,process,verification | Parser validation + dot-source smoke test exclude a bug class; "zero bugs found" is meaningful signal, not wasted effort | phase05_shared_helpers.md#1 | went-well |
| powershell,testing,security | For any helper with hand-rolled matching or string manipulation, write a 10-line smoke test with positive AND negative cases | phase05_shared_helpers.md#2 | went-well |
| powershell,bash,tools | Never cram multi-line pwsh into bash-quoted `pwsh -Command "..."` — bash eats backticks and `$()` regardless of `$` escaping; use a tempfile + `-File` | phase05_shared_helpers.md#3 | went-well |
| powershell,docs,standards | Helper library headers should name caller-scope state the helper reads (`Depends:` line), not just parameters — implicit deps are invisible | phase05_shared_helpers.md#4 | went-well |
| powershell,security,testing,masking | Substring-match sensitivity detectors must match at camelCase segment boundaries — `pat`/`sas`/`pwd` false-positive inside `InputPath`/`Assessed`/`ForwardTo` | phase05_shared_helpers.md#1pitfall | pitfall |
| powershell,scoping,library | Dot-sourced library files must not set script-scope state (`Set-StrictMode`, `$ErrorActionPreference`, `param` blocks) — those are the caller's prerogatives | phase05_shared_helpers.md#5 | design |
| powershell,logging,standalone-fallback | Helpers destined for standalone-paste toolkits must degrade gracefully when usual caller-scope state is absent (e.g. `$script:LogFile` unset) | phase05_shared_helpers.md#6 | design |
| powershell,stubs,fail-loud | "Fail loud" ≠ "fail closed" — library stubs should WARN-and-return-null, not throw, so one stub call doesn't brick the whole dot-source | phase05_shared_helpers.md#7 | design |
| powershell,scoping,phase-gate | Helpers in dot-sourced libraries must NOT call `exit` — throw a tagged terminating error and let the caller decide function-return vs script-exit | phase06_invoke_triage_build.md#1 | pitfall |
| powershell,testing,smoke-test | Bracket function smoke tests with `=== START ===` / `=== END (rc=$rc) ===` trailers — missing trailer is a precise tell that the function exited via an unexpected path | phase06_invoke_triage_build.md#1 | went-well |
| powershell,performance,cim,wmi | Per-row Get-CimInstance inside foreach is a perf bug — build one snapshot at phase start, hashtable-index by primary key, look up inside the loop | phase06_invoke_triage_build.md#2 | pitfall |
| powershell,logging,observability | Always include stopwatch duration in `UNIT_END` log lines — slow units name themselves; without it, "feels slow" takes hours to localize | phase06_invoke_triage_build.md#2 | went-well |
| security,heuristics,false-positive | Any suspicion-detector that fires on >10% of its input is broken — corpus-check heuristics against a clean baseline before ship | phase06_invoke_triage_build.md#3 | pitfall |
| security,heuristics,scoring | Flags that aren't in the weights file are dead code with negative value — they consume operator attention without influencing the verdict; delete the emit code | phase06_invoke_triage_build.md#3 | pitfall |
| powershell,error-handling,phase-gate | Two-arm catch (gate-signal → return 0, anything-else → return 99) is clearer than separate trys when a function has both early-exit-success and panic paths | phase06_invoke_triage_build.md#1design | design |
| powershell,standalone-fallback,helpers | Capability detection (`Get-Command -ErrorAction SilentlyContinue`) is more robust than caller-set flags for "should I provide a fallback?" decisions | phase06_invoke_triage_build.md#2design | design |
| powershell,module-shape,libraries | Modules whose entry point is a single named function should ship that function and stop — no "if invoked as script, run it" footer; conflates definition and invocation | phase06_invoke_triage_build.md#3design | design |
| powershell,strict-mode,scalar-vs-array | Under `Set-StrictMode -Version Latest`, ALWAYS wrap `Get-ChildItem` (and any cmdlet that may return 0/1/N) in `@(...)` — `.Count` on a single FileInfo throws | phase07_deploy_launcher.md#1 | pitfall |
| powershell,scoping,dot-source | Dot-source operations (`.`) cannot be wrapped in a function — definitions die when the function returns; lift dot-source to script scope | phase07_deploy_launcher.md#2 | pitfall |
| powershell,announce,filtering | Use AST parsing to enumerate "what this codebase contributes" — never use `Get-Command -Name 'Invoke-*'`; PSModulePath pollution makes blocklists unbounded | phase07_deploy_launcher.md#3 | pitfall |
| powershell,bootstrap,logging | Inline a minimal `Write-Log` at top of a launcher — function shadowing makes the handoff to the authoritative version transparent if signatures + script-scope vars match | phase07_deploy_launcher.md#1went | went-well |
| powershell,bootstrap,error-handling | Distinguish critical (exit) vs non-critical (warn+continue) units via a wrapper switch — bake the rule into the API, don't scatter try/catch | phase07_deploy_launcher.md#3went | went-well |
| powershell,bootstrap,ordering | When a plan's nominal step order has a mechanical dependency (logfile needs OutputDir to exist), reshuffle and document the divergence inline at the divergence | phase07_deploy_launcher.md#1design | design |
| architecture,fallback | Don't add fallback modes to every file — identify the canonical "no-launcher" path and concentrate fallback complexity there; some files ARE the fallback | phase07_deploy_launcher.md#2design | design |
| testing,verification,multi-tier | Each verification tier must exclude a different bug class — skipping any tier silently allows that class to ship (Tier 2 passed; Tier 2a found broken IOC correlation) | phase08_verification_tiers.md#1 | went-well |
| testing,ioc,verification | Mock IOC files must contain real entries from the test host — synthetic IOCs that match nothing yield a vacuous pass | phase08_verification_tiers.md#2 | went-well |
| testing,powershell,verification | AST parse-check before re-running a tier — sub-100ms vs 13s+ per real-run cycle; cheapest possible regression test on every edit | phase08_verification_tiers.md#3 | went-well |
| testing,standalone-fallback,verification | Helper-stub guards (`if -not Get-Command`) make stubs invisible in normal load path — only standalone-paste exercises stub bodies | phase08_verification_tiers.md#4 | went-well |
| powershell,strict-mode,cim,wmi | CIM polymorphism: heterogeneous collections (`Actions`, `Triggers`) need `PSObject.Properties.Name -contains` probing — direct property access throws under StrictMode on non-default subtypes | phase08_verification_tiers.md#1pitfall | pitfall |
| architecture,data-flow,ioc | Cross-stage filter that's correct in isolation can be wrong in pipeline — test the pipeline end-to-end with data only visible via the cross-stage path | phase08_verification_tiers.md#2pitfall | pitfall |
| heuristics,scoring,ioc | Thresholds and floors must be checked against each other — a 10×2.0=20 IOC-only floor lands in Low when Medium threshold is 25; lurks until pipeline test | phase08_verification_tiers.md#3pitfall | pitfall |
| standalone-fallback,powershell,verification | If standalone-paste is load-bearing, the standalone-paste tier is non-optional — every change to the function body that may add a helper call must re-run it | phase08_verification_tiers.md#4pitfall | pitfall |
| powershell,scoping,defensive | Inline helper stubs in paste-target files: use `Get-Variable -Scope 1` for caller-param lookup, not implicit dynamic scoping — paste session strict-mode state is unknowable | phase08_verification_tiers.md#1design | design |
| testing,git,privacy | Test fixtures (mock IOCs, smoke-test scripts) belong in unconditionally-ignored dirs (`output/`), not partially-ignored dirs (`iocs/`) — defends against future .gitignore edits | phase08_verification_tiers.md#2design | design |
| testing,standalone-fallback,isolation | Standalone-paste tier must spawn a literal fresh `pwsh -NoProfile` child — runspaces inherit `$env:PSModulePath` and silently mask missing-stub bugs | phase08_verification_tiers.md#3design | design |
| docs,verification,powershell | Markdown link-checking belongs in the same step as writing the file — extract `\]\(([^)]+)\)`, filter internal, Test-Path each | phase09_readme_expansion.md#1 | went-well |
| docs,planning,scoping | Module/feature tables must distinguish *shipped* from *planned* in the same column — separate "status" lines get skimmed past | phase09_readme_expansion.md#2 | went-well |
| docs,deployment,operator-experience | When multiple deployment paths are meaningfully different, document them as parallel siblings (Path A/B/C), not primary + footnotes | phase09_readme_expansion.md#3 | went-well |
| docs,planning,ephemeral-context | Bug-specific troubleshooting entries have a half-life — schedule a prune or move to CHANGELOG before they accumulate | phase09_readme_expansion.md#1pitfall | pitfall |
| docs,planning,coupling | Public docs that link to scheduled-for-reorg internal artifacts must capture the dependency in a CF before the reorg starts | phase09_readme_expansion.md#2pitfall | pitfall |
| docs,security,deployment | Standalone-paste path documents *paste*, not `iwr \| iex` — `iwr \| iex` to a security tool from GitHub looks identical to a malicious dropper to EDR | phase09_readme_expansion.md#2design | design |
| docs,planning,scoping | Don't pre-extract reference documentation until it has at least two consumers — one module's reference belongs in README; two earn their own file | phase09_readme_expansion.md#3design | design |
| process,lessons-learned,scoping | When organizing accumulated rules, count the primary tag first — `≥3 rules earns a file` is a real cliff; below it sits in INDEX, above it earns a file | phase10_lessons_finalize.md#1 | went-well |
| process,lessons-learned,coupling | Carry-forwards exist to be consulted *before action*, not just appended *after* — re-read open CFs at phase start, not just retrospective | phase10_lessons_finalize.md#2 | went-well |
| docs,verification,powershell | When a verification idiom has worked in 3+ phases, promote it from per-phase tactical to cross-phase reflex — fixed cost vs growing-cost-of-not-running | phase10_lessons_finalize.md#3 | went-well |
| process,lessons-learned,scoping | Tag the primary slot with the topic the rule *teaches*, not the technology it *uses* — `heuristics,powershell` not `powershell,heuristics` | phase10_lessons_finalize.md#1pitfall | pitfall |
| lessons-learned,planning | AI-file rule counts that aggregate cross-references can overcount — graduation passes should recount with deduplication | phase10_lessons_finalize.md#2pitfall | pitfall |
| lessons-learned,docs | AI subject files use terse When/Rule template (not narrative) + `*Source:*` line as bridge — narrative lives in phase files, AI files are pure rules | phase10_lessons_finalize.md#1design | design |
| lessons-learned,scoping | Concern maps live inline in `_overview.md` (not separate files) until ~5 entries each — keeps single entry point flat | phase10_lessons_finalize.md#2design | design |
| lessons-learned,coupling,planning | Foundation graduation is a phase-boundary activity, not a phase-finalization activity -- defer until next phase transition | phase10_lessons_finalize.md#3design | design |
| powershell,encoding,debugging | PS 5.1 reads .ps1 files as Windows-1252 unless BOM present -- UTF-8 em-dashes/arrows in comments break parser with cascading "Expressions are only allowed as the first element of a pipeline" | phase11_ps51_encoding_fix.md#1 | went-well |
| powershell,encoding,debugging | Mojibake signatures (`â€"`, `â€™`, `â€œ`, `Â`) in PS 5.1 error output instantly name an encoding bug -- scan the error text for these before chasing the cited line number | phase11_ps51_encoding_fix.md#1 | went-well |
| powershell,encoding,verification | Before bulk-fixing encoding bugs, enumerate codepoints + counts -- bounded substitution map is auditable and reversible; greedy strip-and-replace destroys information | phase11_ps51_encoding_fix.md#2 | went-well |
| powershell,encoding,verification | Encoding fix scope = every text file the operator might READ, not just files the parser chokes on -- mojibake in a security tool erodes trust as fast as a real bug | phase11_ps51_encoding_fix.md#3 | went-well |
| testing,powershell,verification | No verification tier covering "PS 5.1 reads file" = the bug class ships -- multi-tier rule (phase08#1) re-applies as predictive warning | phase11_ps51_encoding_fix.md#1pitfall | pitfall |
| powershell,verification,defensive | Round-trip equality checks compare original-after-substitution against bytes-decoded-back -- `Contains('?')` false-positives on legitimate `?` chars in source | phase11_ps51_encoding_fix.md#3pitfall | pitfall |
| powershell,encoding,deployment | Prefer ASCII replacement over UTF-8 BOM for shipping .ps1 -- standalone-paste path can't survive BOM bytes; ASCII has zero failure modes across editors/tools/shells | phase11_ps51_encoding_fix.md#1design | design |
| testing,git,privacy | One-shot diagnostic scripts live in gitignored `output/` -- generalizes phase08#2design (test fixtures) to one-shot tooling | phase11_ps51_encoding_fix.md#2design | design |
| process,debugging,powershell | When PS reports cascading parser errors with "Missing closing '}'" trail, the cited line is always wrong -- the *first* point of confusion is closer to the bottom of the error output | phase12_diagnostic_playbook.md#step1 | went-well |
| powershell,encoding,debugging | Mojibake fingerprints (`â€"`, `â†`, `Â`, `Ã`) name encoding bugs in <20 seconds -- skip the parser-error chase, go to the encoding fix | phase12_diagnostic_playbook.md#step2 | went-well |
| process,debugging | Force the bug hypothesis into one sentence before writing diagnostic code -- if you cannot, you have a confused suspicion, not a hypothesis | phase12_diagnostic_playbook.md#step3 | went-well |
| process,debugging,tools | When the bug is in tool X's display, you cannot diagnose it with tool X -- find a tool one layer below (raw bytes, raw packets, raw timing) | phase12_diagnostic_playbook.md#step4 | went-well |
| process,debugging,bash | When a diagnostic command fails for quoting/escaping reasons, STOP -- the diagnostic environment is now compromised, switch invocation paths before continuing | phase12_diagnostic_playbook.md#step5 | went-well |
| process,debugging,scoping | Quantify the bug surface (files, bytes, distinct values) before designing the fix -- numbers drive design; vibes do not | phase12_diagnostic_playbook.md#step6 | went-well |
| process,refactoring | Bounded substitution maps over greedy strip-and-replace -- narrow fixes are reviewable, reversible, extensible; broad fixes hide future bugs | phase12_diagnostic_playbook.md#step7 | went-well |
| powershell,encoding,fail-loud | Encoding-bug fixes must use writers that bypass encoding negotiation (`File::WriteAllBytes`) -- letting PS choose an encoding re-introduces the bug class | phase12_diagnostic_playbook.md#step8 | went-well |
| process,verification,debugging | The discovery tool IS the first regression test -- if it still finds the bug after the fix, the fix is wrong; no other verification matters yet | phase12_diagnostic_playbook.md#step9 | went-well |
| process,verification | Two verification passes that exercise the same code path are one verification pass -- each pass must exclude a *different* bug class or it is decoration | phase12_diagnostic_playbook.md#step10 | went-well |
| process,debugging,scoping | When you find a bug, ask "what is the bug *class*, and where else could it manifest?" -- audit the surface in the same session, not next week | phase12_diagnostic_playbook.md#step12 | went-well |
| lessons-learned,process | Bug-fix reflections must answer "what would have caught this?" -- if the answer is "none of our tests," that is a CF, not a footnote | phase12_diagnostic_playbook.md#step13 | went-well |
| heuristics,scoring,false-positive | When detector top-N is dominated by identical findings on a clean baseline, fix the detector (allowlist) rather than the display (top-N dedup) -- dedup hides noise behind cosmetics | phase12_diagnostic_playbook.md#finding2 | pitfall |
| lessons-learned,docs | Diagnostic playbooks captured as numbered steps (not bullets) -- the order encodes a dependency graph that prose flattens away | phase12_diagnostic_playbook.md#2design | design |
| enrichment,network,dns | Prefer protocols the endpoint already needs (DNS, NTP) over protocols the perimeter may block (HTTPS to third-party API) -- Cymru DNS TXT for ASN lookup is the canonical example | phase13_external_pattern_borrow.md#finding1 | design |
| heuristics,enrichment,asn | Allowlist the small finite normal set (legitimate ASNs ~10-20) and surface everything else; blocklists of bad IPs decay daily, allowlists of legitimate operators decay over years | phase13_external_pattern_borrow.md#finding2 | design |
| heuristics,enrichment | Document fallback semantics -- distinguish degraded answer (same question, less precision) from different answer (related question, full precision); /24 vs BGP /20 is the latter | phase13_external_pattern_borrow.md#finding3 | design |
| enrichment,operational-footprint,security | A detection tool's enrichment lookups are part of the tool's observable footprint *on the target* -- document them, provide a `-NoNetworkLookups` kill-switch, make stealth-vs-quality the operator's choice | phase13_external_pattern_borrow.md#finding4 | design |
| process,external-knowledge,lessons-learned | Read peer code from adjacent forensics/security domains for techniques even when use cases differ -- trade knowledge is invisible to general docs but visible in working code from practitioners | phase13_external_pattern_borrow.md#finding5 | went-well |
| process,lessons-learned,planning | Carry-forwards must record their *premise*, not just their deferral -- "Phase 2 because needs offline DB" is reviewable; "Phase 2" is opaque and outlives its premise silently | phase13_external_pattern_borrow.md#finding6 | pitfall |
| process,planning,docs | Ghost CFs (referenced but never formally defined in a committed file) are invisible to premise audits -- every CF must have a committed definition with Title/Surface/Action/Premise or it doesn't exist | phase15_cf35_premise_audit.md#finding1 | pitfall |
| process,planning | CF clusters that share a premise (CF-21/23/24/30 graduation, CF-16/19 scoring) must be treated as a single atomic task -- fixing one without the others risks inconsistency | phase15_cf35_premise_audit.md#finding6 | design |
| config,dead-code,suppression | Config fields loaded by U-LoadConfig but never read by any unit are dead code with the same negative value as dead flags -- TrustedSigners sat dead next to BeaconWhitelist for an entire phase | phase14_phase12_connection_enrichment_and_hotfix.md#1 | pitfall |
| testing,verification,elevation,multi-tier | Tier 6 (non-elevated baseline on a real desktop) is mandatory -- excludes the elevation-degradation bug class; clean VMs and admin sessions cannot substitute | phase14_phase12_connection_enrichment_and_hotfix.md#2 | went-well |
| heuristics,scoring,diagnostic-flags | Dead-flag rule has a carve-out: *absent* from weights file = dead; *present with weight 0* = diagnostic-only flag, legitimate, never appears in scoring math | phase14_phase12_connection_enrichment_and_hotfix.md#3 | design |
| powershell,performance,signer-cache | Path-keyed per-invocation Get-AuthenticodeSignature cache -- generalizes phase06#2 (per-row CIM is a perf bug) to any expensive lookup with a stable key. Per-invocation, not persistent (signer state can change) | phase14_phase12_connection_enrichment_and_hotfix.md#went-well-2 | design |
| testing,verification,elevation | Elevation-degradation is its own bug class -- mechanically-correct code under non-admin permissions can still mislead the operator. Code-reading audits cannot find these; only a degraded-environment run can | phase14_phase12_connection_enrichment_and_hotfix.md#2 | pitfall |
| powershell,permissions,observation | Non-elevated Get-NetTCPConnection enumerates SYSTEM-owned connections fine; only the downstream Win32_Process enrichment (ExecutablePath, CommandLine) degrades. ParentProcessName survives non-elevation | phase14_phase12_connection_enrichment_and_hotfix.md#observations | went-well |
| process,poc-first,development | Build the minimal testable version that proves the methodology before investing in error handling, config integration, logging, and edge cases -- PoC failure is early success (pivot before the investment compounds) | ai/process.md#poc-first | design |
| process,poc-first,development | PoC script becomes permanent regression test -- same code that proved the method initially re-runs in seconds to catch format drift in the external dependency (Cymru DNS TXT format example) | phase16_asn_enrichment_and_killswitch.md#went-well-1 | went-well |
| enrichment,asn,dns | Team Cymru DNS TXT at origin.asn.cymru.com resolves ASN/CIDR/Country/AS-Name from a reversed IPv4 address with no API key, no database, just Resolve-DnsName -- IPv4 only, IPv6 is a separate zone (origin6) | phase16_asn_enrichment_and_killswitch.md#data-points | went-well |
| enrichment,design | Ship enrichment (context) before scoring (judgment) -- context is mechanical and universally useful; scoring is per-engagement and needs data to tune against. Bundling them locks in weights that may be wrong for the first engagement | phase16_asn_enrichment_and_killswitch.md#decision-enrichment-only | design |
| heuristics,allowlist,signer-cache | Allowlists that expand a trust boundary (embedded-browser suppression) should be gated on an additional signal, not process name alone -- msedgewebview2.exe signer-gated on Microsoft TrustedSigner, reusing the existing Authenticode cache | phase16_asn_enrichment_and_killswitch.md#went-well-3 | design |
| enrichment,operational-footprint,network | Never call an external service for non-public inputs -- the skip-list (RFC1918/loopback/link-local/CGNAT/multicast) must short-circuit before the DNS/HTTP call, both for performance and to prevent leaking internal topology to the external resolver | phase16_asn_enrichment_and_killswitch.md#pitfall2 | pitfall |
| process,design,contract | Feature-flagged output must have a stable schema regardless of flag state -- set fields to null in the off-path instead of omitting them; downstream consumers should not have to conditionally handle "might not exist" | phase16_asn_enrichment_and_killswitch.md#pitfall3 | design |
| process,refactoring,verification | Refactors triggered by a second caller should verify the ORIGINAL site still works, not just the new one -- Tier 1/2 run that exercises the original flag's original trigger is the minimum bar | phase16_asn_enrichment_and_killswitch.md#regression5 | went-well |
| process,planning | Atomic CF cluster rule held: CF-31 + CF-34 shipped in one commit because CF-34 (kill-switch) was phase15 blocking-dependency for CF-31 (ASN enrichment) -- shipping either alone would have been worse than shipping neither | phase16_asn_enrichment_and_killswitch.md#went-well-4 | design |

## Foundation

| tags | description | source | type |
|------|-------------|--------|------|

## Reference

| tags | description | source | type |
|------|-------------|--------|------|
