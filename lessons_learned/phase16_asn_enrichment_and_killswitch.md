---
name: phase16_asn_enrichment_and_killswitch
description: Phase 1.3 ship reflection. Three carry-forwards closed atomically (CF-31 ASN enrichment via Team Cymru DNS, CF-33 embedded-Chromium WebView2 allowlist with signer gating, CF-34 -NoNetworkLookups kill-switch). Validated the PoC-first rule on its first real use. Extracted a reusable signer-check closure that deduplicated an existing inline block. One CF (CF-28) explicitly deferred because its premise was still live (needs clean-baseline data). Establishes enrichment as the third scoring axis alongside process identity and port.
type: reflection
---

# phase16_asn_enrichment_and_killswitch --- ASN Enrichment, WebView2 Allowlist, Network Kill-Switch

> **Scope:** Phase 1.3 atomic trio. CF-31 (Team Cymru DNS ASN enrichment), CF-33 (WebView2 embedded-Chromium allowlist), CF-34 (`-NoNetworkLookups` kill-switch). CF-28 deferred with premise still valid.
> **Date:** 2026-04-10
> **Verification:** Parser clean, dry-run Preflight->Processing exit 0, full real-run exit 0 (JSON 46KB, 27 connection rows enriched 27/27), kill-switch path verified (unit duration 0.04s vs 4.7s enriched), Tier 5 standalone-paste pass with `source=inline-fallback` and `ASN_ENRICH_COMPLETE` log line, CF-33 live-process check confirms msedgewebview2.exe is Microsoft-signed Valid and produces zero flagged rows.

---

## Applied Lessons

| Rule (file -> heading) | Outcome | Note |
|------------------------|---------|------|
| process.md --- proof of concept before full implementation | **Validated on first real use** | `output/_poc_cymru_dns.ps1` was 90 lines of "does this method work against real DNS" before a single line of production code. 3/3 test IPs resolved on first run. The PoC became the regression test for the core mechanic --- if a later edit breaks Cymru TXT parsing, the PoC will catch it before Tier 1. See "What Went Well #1" below. |
| process.md --- carry-forwards must record their premise | **Paid off immediately** | Every CF closed this phase had an explicit premise from phase15_cf35_premise_audit. CF-31's premise ("needs offline DB") had already been collapsed by peer-code reading; CF-34's premise ("blocks CF-31") was load-bearing and is why the two shipped together. CF-28 is still open *because* its premise ("needs clean-baseline sampling") is still true on this host. |
| process.md --- cross-class verification | **Re-applied** | PoC run used `Resolve-DnsName` (PowerShell cmdlet); verification used `nslookup` (different tool, different resolver plumbing) --- both returned identical TXT payload. Would have caught a PS-specific DNS caching bug. |
| heuristics.md --- allowlist the small finite normal set | **Re-applied, narrowly** | CF-33 added exactly one process name (`msedgewebview2.exe`) to the embedded-browser pattern, gated on TrustedSigner (Microsoft). Resisted the temptation to add CefSharp / electron / others preemptively --- narrow scope matches the audit's "allowlist that's too broad suppresses real C2" warning. |
| heuristics.md --- enrichment as observable footprint | **Codified into a kill-switch** | CF-34 is the operational consequence of this rule: every DNS query the tool makes is observable on the target endpoint. The `-NoNetworkLookups` switch exists so an operator running triage on a host they don't want to "touch the network from" has a guarantee. |
| testing.md --- Tier 5 standalone-paste is non-negotiable for new units | **Re-applied** | `U-EnrichConnectionsASN` has three inline helpers (`$skipEnrich`, `$resolveOne`, `$testTrustedSigner` in sibling unit). Without Tier 5, I'd have no confidence the inline-fallback path picked them up. It did --- Tier 5 logged `ASN_ENRICH_COMPLETE` from a fresh `pwsh -NoProfile` child with no config files. |
| process.md --- Glob sweep before writing files | **Re-applied** | Checked `output/` for pre-existing `_poc_*` scripts before creating `_poc_cymru_dns.ps1`. |
| config.md --- fallback weights must match file schema | **Verified explicitly** | After CF-31 + CF-33, compared `$weightsFallback` (line 443) against `config/triage-weights.json` --- identical. ASN enrichment is context-only this phase, not a scoring contribution, so no weight entries needed. |
| process.md --- "what would have caught this" discipline | **Driving section 4 below** | The ParentProcessName-by-pid_ bug I didn't actually hit (but could have) is captured as a Pitfall-Avoided. |

---

## What Went Well

### 1. PoC-first rule validated on its first real use

The rule was added to `ai/process.md` earlier the same day as a user guideline. CF-31 was the first feature after the rule landed. The workflow:

1. Write `output/_poc_cymru_dns.ps1` --- 90 lines, three real IPs (8.8.8.8 / 1.1.1.1 / 208.67.222.222), real `Resolve-DnsName` calls, parse the TXT payload.
2. Run it: `POC_PASS: Cymru DNS method viable (3/3 resolved)` in ~2 seconds.
3. Cross-verify with nslookup --- same TXT bytes, different tool class.
4. Only then write `U-EnrichConnectionsASN` (~130 lines production code with cache, skip-list, kill-switch, logging).

**What this bought me:** the production unit's Cymru-specific logic (reverse octets, origin.asn.cymru.com path, two-stage ASN->ASName lookup, multi-origin "15169 36040" handling) was already proven working code by the time I ported it. The production layer was just "add cache, skip non-public IPs, gate on kill-switch, Add-Member to rows" --- all independent of the core DNS method. If the method had failed (e.g., Cymru had rate-limited the resolver or the TXT format had drifted from documentation), the pivot cost was ~15 minutes of PoC work, not an abandoned production unit.

**The PoC's cost was amortized across the production implementation.** The ~90 lines of PoC code became a permanent regression test (`output/_poc_cymru_dns.ps1`) that re-runs in ~2 seconds. If any future refactor breaks the Cymru parse logic, running the PoC against known-good IPs catches it before Tier 1. The PoC is now the first regression test for CF-31's fundamental mechanic, exactly as `ai/process.md#proof-of-concept-first` says it should be.

### 2. CF-31 shipped enrichment-only, not scoring

The audit spec said "ASN enrichment" --- it didn't say "ASN-based scoring." Those are different problems:
- **Enrichment** is mechanical: resolve IP -> ASN, add fields. Methodology is the only question.
- **Scoring** is judgment: is AS13335 (Cloudflare) a positive or negative signal? AS16509 (AWS)? AS14061 (DigitalOcean)? AS16276 (OVH)? The answer depends on the engagement --- a commercial SaaS app uses Cloudflare legitimately; a botnet C2 uses DigitalOcean/OVH more often than residential. An engagement-specific tuning decision, not a universal rule.

Shipping enrichment alone unblocks the scoring decision without locking in weights that might be wrong for the first real engagement. The operator gets the context today; the scoring pass comes after there's per-engagement data to tune against. This is the same separation the Phase 1.2.1 hotfix's `EnrichmentIncomplete` flag used (weight 0, diagnostic-only, data without judgment).

### 3. CF-33 signer-gated narrowly, not name-matched broadly

The cheap fix for msedgewebview2.exe firing `PrivateToPublicNonBrowser` was to add it to the `$browserPattern` regex. Two characters of edit. The audit premise (`phase15_cf35_premise_audit.md` line 68) explicitly warned: "an allowlist that's too broad suppresses real C2."

The cheap fix would have allowlisted any file named `msedgewebview2.exe` regardless of location or signer. An attacker dropping `msedgewebview2.exe` in `C:\Users\Public\` would be invisible. The safer fix reuses the existing signer cache (already paid for by the Phase 1.2.1 `ProcessInTempOrAppData` signer-aware refinement) and checks that the binary is actually Microsoft-signed.

The extra safety cost nothing because the signer cache infrastructure was already in place. An unsigned `msedgewebview2.exe` dropped by an attacker still fires the flag. The allowlist is load-bearing, not a blind-trust name match.

### 4. The atomic CF cluster rule held

Per phase15, CF-31 and CF-34 were identified as one commit ("CF-31 cannot ship without CF-34"). They shipped together in one editing session, not two. If I'd shipped CF-31 first, the enrichment DNS lookups would have been observable from the target endpoint with no operator opt-out --- a worse outcome than not shipping CF-31 at all on network-paranoid engagements.

CF-33 was a natural extension of the same Phase 1.3 "connection context" theme. Including it in the same commit kept the phase coherent: one theme (connection enrichment + operator control), three flags closed.

### 5. Signer-check extraction was justified by two callers, not speculation

When CF-33 needed signer verification, I extracted the inline Authenticode block from `ProcessInTempOrAppData` into a closure (`$testTrustedSigner`). The refactor was justified *because there were two callers*, not in anticipation of future callers. Net code change: ~10 lines removed (dedup) + one reusable closure. Both sites are now one-liners that read naturally (`if (& $testTrustedSigner $pd.Path) { ... }`).

**Why this matters:** "avoid speculative abstractions" is a real rule --- premature extraction is waste. But "dedupe two callers" is not speculation, it's a measured refactor. The rule is to refactor when you have evidence, not to refactor when you might someday. Two callers is evidence.

---

## Bugs / Pitfalls Avoided

### 1. Pitfall: ParentProcessName key type mismatch (caught by real run, not parser)

The existing Phase 1.2 code indexes `$parentNameIndex` by `[int]$pid_`. My CF-31 code had no direct interaction with parent lookups, but the original `U-ConnectionsSnapshot` keyed `$parentNameIndex[$pid_]` --- and `$pid_` is already an int because of `$pid_ = [int]$c.OwningProcess`. No bug, but the defensive re-cast pattern (`[int]$pid_`) at the `parentNameIndex[[int]$c.OwningProcess]` line from the phase1.2 initial design is a useful reminder: hashtable keys in PowerShell are reference-equality sensitive between `[int]`, `[uint32]`, and `[string]` representations of the same number. The pattern that survived was: always cast at the lookup site, even when the variable looks pre-cast.

I didn't hit a new bug this phase, but I did have to read this code carefully to add ASN fields to each row via `Add-Member` without breaking the existing `Flags` array semantics. The pitfall-avoided is: `Add-Member -Force` on `NoteProperty` does the right thing even for rows that already exist; I considered rebuilding each row as a new `PSCustomObject` and decided against it (unnecessary allocation, and `Flags` is a reference-typed array so rebuild would have silently de-reffed it).

### 2. Pitfall: Skip-list must come before DNS call

First draft of `U-EnrichConnectionsASN` had me calling `$resolveOne` on every row and letting Cymru return `$null` for private IPs. That would have been wrong in two ways:
- **Performance:** one DNS round-trip per private IP, adding seconds to the unit
- **Footprint:** sending `10.x.x.x.origin.asn.cymru.com` queries leaks internal network topology to a public DNS resolver

I caught this at design time (before writing the body) by thinking about the "what's the smallest reasonable input" case. The skip-list (`$skipEnrich` closure) runs first; non-public IPs never hit the wire. RFC1918 + loopback + link-local + CGNAT + multicast all short-circuit. This is a design pitfall that would have shipped silently --- nothing would have errored, the operator just would have been leaking internal IPs to Cymru.

**The lesson:** for any external lookup, write the skip-list before the call-site. "Never make a network call you don't have to" is the zero-footprint default. Should probably be codified as a heuristic rule.

### 3. Pitfall: -NoNetworkLookups must add null fields, not skip the Add-Member entirely

First mental model was "if kill-switch is set, return early." But that would produce connection rows WITHOUT the new `RemoteASN`/`RemoteASName`/etc. fields --- the output JSON schema would differ depending on whether the flag was set. Downstream consumers (top-5 summary, operator JSON readers) would have to handle "field might not exist" cases.

Fix: the kill-switch path still loops through rows and adds `$null` for each new field. Output shape is stable regardless of flag state. This is the "uniform schema" principle for feature flags --- the feature's presence can vary, the output contract cannot.

### 4. Pitfall-in-waiting: IPv6 Cymru support not implemented

Current skip-list treats anything that doesn't match `^\d+\.\d+\.\d+\.\d+$` as "skip for now." This means IPv6 connections get enrichment fields set to null, even public ones. Team Cymru does support IPv6 via `origin6.asn.cymru.com` with reversed nibbles, but the query format is fiddly and my dev box has few IPv6 established connections to test against.

**Decision:** explicit defer, not silent skip. Logged as **CF-39** (see Carry-Forwards below). Shipping IPv4-only enrichment is better than shipping broken IPv6 enrichment; shipping nothing is worse than shipping IPv4. The explicit defer keeps the gap visible.

---

## Decisions Made

### Decision: CF-31 ships without scoring weights

Already explained in "What Went Well #2." The short version: enrichment is context, scoring is judgment; bundling them would have required a judgment call (which ASNs are hostile?) without the engagement data to make that call. A future tuning pass can add weights when there's a real engagement to tune against.

### Decision: CF-33 is signer-gated, not name-only

Already explained in "What Went Well #3." The short version: the audit's explicit "too broad allowlist" warning + existing signer infrastructure = free extra safety.

### Decision: CF-28 stays open

The phase15 audit said CF-28 (ScheduledTasks LOLBin Microsoft allowlist) needs "clean-baseline author sampling." I'm running on a dev box. Building the allowlist from dev-box data would produce an allowlist that matches my installed software, not a representative Windows 11 host. That would either under-suppress (legitimate Microsoft tasks on other hosts not allowlisted) or over-suppress (non-Microsoft tasks that happen to be on my dev box allowlisted).

The premise is still live. Deferring is correct. The audit's own rule ("CFs whose premise has fallen should be promoted; CFs whose premise is still live should stay open") applies directly.

### Decision: Tier 6 (non-elevated) rerun not needed this phase

Phase 14 added Tier 6 because non-elevated runs were discovering bugs that elevated runs missed. CF-31 / CF-33 / CF-34 are all in code paths that behave identically elevated vs non-elevated (DNS is a per-user operation, Authenticode signing is readable by any user, the kill-switch is a param check). I verified on non-elevated (this session's shell is non-elevated and all the real runs were against it). An elevated rerun is a hygiene check for the next phase transition, not a blocker for this ship.

### Decision: Skipped the `-NoNetworkLookups` flag in the inline fallback weights

The kill-switch is a parameter, not a config field. The fallback weights map is for scoring weights only. No weights entry needed.

---

## Data Points from the Real Run

**Before Phase 1.3 (baseline, phase14 V3 elevated run):** HIGH=0 MEDIUM=22 LOW=2 (dev box noise elevated)

**After Phase 1.3 (non-elevated, this phase):**
- Total connections scanned: 58-66 (varies with background churn)
- Flagged before CF-33 (ephemeral msedgewebview2 rows counted): 42
- Flagged after CF-33 (msedgewebview2 suppressed): 27
- Net reduction: ~15 rows (35% of flagged), exactly the msedgewebview2 noise the CF-33 premise targeted
- Unique remote IPs resolved to ASN: 27
- Resolution success rate: 27/27 (100%) via Cymru DNS
- Cache hit rate: 6/33 lookups (18% --- reasonable, one browser tab hits the same CDN edge many times)
- Enrichment unit duration: 1.4-4.7s for 20-34 unique lookups (~50-150ms per lookup, consistent with DNS latency)
- Kill-switch unit duration: 0.04s (vs 4.7s when enrichment runs, 99% reduction --- confirms zero DNS activity)

**Observed ASNs in the real output (all expected for a dev box):**
- Microsoft (AS8075) dominant (25 rows) --- Teams, Windows Update, Office, Edge telemetry
- Amazon (AS16509, AS14618) --- AWS services
- Akamai (AS20940) --- CDN for Microsoft
- GitHub (AS36459) --- VS Code Git operations
- Anthropic (AS399358) --- Claude Code sessions
- Google Cloud (AS396982) --- GCP-hosted services
- Cloudflare (AS13335) --- DNS
- N-able (AS16633) --- MSP RMM vendor
- One MS row in country GB instead of US --- CDN edge, exactly the "huh, why?" context the operator now has

**Output stability:** the JSON artifact shape is identical between `-NoNetworkLookups` runs and normal runs --- all four new fields (`RemoteASN`, `RemoteASName`, `RemoteCountry`, `RemoteCIDR`) are present on every row, just null when the kill-switch is set.

---

## Carry-Forwards

### Closed this phase

- **CF-31** --- ASN enrichment via Cymru DNS --- shipped in `U-EnrichConnectionsASN`
- **CF-33** --- Embedded-Chromium WebView2 browser filter --- shipped as signer-gated allowlist in `U-ConnectionsSnapshot`
- **CF-34** --- `-NoNetworkLookups` kill-switch --- shipped as parameter + `$script:NetworkLookupsEnabled` flag

### Still open (premise unchanged)

- **CF-28** --- ScheduledTasks LOLBin Microsoft allowlist --- still waiting on clean-baseline sampling
- All other CFs from phase15 audit (graduation cluster, tuning cluster, hygiene cluster) --- premise unchanged, deferral still valid

### New carry-forwards

- **CF-39** --- **IPv6 ASN enrichment via Cymru `origin6.asn.cymru.com`**. Current `U-EnrichConnectionsASN` skips any remote address not matching IPv4 dotted-quad. Team Cymru supports IPv6 via a reversed-nibble format at `origin6.asn.cymru.com`, but the query construction is fiddly (32 reversed nibbles + trailing zone) and I had insufficient IPv6 traffic on this host to test against. Premise: needs a host with meaningful IPv6 outbound connections to verify the parse logic against real TXT payloads. Premise collapses if: a target engagement has IPv6 traffic the operator wants enriched, or a dev box picks up IPv6 connectivity that can be used for testing. Phase: Phase 1.4 hygiene pass or next engagement-specific ask.

- **CF-40** --- **ASN-based scoring tuning pass**. Now that enrichment is in place, scoring weights like `SuspiciousASN` or `HostingASN` or `ResidentialASN` become possible. The decision is engagement-specific --- Cloudflare/AWS/Azure are legitimate for most apps but common for C2 too. Premise: scoring decisions need per-engagement context; no universal rule. Premise collapses if: an operator asks for a scoring bump on a specific ASN range, or a corpus of labeled "malicious C2 by ASN" data becomes available. Phase: Tuning pass (batch with CF-16, CF-19, CF-40).

- **CF-41** --- **Document the PoC-first workflow in a short README section**. The PoC-first rule is in `ai/process.md` but the practical workflow (write to `output/_poc_*.ps1`, test against real data, commit the PoC alongside the feature, re-run as regression test) isn't documented anywhere a new collaborator would find it. Premise: the rule is only useful if it's discoverable from outside the ai/ subject tree. Premise collapses when: the graduation pass reorganizes the docs (CF-23). Phase: graduation pass.

### Retired (premise collapsed before this phase)

- **CF-32** --- already retired in phase15 (ghost CF, never defined)

---

## What Would Have Caught a Regression Here?

Applying `process.md#bug-fix-reflections-must-answer-what-would-have-caught-this` even though I didn't hit a regression:

1. **If Cymru changed their TXT format** --- the `_poc_cymru_dns.ps1` script is the canonical test. Re-running it is the fastest way to detect a format drift. Would catch the bug in ~2 seconds vs debugging a live triage run.

2. **If `Resolve-DnsName` dropped `-QuickTimeout`** in a future PS version --- parser would still pass, PoC would still pass (it uses the same cmdlet), but Tier 2 would show longer duration. Would need to diff unit duration between versions.

3. **If an edit broke the `Add-Member` call for any row field** --- the JSON inspection script (`_inspect_asn_fields.ps1`) asserts all four fields exist on the first row and counts with-vs-without distribution. Running it after any `U-EnrichConnectionsASN` edit catches shape regressions.

4. **If the `$script:NetworkLookupsEnabled` variable got renamed** --- Tier 1 dry-run with `-NoNetworkLookups` would fail the "ASN_ENRICH_SKIPPED" log line check. The log line is the contract. (I didn't write this as an automated Tier 1 assertion --- it's a manual verification. Should probably be codified.)

5. **If the signer cache extraction broke `ProcessInTempOrAppData`** --- CF-33's refactor replaced 13 lines of inline code with one closure call. A bug in the closure would have broken BOTH sites. Verification: Tier 1 dry-run shows `ProcessInTempOrAppData` still fires on unsigned temp/appdata binaries (it did --- the top-5 still lists the pre-existing two High findings with that flag).

The fifth item is the most important --- a refactor that touches a working rule should verify the rule still fires correctly. I did this implicitly by checking the top-5 still contained `ProcessInTempOrAppData` High findings, but it deserves to be explicit in the verification plan.

---

## Proposed Rule Additions

### `heuristics.md` addition: "Never call an external service for non-public inputs"

> **When:** Building an enrichment unit that calls an external API, DNS resolver, or remote service.
> **Rule:** Write the skip-list before the call-site. Non-public inputs (RFC1918, loopback, link-local, CGNAT, multicast, reserved) must short-circuit *before* a DNS/HTTP/TCP connection is attempted. Two reasons: (1) external services don't answer for private inputs (waste), (2) sending private inputs to external services leaks internal topology (footprint). The skip-list is not a performance optimization --- it's a zero-footprint default.
> *Source: phase16_asn_enrichment_and_killswitch.md --- pitfall #2*

### `process.md` addition: "Shipped features need a stable output schema regardless of feature-flag state"

> **When:** Adding a feature behind a kill-switch or feature flag.
> **Rule:** The output schema (JSON shape, row fields, log line names) must be identical whether the flag is on or off. Set fields to `$null` in the off-path, don't omit them. Downstream consumers should not have to conditionally handle "might or might not exist." The flag controls behavior, not shape.
> *Source: phase16_asn_enrichment_and_killswitch.md --- pitfall #3*

### `process.md` addition: "Refactors triggered by a second caller should verify the first caller still works"

> **When:** Extracting a shared helper because a new site needs the same logic as an existing site.
> **Rule:** After the refactor, verify the ORIGINAL site still behaves correctly --- not just the new one. The refactor's job is "do the same thing in two places," and "same thing" needs evidence. A Tier 1/2 run that exercises the original site's behavior (e.g., the original flag still fires on the original trigger) is the minimum bar.
> *Source: phase16_asn_enrichment_and_killswitch.md --- "what would have caught a regression #5"*

These three rules will land in the next documentation pass, not inline in this reflection. Marking them here so they don't get lost.

---

## Files Changed

| File | Change |
|------|--------|
| `modules/Invoke-BotnetTriage.ps1` | (1) Added `-NoNetworkLookups` parameter (CF-34); (2) Published `$script:NetworkLookupsEnabled` flag in `U-LoadConfig` with explicit INFO log; (3) Added `U-EnrichConnectionsASN` unit in Phase C Processing, between `U-ApplyExclusions` and `U-ScoreFindings`; (4) Added `$embeddedBrowserPattern` + signer-gated check in `U-ConnectionsSnapshot` for CF-33; (5) Extracted `$testTrustedSigner` closure, replaced inline signer block in `ProcessInTempOrAppData` with one-line call |
| `output/_poc_cymru_dns.ps1` | NEW --- CF-31 methodology proof-of-concept (keeps as permanent regression test) |
| `output/_inspect_asn_fields.ps1` | NEW --- JSON field inspection script for ASN enrichment verification |
| `output/_inspect_cf33.ps1` | NEW --- msedgewebview2 allowlist + live signer verification script |
| `lessons_learned/phase16_asn_enrichment_and_killswitch.md` | NEW --- this file |

No config file changes (enrichment is context-only, no scoring contribution this phase).

---

## Next Phase Readiness

- Phase 1.3 closed (CF-31, CF-33, CF-34). CF-28 deferred with live premise.
- Phase 1.4 candidate scope: CF-28 (if baseline data becomes available), CF-39 (IPv6 Cymru), CF-40 (ASN scoring tuning), or the graduation cluster (CF-21, CF-23, CF-24, CF-30).
- No hard blockers for the graduation cluster --- all four share the same atomic premise per phase15. Could be the next pass.
- CF-18 (U-CorrelateIOCs / ListeningPorts comment) is still marked "catch in any U-CorrelateIOCs diff" --- I touched `U-CorrelateIOCs` tangentially this phase (it runs after my new enrichment unit) but didn't read it. If the next phase edits that unit, remember to add the comment.
