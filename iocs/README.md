# iocs/ — IOC File Staging

This folder holds engagement-specific IOC files used by the Network Forensics
Toolkit modules. Only `iocs_template.txt` and this README ship in the repo.
Every other file here is gitignored — IOC lists can contain client-identifying
context and MUST NOT be committed.

## What belongs here

- **`iocs_template.txt`** — the canonical format reference. Committed. Copy
  it to start a new engagement IOC file.
- **`<engagement>.txt`** — your working IOC file for a specific engagement
  (e.g. `acme_2026-04.txt`). Gitignored.
- **`README.md`** — this file.

## How operators use it

### 1. Start from the template

```powershell
cd iocs
Copy-Item iocs_template.txt .\acme_2026-04.txt
```

Edit `acme_2026-04.txt` in place. Strip the example indicators at the bottom
of the template before running anything against it — those example IPs are
documentation placeholders, not real bad actors.

### 2. Reference it from a module invocation

```powershell
Invoke-BotnetTriage -IOCFile ".\iocs\acme_2026-04.txt"
```

The loader is tolerant: missing file → warning + continue, malformed line →
skip + log, empty file → all findings produced with no IOC multiplier applied.
A missing IOC file should **never** abort a triage run.

### 3. Distribute IOC files out of band

Because `iocs/*` is gitignored (except the template and this README),
engagement IOCs don't ride along with a `git clone`. Distribute them via:

- secure team messaging (e.g. encrypted Slack DM to the responder on shift),
- case-management upload (the engagement's ticket attachment), or
- copy-paste into a remote shell (powershell one-liner to write the file
  into `$env:TEMP` before running the module standalone).

Never commit `iocs/<engagement>.txt` to this repo, even privately — treat it
the same as `.env`.

## Indicator format quick reference

See `iocs_template.txt` for the authoritative format documentation. One-line
summary:

| Line shape | Meaning |
|---|---|
| `# anything` | comment — ignored |
| `(blank)` | ignored |
| `192.0.2.15` | IPv4 |
| `192.0.2.0/24` | IPv4 CIDR |
| `2001:db8::1` | IPv6 |
| `evil.example.com` | domain |
| `https://evil.example.com/x` | URL |
| 32 hex chars | MD5 |
| 40 hex chars | SHA1 |
| 64 hex chars | SHA256 |

Indicators are matched case-insensitively. No inline comments — put each
comment on its own line above the indicator it annotates.

## What cross-references what (Phase 1)

`Invoke-BotnetTriage` cross-references IOCs against these data sources:

- **TCP connection remote IPs** (IP / CIDR indicators)
- **DNS client cache** (domain and IP indicators)
- **Hosts file entries** (domain indicators)
- **Scheduled task / service command lines** (URL and domain indicators)

A match acts as a **score multiplier** on the finding, not a standalone
finding. The module still flags suspicious state (e.g. a process running
from `%TEMP%` with a network connection) whether or not the remote IP is
in your IOC list — IOCs just make already-suspicious findings score higher.

Hash indicators are accepted by the loader but not used in Phase 1. They
carry forward to Phase 2 (`Invoke-C2BeaconHunt` + threat-intel enrichment).
