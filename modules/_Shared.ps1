<#
.SYNOPSIS
    Authoritative shared helper library for the Network Forensics Toolkit.

.DESCRIPTION
    Dot-sourced by Deploy.ps1 before any Invoke-*.ps1 module. Defines the
    canonical implementations of helpers that multiple modules need:
    logging, config loading, secret retrieval, network utilities, phase
    gating, and output verification.

    Modules also embed minimal *inline stubs* of the critical helpers
    (Write-Log, Get-Secret, Test-IsPrivateIP, Get-ProcessDetails,
    Resolve-Config) so that a single module file can be pasted into a
    remote shell standalone without this file present. When _Shared.ps1
    IS dot-sourced first, the stubs detect the already-defined function
    (via Get-Command) and skip their own re-definition.

    Phase 2 helpers (API enrichment, HTML report, base64 export) ship
    here as empty stubs so that dot-sourcing succeeds in Phase 1. They
    will be fleshed out in Phase 2 without any structural changes to
    this file.

.NOTES
    Author  : Ghost
    Created : 2026-04-09
    Version : 1.0.0

    Error codes (canonical):
      0  = Success
      10 = Input file not found
      11 = Input file unreadable / malformed
      20 = Unit / processing failure
      30 = External service unreachable (Phase 2 only; not used here)
      40 = Output verification failed
      50 = Retry exhausted
      99 = Unhandled error
#>

#Requires -Version 5.1

# NOTE: No `param` block and no `Set-StrictMode` at file scope -- this
# file is dot-sourced into a parent scope (Deploy.ps1 or a standalone
# pwsh session), and strict-mode settings should be chosen by the
# caller, not imposed by the library.


# ============================================================
#region  HELPER: Write-Log
# Purpose : Write timestamped, leveled log entries to console + file.
#           DEBUG entries always write to file when $script:LogFile
#           is set; suppressed from console unless $DebugMode is true.
# Inputs  : -Message (string, mandatory)
#           -Level (DEBUG|INFO|WARN|ERROR|FATAL, default INFO)
# Outputs : None (side effect: writes to $script:LogFile and console)
# Depends : Optional $script:LogFile (file write is skipped if unset)
#           Optional $DebugMode (suppresses DEBUG from console if $false)
#endregion ==================================================
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [Parameter(Position = 1)]
        [ValidateSet("DEBUG","INFO","WARN","ERROR","FATAL")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"

    # Write to file only if the caller has set $script:LogFile.
    # Standalone-paste modules may call Write-Log before any log
    # file is configured; in that case, console-only is fine.
    if ($script:LogFile) {
        try {
            Add-Content -Path $script:LogFile -Value $entry -ErrorAction Stop
        } catch {
            # File write failed (disk full, path denied). Fall back
            # to console-only and flag the failure once per process.
            if (-not $script:LogFileWarnedOnce) {
                Write-Host "[$timestamp] [WARN] Write-Log: log file write failed ($($_.Exception.Message)); continuing console-only" -ForegroundColor Yellow
                $script:LogFileWarnedOnce = $true
            }
        }
    }

    # Suppress DEBUG from console unless DebugMode is active.
    if ($Level -eq "DEBUG" -and -not $DebugMode) { return }

    $color = switch ($Level) {
        "DEBUG" { "Gray" }
        "INFO"  { "White" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
        "FATAL" { "DarkRed" }
        default { "White" }
    }
    Write-Host $entry -ForegroundColor $color
}


# ============================================================
#region  HELPER: Get-Secret
# Purpose : Retrieve a secret from the process environment with
#           masked logging. Safe to call even if the secret is
#           unset -- returns $null rather than throwing.
# Inputs  : -Name (string, mandatory) -- env var name
#           -Required (switch) -- if set, throw when missing
# Outputs : The secret value (string) or $null
# Depends : Write-Log
#endregion ==================================================
function Get-Secret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [switch]$Required
    )

    $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if (-not $value) {
        $value = [Environment]::GetEnvironmentVariable($Name, 'User')
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        if ($Required) {
            Write-Log -Level ERROR -Message "SECRET_MISSING: $Name (required)"
            throw "Required secret '$Name' is not set in environment."
        }
        Write-Log -Level DEBUG -Message "SECRET_MISSING: $Name (optional)"
        return $null
    }

    # Mask for logging: show first 2 + last 2 chars, middle as ***.
    $masked = if ($value.Length -le 6) { '***' }
              else { "$($value.Substring(0,2))***$($value.Substring($value.Length-2,2))" }
    Write-Log -Level DEBUG -Message "SECRET_LOADED: $Name = $masked"

    return $value
}


# ============================================================
#region  HELPER: Test-IsPrivateIP
# Purpose : Return $true if the given address string is private,
#           loopback, link-local, or otherwise non-routable.
#           Handles IPv4 and IPv6.
# Inputs  : -IPAddress (string, mandatory)
# Outputs : [bool]
# Depends : None
#endregion ==================================================
function Test-IsPrivateIP {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$IPAddress
    )

    if ([string]::IsNullOrWhiteSpace($IPAddress)) { return $false }

    $ip = $null
    if (-not [System.Net.IPAddress]::TryParse($IPAddress, [ref]$ip)) {
        return $false
    }

    if ($ip.AddressFamily -eq 'InterNetworkV6') {
        # IPv6 private / loopback / link-local
        if ($ip.IsIPv6LinkLocal) { return $true }
        if ($ip.IsIPv6SiteLocal) { return $true }
        if ([System.Net.IPAddress]::IsLoopback($ip)) { return $true }
        $firstByte = $ip.GetAddressBytes()[0]
        # fc00::/7 -- unique local addresses
        if (($firstByte -band 0xFE) -eq 0xFC) { return $true }
        return $false
    }

    # IPv4
    $bytes = $ip.GetAddressBytes()
    $b0 = $bytes[0]; $b1 = $bytes[1]

    if ($b0 -eq 10)                               { return $true }  # 10.0.0.0/8
    if ($b0 -eq 127)                              { return $true }  # 127.0.0.0/8
    if ($b0 -eq 172 -and ($b1 -ge 16 -and $b1 -le 31)) { return $true }  # 172.16.0.0/12
    if ($b0 -eq 192 -and $b1 -eq 168)             { return $true }  # 192.168.0.0/16
    if ($b0 -eq 169 -and $b1 -eq 254)             { return $true }  # 169.254.0.0/16 link-local
    if ($b0 -eq 0)                                { return $true }  # 0.0.0.0/8
    if ($b0 -ge 224)                              { return $true }  # 224/4 multicast, 240/4 reserved

    return $false
}


# ============================================================
#region  HELPER: Get-ProcessDetails
# Purpose : Return a normalized object describing a process by PID:
#           name, path, command line, parent PID, user, signer.
#           Access-denied on any sub-lookup degrades to null fields
#           rather than throwing -- triage must survive sandboxed
#           remote shells.
# Inputs  : -ProcessId (int, mandatory)
# Outputs : [pscustomobject] -- may have null fields on partial failure
# Depends : Write-Log (used only for DEBUG on sub-failures)
#endregion ==================================================
function Get-ProcessDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ProcessId
    )

    $result = [pscustomobject]@{
        ProcessId    = $ProcessId
        Name         = $null
        Path         = $null
        CommandLine  = $null
        ParentPid    = $null
        User         = $null
        SignerStatus = $null
        SignerName   = $null
        Error        = $null
    }

    try {
        $cim = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop
        if ($cim) {
            $result.Name        = $cim.Name
            $result.Path        = $cim.ExecutablePath
            $result.CommandLine = $cim.CommandLine
            $result.ParentPid   = $cim.ParentProcessId

            # Owner lookup can fail with access denied -- degrade quietly.
            try {
                $owner = Invoke-CimMethod -InputObject $cim -MethodName GetOwner -ErrorAction Stop
                if ($owner -and $owner.ReturnValue -eq 0) {
                    $result.User = if ($owner.Domain) { "$($owner.Domain)\$($owner.User)" } else { $owner.User }
                }
            } catch {
                if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                    Write-Log -Level DEBUG -Message "GET_OWNER_FAILED: PID=$ProcessId | $($_.Exception.Message)"
                }
            }

            # Signer lookup (best-effort) -- only if path is present and readable.
            if ($result.Path -and (Test-Path $result.Path -ErrorAction SilentlyContinue)) {
                try {
                    $sig = Get-AuthenticodeSignature -FilePath $result.Path -ErrorAction Stop
                    $result.SignerStatus = [string]$sig.Status
                    $result.SignerName   = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { $null }
                } catch {
                    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                        Write-Log -Level DEBUG -Message "GET_SIGNATURE_FAILED: PID=$ProcessId Path='$($result.Path)' | $($_.Exception.Message)"
                    }
                }
            }
        }
    } catch {
        $result.Error = $_.Exception.Message
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log -Level DEBUG -Message "GET_PROCESS_DETAILS_FAILED: PID=$ProcessId | $($_.Exception.Message)"
        }
    }

    return $result
}


# ============================================================
#region  HELPER: Resolve-Config
# Purpose : Load a JSON config file with a hashtable fallback.
#           If the file is missing or unparseable, returns the
#           supplied fallback. Emits a warning on fallback.
# Inputs  : -Path (string, mandatory) -- path to JSON file
#           -Fallback (hashtable) -- returned when file unusable
#           -Label (string) -- friendly name for log messages
# Outputs : [pscustomobject] or [hashtable]
# Depends : Write-Log
#endregion ==================================================
function Resolve-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [hashtable]$Fallback = @{},

        [string]$Label = (Split-Path $Path -Leaf)
    )

    if (-not (Test-Path $Path)) {
        Write-Log -Level WARN -Message "CONFIG_MISSING: $Label | Path: '$Path' | Using inline fallback defaults"
        return $Fallback
    }

    try {
        $content = Get-Content -Path $Path -Raw -ErrorAction Stop
        $parsed  = $content | ConvertFrom-Json -ErrorAction Stop
        Write-Log -Level DEBUG -Message "CONFIG_LOADED: $Label | Path: '$Path'"
        return $parsed
    } catch {
        Write-Log -Level WARN -Message "CONFIG_MALFORMED: $Label | Path: '$Path' | $($_.Exception.Message) | Using inline fallback defaults"
        return $Fallback
    }
}


# ============================================================
#region  HELPER: Invoke-WithRetry
# Purpose : Execute a script block with exponential backoff retry.
#           Used by Phase 2 API callers. Distinguishes transient
#           failures (retry) from fatal ones (stop).
# Inputs  : -ScriptBlock, -OperationName, -MaxAttempts, -DelaySeconds
# Outputs : Return value of ScriptBlock on success; exits 50 on exhaustion
# Depends : Write-Log
#endregion ==================================================
function Invoke-WithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory)][string]$OperationName,
        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 5
    )

    $attempt = 0
    while ($attempt -lt $MaxAttempts) {
        $attempt++
        try {
            Write-Log -Level DEBUG -Message "RETRY: $OperationName | Attempt $attempt of $MaxAttempts"
            return & $ScriptBlock
        } catch {
            if ($attempt -eq $MaxAttempts) {
                Write-Log -Level ERROR -Message "RETRY_EXHAUSTED: $OperationName | All $MaxAttempts attempts failed | Last error: $($_.Exception.Message)"
                exit 50
            }
            $wait = $DelaySeconds * [Math]::Pow(2, $attempt - 1)
            Write-Log -Level WARN -Message "RETRY_WAIT: $OperationName | Attempt $attempt failed | Waiting ${wait}s | Error: $($_.Exception.Message)"
            Start-Sleep -Seconds $wait
        }
    }
}


# ============================================================
#region  HELPER: Import-DotEnv
# Purpose : Parse a .env file into process environment variables.
#           Supports KEY=value, KEY="quoted value", KEY='single',
#           skips comments (#) and blank lines. Missing file ->
#           WARN + return (not FATAL) so standalone-paste path
#           still works.
# Inputs  : -Path (string, mandatory)
# Outputs : [int] count of variables loaded
# Depends : Write-Log
#endregion ==================================================
function Import-DotEnv {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Log -Level WARN -Message "CONFIG_MISSING: .env file not found at '$Path' -- no secrets loaded"
        return 0
    }

    $loaded = 0
    $lines  = Get-Content -Path $Path -ErrorAction Stop
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed.StartsWith('#')) { continue }

        $eq = $trimmed.IndexOf('=')
        if ($eq -lt 1) {
            Write-Log -Level DEBUG -Message "DOTENV_SKIP: malformed line '$trimmed'"
            continue
        }

        $key = $trimmed.Substring(0, $eq).Trim()
        $val = $trimmed.Substring($eq + 1).Trim()

        # Strip surrounding quotes if balanced.
        if ($val.Length -ge 2) {
            $firstChar = $val[0]
            $lastChar  = $val[$val.Length - 1]
            if (($firstChar -eq '"' -and $lastChar -eq '"') -or
                ($firstChar -eq "'" -and $lastChar -eq "'")) {
                $val = $val.Substring(1, $val.Length - 2)
            }
        }

        if ([string]::IsNullOrWhiteSpace($val)) {
            Write-Log -Level DEBUG -Message "DOTENV_EMPTY: $key -- skipped"
            continue
        }

        [Environment]::SetEnvironmentVariable($key, $val, 'Process')
        $loaded++
    }

    Write-Log -Level INFO -Message "DOTENV_LOADED: $loaded variable(s) from '$Path'"
    return $loaded
}


# ============================================================
#region  HELPER: Import-LocalConfig
# Purpose : Merge an example JSON config with an optional local
#           override file. Local values always win. Missing local
#           file is not an error -- the example is returned as-is.
# Inputs  : -ExamplePath (string, mandatory)
#           -LocalPath (string, mandatory)
# Outputs : [pscustomobject] -- merged config
# Depends : Write-Log
#endregion ==================================================
function Import-LocalConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ExamplePath,
        [Parameter(Mandatory)][string]$LocalPath
    )

    if (-not (Test-Path $ExamplePath)) {
        Write-Log -Level WARN -Message "CONFIG_MISSING: example config not found at '$ExamplePath' | Returning empty config"
        return [pscustomobject]@{}
    }

    $example = Get-Content -Path $ExamplePath -Raw | ConvertFrom-Json -ErrorAction Stop

    if (-not (Test-Path $LocalPath)) {
        Write-Log -Level DEBUG -Message "CONFIG_LOCAL_ABSENT: '$LocalPath' -- using example values only"
        return $example
    }

    try {
        $local = Get-Content -Path $LocalPath -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Log -Level WARN -Message "CONFIG_LOCAL_MALFORMED: '$LocalPath' | $($_.Exception.Message) | Falling back to example values"
        return $example
    }

    # Shallow merge: for each property in $local, overwrite the
    # matching property in $example. Nested objects replace whole.
    foreach ($prop in $local.PSObject.Properties) {
        if ($example.PSObject.Properties.Name -contains $prop.Name) {
            $example.$($prop.Name) = $prop.Value
        } else {
            $example | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
        }
    }

    Write-Log -Level INFO -Message "CONFIG_MERGED: example='$ExamplePath' <- local='$LocalPath'"
    return $example
}


# ============================================================
#region  HELPER: Get-MaskedParams
# Purpose : Convert a hashtable of parameter values to a printable
#           string with sensitive values masked. Used for PARAMS
#           log line emission. Canonical pattern list per
#           github-security-standards_V4.
# Inputs  : -Parameters (hashtable, mandatory)
# Outputs : [string] -- "Key1='value1' | Key2='***' | ..."
# Depends : None
#endregion ==================================================
function Get-MaskedParams {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Parameters
    )

    $sensitivePatterns = @(
        'key','secret','password','token','credential','pwd',
        'apikey','auth','bearer','conn_str','connection_string',
        'certificate','pat','sas'
    )

    # Match patterns against camelCase / snake_case segments of the
    # parameter name, NOT as arbitrary substrings. A substring match
    # on short tokens like `pat`, `sas`, `pwd` produces false positives
    # (`InputPath` contains `pat`, `AssessedBy` contains `sas`, etc.).
    # The segment regex extracts runs like "Input","Path","API","Key"
    # from names like "InputPath" or "APIKey"; the full-name exact
    # check handles compound patterns like `connection_string`.
    $parts = foreach ($kv in $Parameters.GetEnumerator()) {
        $nameRaw  = $kv.Key.ToString()
        $nameLc   = $nameRaw.ToLowerInvariant()
        $segments = [regex]::Matches($nameRaw, '[A-Z]?[a-z]+|[A-Z]+(?![a-z])') |
                    ForEach-Object { $_.Value.ToLowerInvariant() }

        $isSensitive = $false
        foreach ($pat in $sensitivePatterns) {
            if ($nameLc -eq $pat -or $segments -contains $pat) {
                $isSensitive = $true; break
            }
        }
        if ($isSensitive) {
            "{0}='***'" -f $kv.Key
        } else {
            "{0}='{1}'" -f $kv.Key, $kv.Value
        }
    }

    return ($parts -join ' | ')
}


# ============================================================
#region  HELPER: Invoke-PhaseStart
# Purpose : Record phase start time and log PHASE_START.
# Inputs  : -PhaseName (string, mandatory)
# Outputs : Sets $script:PhaseTimer; logs PHASE_START
# Depends : Write-Log
#endregion ==================================================
function Invoke-PhaseStart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PhaseName
    )
    $script:PhaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Log -Level INFO -Message "PHASE_START: $PhaseName"
}


# ============================================================
#region  HELPER: Invoke-PhaseGate
# Purpose : Log phase duration and conditionally exit 0 if the
#           caller's $StopAfterPhase param matches. A gate stop
#           is a clean success, not a failure.
# Inputs  : -PhaseName (string, mandatory)
#           -Summary (string, optional) -- freeform detail
# Outputs : Logs PHASE_END; may exit 0 if gate triggered
# Depends : $StopAfterPhase (caller's param scope)
#           $script:PhaseTimer, $script:ScriptTimer, Write-Log
#endregion ==================================================
function Invoke-PhaseGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PhaseName,
        [string]$Summary = ""
    )

    if ($script:PhaseTimer) { $script:PhaseTimer.Stop() }
    $phaseDuration = if ($script:PhaseTimer) { $script:PhaseTimer.Elapsed.TotalSeconds } else { 0 }

    if ($Summary) {
        Write-Log -Level INFO -Message "PHASE_SUMMARY: $PhaseName | $Summary"
    }
    Write-Log -Level INFO -Message "PHASE_END: $PhaseName | Phase Duration: ${phaseDuration}s"

    if ($StopAfterPhase -eq $PhaseName) {
        if ($script:ScriptTimer) { $script:ScriptTimer.Stop() }
        $total = if ($script:ScriptTimer) { $script:ScriptTimer.Elapsed.TotalSeconds } else { 0 }
        Write-Log -Level INFO -Message "PHASE_GATE: Stopping cleanly after phase '$PhaseName' | Total Duration: ${total}s"
        # Signal via tagged terminating error rather than exit, so this works
        # both inside an imported function (caller catches and returns 0) and
        # inside a script (script-level try/catch exits 0). exit at file scope
        # would kill the parent pwsh session of any imported caller.
        $ex = [System.Management.Automation.RuntimeException]::new("PHASE_GATE_REACHED:$PhaseName")
        $er = [System.Management.Automation.ErrorRecord]::new($ex, 'PhaseGateReached', 'OperationStopped', $PhaseName)
        throw $er
    }
}


# ============================================================
#region  HELPER: Verify-JsonOutput
# Purpose : Confirm a JSON file exists, is non-empty, parses as
#           valid JSON, and (optionally) contains a list of
#           required top-level keys. Exits 40 on failure.
# Inputs  : -Path (string, mandatory)
#           -RequiredKeys (string[], optional)
# Outputs : Logs VERIFY_OK or exits 40
# Depends : Write-Log
#endregion ==================================================
function Verify-JsonOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$RequiredKeys = @()
    )

    if (-not (Test-Path $Path)) {
        Write-Log -Level ERROR -Message "VERIFY_FAILED: JSON not found | Path: '$Path'"
        exit 40
    }

    $size = (Get-Item $Path).Length
    if ($size -lt 1) {
        Write-Log -Level ERROR -Message "VERIFY_FAILED: JSON is empty | Path: '$Path'"
        exit 40
    }

    try {
        $parsed = Get-Content -Path $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Log -Level ERROR -Message "VERIFY_FAILED: JSON malformed | Path: '$Path' | $($_.Exception.Message)"
        exit 40
    }

    foreach ($key in $RequiredKeys) {
        if (-not ($parsed.PSObject.Properties.Name -contains $key)) {
            Write-Log -Level ERROR -Message "VERIFY_FAILED: JSON missing required key '$key' | Path: '$Path'"
            exit 40
        }
    }

    Write-Log -Level INFO -Message "VERIFY_OK: JSON output | Path: '$Path' | Size: ${size}B | Keys verified: $($RequiredKeys.Count)"
}


# ============================================================
# ============================================================
#                    PHASE 2 -- STUB HELPERS
# ============================================================
# The following helpers are placeholders so that modules which
# reference them dot-source cleanly in Phase 1. Each emits a
# WARN-level log line and returns a null/empty result. Phase 2
# will replace them with real implementations lifted from the
# upstream network-dfir library.
#
# Any Phase 1 code path that calls one of these is a bug --
# Phase 1 is strictly offline-capable with no enrichment.
# ============================================================


# ============================================================
#region  STUB (Phase 2): Invoke-GeoEnrichment
#endregion ==================================================
function Invoke-GeoEnrichment {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$IPAddress)
    # TODO Phase 2: ip-api.com lookup, returns Country/Region/ISP/ASN
    Write-Log -Level WARN -Message "PHASE2_STUB_CALLED: Invoke-GeoEnrichment is a Phase 2 placeholder | IP=$IPAddress"
    return $null
}


# ============================================================
#region  STUB (Phase 2): Invoke-VirusTotalLookup
#endregion ==================================================
function Invoke-VirusTotalLookup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Indicator,
        [ValidateSet('ip','domain','hash','url')][string]$Kind = 'ip'
    )
    # TODO Phase 2: VT API v3, requires VT_API_KEY secret,
    #               returns reputation / detection counts.
    Write-Log -Level WARN -Message "PHASE2_STUB_CALLED: Invoke-VirusTotalLookup is a Phase 2 placeholder | $Kind=$Indicator"
    return $null
}


# ============================================================
#region  STUB (Phase 2): Invoke-AbuseIPDBLookup
#endregion ==================================================
function Invoke-AbuseIPDBLookup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$IPAddress)
    # TODO Phase 2: AbuseIPDB API, requires ABUSEIPDB_API_KEY,
    #               returns abuseConfidenceScore + recent reports.
    Write-Log -Level WARN -Message "PHASE2_STUB_CALLED: Invoke-AbuseIPDBLookup is a Phase 2 placeholder | IP=$IPAddress"
    return $null
}


# ============================================================
#region  STUB (Phase 2): Invoke-ScamalyticsLookup
#endregion ==================================================
function Invoke-ScamalyticsLookup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$IPAddress)
    # TODO Phase 2: Scamalytics API, requires SCAMALYTICS_USERNAME
    #               + SCAMALYTICS_API_KEY, returns fraud score.
    Write-Log -Level WARN -Message "PHASE2_STUB_CALLED: Invoke-ScamalyticsLookup is a Phase 2 placeholder | IP=$IPAddress"
    return $null
}


# ============================================================
#region  STUB (Phase 2): Invoke-HeuristicScoring
#endregion ==================================================
function Invoke-HeuristicScoring {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Finding,
        $Weights
    )
    # TODO Phase 2: Apply scoring-weights.json rules to beacon
    #               findings. Phase 1 triage has its own inline
    #               scorer driven by triage-weights.json.
    Write-Log -Level WARN -Message "PHASE2_STUB_CALLED: Invoke-HeuristicScoring is a Phase 2 placeholder"
    return 0
}


# ============================================================
#region  STUB (Phase 2): ConvertTo-HtmlReport
#endregion ==================================================
function ConvertTo-HtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][string]$OutputPath,
        [string]$Title = "Network Forensics Report"
    )
    # TODO Phase 2: Dark-theme HTML template lifted from upstream
    #               network-dfir library. Phase 1 outputs JSON only.
    Write-Log -Level WARN -Message "PHASE2_STUB_CALLED: ConvertTo-HtmlReport is a Phase 2 placeholder | OutputPath=$OutputPath"
}


# ============================================================
#region  STUB (Phase 2): Export-Base64Report
#endregion ==================================================
function Export-Base64Report {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][string]$OutputPath
    )
    # TODO Phase 2: Read $InputPath, base64-encode, write to
    #               $OutputPath with chunked line breaks for
    #               safe remote-shell copy-paste exfil.
    Write-Log -Level WARN -Message "PHASE2_STUB_CALLED: Export-Base64Report is a Phase 2 placeholder | In=$InputPath Out=$OutputPath"
}


# End of _Shared.ps1
