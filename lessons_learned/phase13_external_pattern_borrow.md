---
name: phase13_external_pattern_borrow
description: Reflection on what was learned by reading Ghost-Glitch04/Digital-Forensics/Parse-Entra-Sign-In_V3.py --- a peer's IP-to-ASN enrichment script for Entra sign-in log forensics. Captures the Team Cymru DNS technique, the legitimate-ASN-allowlist design pattern, the /24-as-universal-fallback rule, and the meta-lesson about peer code from adjacent domains as a learning vector. Re-shapes CF-31 from "Phase 2, requires offline DB" to "Phase 1.3, no DB needed."
type: reflection
---

# phase13_external_pattern_borrow --- Reading Peer Code from an Adjacent Domain

> **Scope:** Not a code-change reflection. The operator shared a Python script from a different forensics tool (`Parse-Entra-Sign-In_V3.py`) and asked me to reflect on what I learned by reading it. The script solves an adjacent problem (sign-in log triage, not endpoint triage), but its IP-to-ASN enrichment technique ports directly to botnet-detection's missing third axis (CF-31). The durable lessons split into two camps: (a) concrete techniques to import, (b) the meta-process of treating peer code as a knowledge channel.
> **Date:** 2026-04-09
> **Triggered by:** Operator shared `https://github.com/Ghost-Glitch04/Digital-Forensics/tree/main/Parse-Entra-Sign-In` after CF-31 (ASN enrichment) was discussed as a Phase 2 deferral.
> **Source script:** `Parse-Entra-Sign-In_V3.py` --- specifically `cymru_lookup`, `_fallback_subnet`, and the dedupe-by-CIDR pipeline stage.

---

## Applied Lessons

| Rule (file -> heading) | Outcome | Note |
|------------------------|---------|------|
| heuristics.md --- thresholds and floors must be checked against each other | **Applied predictively** | The "legitimate ASN allowlist" pattern needs threshold math: which ASNs cover 80% of legitimate traffic, what's the score impact of "ASN not in allowlist," does it ever push a clean Microsoft connection into Medium? Pre-flight check before Phase 1.3 ships. |
| heuristics.md --- any detector firing on >10% of input is broken | **Re-applied as design constraint** | A `SuspiciousAsn` flag will fire on every connection where ASN is unknown. On a clean baseline, that may be most rows (we don't know yet). Must corpus-check the allowlist before ship --- same rule that closed CF-29. |
| process.md --- when two planning docs disagree, read the committed file | **Re-applied as cross-tool variant** | When my mental model ("ASN enrichment is hard / requires offline DB / requires API key") conflicts with a peer's working code that uses neither, the peer's code is ground truth. My mental model was the planning doc; the script was the committed file. |
| heuristics.md --- concentrate fallback complexity on the canonical no-launcher path | **Generalizable to enrichment** | The `_fallback_subnet` pattern (Cymru -> /24) is the same shape as standalone-fallback: one canonical path holds the fallback, callers stay simple. Phase 1.3's ASN unit gets one fallback, not five. |

---

## What I Knew vs What the Script Taught

### What I knew (and was wrong about)
- "ASN enrichment requires MaxMind GeoIP2 / IPinfo / similar."
- "Either you bundle a 50MB DB and update it monthly, or you pay for an API and add an internet egress dependency."
- "Therefore CF-31 is Phase 2 work, defer until the offline-DB question is answered."

### What the script taught
- **Team Cymru DNS** (`<reversed-ip>.origin.asn.cymru.com` TXT record) returns `ASN | BGP-CIDR | country | registry | date` in a single DNS query.
- No API key, no rate limit, no DB, no external HTTP egress.
- Uses DNS, which is a hard requirement for the endpoint to function at all.
- `nslookup -type=TXT <query>` from any standard endpoint, no extra tooling.
- The full Python implementation is ~30 lines. PowerShell port: `Resolve-DnsName -Type TXT` and a regex parse, ~25 lines.

The premise underneath my "Phase 2 deferral" was wrong. CF-31 is now a Phase 1.3 candidate. **One peer script collapsed a phase boundary.**

---

## Findings

### Finding 1: DNS-as-enrichment is a deployment-friendly third axis

The script's choice of DNS over HTTP-API for ASN lookup isn't a clever trick --- it's the obvious choice once you accept the constraint that the lookup must work on hardened endpoints. HTTP egress to `api.ipinfo.io` may be blocked. DNS to `*.cymru.com` is rarely blocked because the endpoint already needs to resolve `microsoft.com`, `windowsupdate.com`, etc. The two channels have very different blast radii at the perimeter.

**Generalizable rule:** When choosing an enrichment data source for a tool that runs on possibly-restricted endpoints, prefer protocols the endpoint *already needs* for normal operation (DNS, NTP) over protocols that may be blocked at the perimeter (HTTPS to a third-party host). The lookup that works on the hardened endpoint is the one that uses channels the perimeter *had* to permit.

-> Lives in: **heuristics.md**, new "Enrichment & Operational Footprint" section.

---

### Finding 2: Legitimate-ASN allowlist > IP blocklist

The script's filter logic is "if Cymru-verified ASN is in the legitimate set, drop the row." Not "if IP is in a blocklist, flag it." The asymmetry matters:

- **Blocklist of bad IPs:** unbounded, decays daily, requires constant updating, misses anything new.
- **Allowlist of good ASNs:** ~10-20 entries cover the vast majority of legitimate cloud/CDN traffic (Microsoft 8075, Akamai 16625, Cloudflare 13335, Google 15169, Meta 32934, ...), decays slowly, surfaces everything new.

The same Cymru data can drive either. The script picks allowlist because the threat model is "find an attacker hiding in legitimate traffic," not "block known bad guys at the firewall." Botnet-detection has the same threat model.

**Generalizable rule:** When the threat model is "find an anomaly in a sea of normal," allowlist the *small finite normal set* and surface everything else. When the threat model is "block known bad," blocklist the bad set. Choose the cardinality that's smaller and slower-changing --- almost always the allowlist of legitimate operators.

-> Lives in: **heuristics.md**.

---

### Finding 3: /24 is the universal fallback for IP clustering

```python
def _fallback_subnet(ip: str) -> Optional[str]:
    addr = ipaddress.ip_address(ip)
    prefix = 24 if isinstance(addr, ipaddress.IPv4Address) else 64
    return str(ipaddress.ip_network(f"{ip}/{prefix}", strict=False))
```

When the BGP-announced prefix is unavailable, the script falls back to /24 (IPv4) or /64 (IPv6) --- coarse-but-still-clusterable. The fallback isn't a *degraded* answer; it's a *different* answer to a slightly different question. BGP /20 says "Cloudflare owns this." /24 says "this address is in the same neighborhood as that other address." Both are useful for clustering, and the operator may prefer one over the other depending on what they're tracking.

**Generalizable rule:** When designing a fallback for a lookup, ask whether the fallback answers the same question more coarsely (degraded) or a related question completely (different). /24-vs-BGP is the latter --- both are full answers to legitimate questions. Document the fallback's *semantic*, not just its trigger condition.

-> Lives in: **heuristics.md**.

---

### Finding 4: Enrichment generates its own observable footprint

The script runs on an analyst workstation parsing a CSV. Its DNS queries to `cymru.com` are invisible --- the workstation already does thousands of DNS queries an hour. **Botnet-detection runs on a possibly-compromised endpoint**, which changes the calculus:

- Every Cymru lookup we make is a DNS query *from the triage tool itself*.
- An attacker watching the endpoint's DNS log will see `1.1.1.1.in-addr.arpa.origin.asn.cymru.com` appear immediately after we run.
- This is a behavioral signal that triage is being performed.
- On a noisy endpoint that signal is invisible. On a quiet IR target where the operator wants minimal footprint, it is not.

**Generalizable rule:** A detection tool's enrichment lookups are part of the tool's observable footprint *on the target*. Document them. Provide a kill-switch (`-NoNetworkLookups`) that disables external enrichment for low-footprint runs. The tradeoff is "score quality vs operator stealth" --- make it the operator's choice, not a default.

-> Lives in: **heuristics.md**. Also a new carry-forward (CF-34).

---

### Finding 5: Reading peer code from adjacent domains is a high-value learning vector

This is the meta-lesson and the one I am most likely to forget without writing it down. The script solves an adjacent problem (sign-in logs, not endpoint triage). I would not have found it by searching for "PowerShell ASN lookup" --- it's Python, lives in a different repo, and is named for a different use case. It came to me only because the operator shared it.

The technique it taught (Cymru DNS) is one I had never encountered in any documentation, blog post, or PowerShell tutorial that surfaced in my training. It's "trade knowledge" --- known to people who do IP forensics, invisible to people who don't. **The fastest way to acquire trade knowledge is to read code written by someone in the trade**, regardless of language or use case.

**Generalizable rule:** When the operator (or a colleague) shares code from an adjacent forensics/security domain, *read it for techniques even if the use case is unrelated*. Map the technique to your problem space; it usually ports. The cost of reading 200 lines of peer code is 5 minutes; the value of learning a previously-unknown enrichment channel is months of avoided wrong-direction work.

-> Lives in: **process.md** under "Lessons-Learned Cadence."

---

### Finding 6: Carry-forwards must record their premise, not just their deferral

CF-31 was originally written as "Phase 2 --- requires offline DB or API." That premise (`requires DB or API`) was a *load-bearing assumption*. When the assumption fell, the entire deferral fell with it. The lesson is not "I was wrong about CF-31"; the lesson is **carry-forwards based on cost premises must include the premise so it can be challenged later**.

A CF that says only "deferred to Phase 2" hides the *reason* and is hard to revisit. A CF that says "deferred to Phase 2 *because requires offline DB*" exposes the premise; if a peer shares a script that doesn't need a DB, the CF can be re-evaluated immediately. Premises decay; deferrals shouldn't outlive their premises silently.

**Generalizable rule:** When deferring work to a future phase, write the *premise* of the deferral, not just the deferral. "Phase 2 because X" is reviewable. "Phase 2" is opaque. On every phase boundary, walk open carry-forwards and re-test the premise --- not just the deferral.

-> Lives in: **process.md** under "Lessons-Learned Cadence." Also a new carry-forward (CF-35).

---

## Carry-Forward Updates

- **CF-31 (was):** Phase 2 --- ASN/GeoIP enrichment to surface cloud CDN vs residential/hosting ASN per connection. Adds a third axis. Requires offline DB or API.
- **CF-31 (now):** **Phase 1.3** --- ASN enrichment via Team Cymru DNS TXT-record query (`Resolve-DnsName -Type TXT <reversed-ip>.origin.asn.cymru.com`). No DB, no API key, no new dependency. Adds `Asn`, `AsnOrg`, `BgpCidr`, `Country` fields to connection rows; adds `SuspiciousAsn` flag when ASN is not in `LegitimateAsns` allowlist (~15 entries: Microsoft 8075, Akamai 16625, Cloudflare 13335, Google 15169, Meta 32934, etc.). Falls back to /24 when DNS lookup fails or `-NoNetworkLookups` is set. Borrowed approach: `Ghost-Glitch04/Digital-Forensics/Parse-Entra-Sign-In_V3.py`.

- **CF-34 (NEW):** Document the operational footprint of enrichment lookups in README and module header. Add `-NoNetworkLookups` kill-switch to Phase 1.3. Required because enrichment runs on a possibly-compromised endpoint, not an analyst workstation --- the tradeoff "score quality vs operator stealth" must be operator-controlled.

- **CF-35 (NEW):** Audit existing carry-forwards for unstated premises. CF-31 was "deferred because hard"; the actual premise ("hard *because* needs DB") was implicit and turned out to be wrong. Walk every open CF and append the premise that justifies the deferral, so future-Claude can challenge it when premises change.

---

## What This Reflection Did Not Cover

- The Phase 1.2 ship reflection (connection enrichment, parent/cmdline context, BeaconWhitelist plumbing) --- separate phase file, deferred until after Phase 1.3 scope is locked.
- The Phase 1.2 verification details (clean VM run output) --- those went in the conversation thread; the operator already has them.
- A line-by-line port of the Cymru lookup function to PowerShell --- belongs in the Phase 1.3 implementation plan, not in a reflection.
- An update to README's deployment-paths section with the new `-NoNetworkLookups` switch --- ships with Phase 1.3.
