---
name: heuristics
description: Detector and scoring rules — false-positive rate ceilings, dead-flag detection, threshold/floor consistency, cross-stage data-flow pitfalls, and enrichment-lookup design (allowlist vs blocklist, fallback semantics, operational footprint).
type: ai-subject
---

# Heuristics — Subject Rules

Rules for designing detectors, scoring weights, and risk classifiers in this toolkit. Anchor topics: false-positive rate ceilings, dead-code flags, threshold/floor math consistency, and architecture pitfalls in cross-stage data flows.

---

## False-Positive Discipline

### Any detector firing on >10% of input is broken

**When:** Adding or tuning a heuristic detector (suspicious-process, raw-IP-DNS, listening-port-on-all-interfaces, etc.).
**Rule:** Corpus-check against a clean baseline host before ship. If the detector fires on >10% of its input, the threshold is wrong, the rule is wrong, or the population is wrong — fix one of those. High-fire detectors train operators to ignore the column.

*Source: phase06_invoke_triage_build.md#3*

---

### Flags not in the weights file are dead code with negative value

**When:** A detector emits a flag (e.g. `'SuspiciousArgs'`) that has no corresponding entry in `triage-weights.json`.
**Rule:** Delete the emit code. The flag consumes operator attention column-space without influencing the verdict — strictly worse than not flagging. Either add the weight or delete the detector. Don't ship dead flags.

*Source: phase06_invoke_triage_build.md#3*

---

## Threshold Math

### Thresholds and floors must be checked against each other

**When:** Tuning IOC-match multipliers, score floors, or verdict thresholds.
**Rule:** Run the math on edge cases. A 10×2.0=20 IOC-only floor lands in `Low` when `Medium=25` — operator sees an IOC match flagged `Low` and assumes the tool is broken. Each multiplier change demands a re-check of every threshold downstream. Check before ship; lurks until pipeline test otherwise.

*Source: phase08_verification_tiers.md#3pitfall*

---

## Cross-Stage Architecture Pitfalls

### Cross-stage filter that's correct in isolation can be wrong in pipeline

**When:** A collection unit filters out "uninteresting" rows before storing them, and a later processing unit (`U-CorrelateIOCs`) needs to see those rows.
**Rule:** Test the pipeline end-to-end with data only visible via the cross-stage path. Each unit can pass its own unit test and the pipeline still be broken — the bug is the *interaction*. Add an `iocHit` pre-retain check at every collection unit that downstream IOC correlation will scan.

```powershell
$iocHit = ($script:IOCSet.Count -gt 0 -and $entry -and $script:IOCSet.Contains([string]$entry))
if ($flags.Count -gt 0 -or $iocHit) { ... store item ... }
```

**Symptom:** `IOC_CORRELATED: 0 finding(s)` despite a known IOC being in live data.

*Source: phase08_verification_tiers.md#2pitfall*

---

### Concentrate fallback complexity on the canonical no-launcher path

**When:** Tempted to add inline-fallback stubs to every script in the toolkit "for safety."
**Rule:** Identify the *one* file that IS the standalone-paste path (e.g. `Invoke-BotnetTriage.ps1`) and concentrate all fallback complexity there. Other files can assume their dependencies are loaded. Some files ARE the fallback; the rest are normal-load.

*Source: phase07_deploy_launcher.md#2design*

---

## Enrichment & Operational Footprint

### Prefer protocols the endpoint already needs over protocols at the perimeter

**When:** Choosing a data source for an enrichment lookup (ASN, GeoIP, reputation) that must work on hardened or possibly-compromised endpoints.
**Rule:** Prefer channels the endpoint *already needs* for normal operation — DNS, NTP — over channels the perimeter may block (HTTPS to a third-party API host). Team Cymru's `<reverse-ip>.origin.asn.cymru.com` TXT record is the canonical example: an analyst workstation and a hardened endpoint both already resolve DNS, so the lookup succeeds in environments where `api.ipinfo.io` would not. The lookup that works on the hardened endpoint is the one that uses channels the perimeter *had* to permit.

*Source: phase13_external_pattern_borrow.md#finding1*

---

### Allowlist the small finite normal set; blocklist the bad set only when bad is smaller

**When:** Designing a filter or scoring rule for enrichment data (ASN, certificate issuer, signer name, etc.).
**Rule:** Threat-model "find an attacker hiding in legitimate traffic" → allowlist legitimate operators (~10–20 ASNs cover most cloud/CDN traffic) and surface everything else. Threat-model "block known bad" → blocklist the bad set. Choose the cardinality that's smaller and slower-changing — for endpoint-triage threat models, that's almost always the legitimate-operator allowlist. Blocklists of bad IPs decay daily; allowlists of legitimate ASNs decay over years.

*Source: phase13_external_pattern_borrow.md#finding2*

---

### Document fallback semantics: degraded answer vs different answer

**When:** Designing a fallback path for a lookup whose primary source can fail (Cymru → /24, RDNS → IP, etc.).
**Rule:** Distinguish a *degraded* answer (same question, less precision) from a *different* answer (related question, full precision). BGP `/20` says "Cloudflare owns this." `/24` fallback says "this address is in the same neighborhood as that one." Both are full answers to legitimate clustering questions. Document the fallback's semantic — operators should know whether they're seeing a worse answer or a different one.

*Source: phase13_external_pattern_borrow.md#finding3*

---

### A detection tool's enrichment lookups are part of the tool's observable footprint

**When:** Adding any enrichment that issues network requests (DNS, HTTP, WHOIS) from a detection or triage tool that runs on the target endpoint.
**Rule:** Every enrichment lookup is a query *from the tool itself*, visible in the endpoint's DNS log / proxy log / packet capture. On a noisy host that's invisible; on a quiet IR target it is a behavioral signal that triage is being performed. Document the footprint in the README and module header. Provide a `-NoNetworkLookups` kill-switch that disables external enrichment for low-footprint runs. The tradeoff "score quality vs operator stealth" must be operator-controlled, not a default.

*Source: phase13_external_pattern_borrow.md#finding4*

---
