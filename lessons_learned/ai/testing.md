---
name: testing
description: Verification rules covering multi-tier non-redundancy, mock-data realism, fresh-process isolation, and where test fixtures live in the repo.
type: ai-subject
---

# Testing — Subject Rules

Rules for designing verification suites in this toolkit. Anchor topics: multi-tier verification (each tier excludes a different bug class), mock IOC realism, standalone-paste isolation, and fixture privacy.

---

## Multi-Tier Verification

### Each tier must exclude a different bug class

**When:** Designing a verification plan with more than one tier (dry-run, real-run, schema check, paste, etc.).
**Rule:** If two tiers exclude the same bug class, one is redundant. If a class isn't excluded by any tier, it ships. Map each tier explicitly to the bug class it owns. Phase 8 caught a broken IOC correlation in Tier 2a (real-run with IOCs) that Tier 2 (real-run no IOCs) had silently passed.

**Companions:** standalone-fallback verification

*Source: phase08_verification_tiers.md#1*

---

### Mock IOC files must contain real entries from the test host

**When:** Building a mock IOC file for verification (`_tier2a_iocs.txt`).
**Rule:** Every IOC must match something on the host the test runs against — pull a real DNS cache entry, a real listening port, etc. Synthetic IOCs that match nothing yield a vacuous pass: every step works, the JSON shows zero matches, and you celebrate a green tier that proves nothing.

```powershell
# Pull a real DNS entry from the test host first:
(Get-DnsClientCache | Select-Object -First 1).Entry  # → e.g. 'api.anthropic.com'
# Put THAT in the mock IOC file.
```

*Source: phase08_verification_tiers.md#2*

---

### AST parse-check before re-running a tier

**When:** Edited a script and about to re-run a verification tier that takes >1s.
**Rule:** `[System.Management.Automation.Language.Parser]::ParseFile(...)` first. Sub-100ms vs 13s+ per real-run cycle. Cheapest possible regression test on every edit. Catches typos before they waste a tier-run.

*Source: phase08_verification_tiers.md#3*

---

## Standalone-Paste Verification

### If standalone-paste is load-bearing, the standalone tier is non-optional

**When:** Editing the body of a function that ships in a standalone-paste path, and the edit may add a helper call.
**Rule:** Re-run the standalone-paste tier. New helper calls escape inline-fallback coverage silently — they work fine in normal load (because `_Shared.ps1` is loaded) but throw "not recognized" the first time anyone pastes. Phase 8 caught `Invoke-PhaseGate` missing-stub this way.

*Source: phase08_verification_tiers.md#4pitfall*

---

### Helper-stub guards make stubs invisible in normal load path

**When:** Inline fallback stubs are wrapped in `if (-not (Get-Command Name))` guards.
**Rule:** The stub bodies never execute in the normal load path — only standalone-paste exercises them. Therefore *only* the standalone-paste tier can find a bug in a stub body. Stub edits without re-running Tier 5 are dead-reckoning.

*Source: phase08_verification_tiers.md#4*

---

### Standalone-paste tier must spawn a literal fresh pwsh -NoProfile child

**When:** Implementing the standalone-paste verification tier.
**Rule:** Use `Start-Process pwsh -ArgumentList '-NoProfile','-File',$childScript` — a fresh OS process. Runspaces inherit `$env:PSModulePath` and silently mask missing-stub bugs because the parent's loaded modules leak into the child runspace. The literal-fresh-process gap is the whole point of the tier.

*Source: phase08_verification_tiers.md#3design*

---

## Fixture Privacy

### Test fixtures live in unconditionally-ignored dirs

**When:** Storing mock IOCs, smoke-test scripts, sample outputs for verification.
**Rule:** Put them in `output/` (gitignored unconditionally), not `iocs/` (only partially gitignored — the template ships). Defends against future `.gitignore` edits accidentally exposing engagement data; keeps the privacy boundary clean and defensible.

*Source: phase08_verification_tiers.md#2design*

---
