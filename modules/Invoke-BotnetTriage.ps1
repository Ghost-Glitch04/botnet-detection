<#
.SYNOPSIS
    Wide-shallow single-pass botnet triage for a Windows endpoint.

.DESCRIPTION
    Invoke-BotnetTriage is the Phase 1 first-responder module of the
    Network Forensics Toolkit. It produces a prioritized High/Medium/Low
    verdict across 8 data sources (connections, listening ports,
    scheduled tasks, services, autoruns, DNS cache, hosts file, local
    accounts) in 30-60 seconds on a typical endpoint.

    Offline-capable by design: no API keys, no threat-intel lookups, no
    outbound network calls. The module exists to answer "is this host
    worth investigating at all, and if so where should I look?" -- NOT
    "is this host beaconing right now, and to where?" The deep question
    is answered by Phase 2's Invoke-C2BeaconHunt.

    Fault-tolerant by unit: if one data-source query fails (common in
    sandboxed remote shells), the failure is logged to the errors array
    and the remaining units continue. A partial triage is still useful.

.PARAMETER OutputDir
    Directory for the JSON artifact and the runtime log. Defaults to
    ..\output relative to this script. Created if missing.

.PARAMETER IOCFile
    Optional path to a line-delimited IOC file (see iocs/iocs_template.txt
    for format). Matching findings receive an IOC score multiplier, not
    a standalone finding category.

.PARAMETER ExclusionsFile
    Optional path to an exclusions JSON (known-good processes, ports,
    trusted signers). Defaults to ..\config\exclusions.json.

.PARAMETER WeightsFile
    Optional path to a triage-weights JSON (per-category risk weights
    + verdict thresholds). Defaults to ..\config\triage-weights.json.

.PARAMETER DaysBackForAccounts
    How many days back to consider an account "recent" for the
    U-LocalAccounts flag. Default 7.

.PARAMETER StopAfterPhase
    Phase gate: stop cleanly (exit 0) after the named phase.
    Valid values: Preflight, Collection, Processing, Output, None.

.PARAMETER DryRun
    No file writes. All would-be writes are logged with a [DRY-RUN] prefix.

.PARAMETER DebugMode
    Promote DEBUG log entries to the console. DEBUG entries are always
    written to the log file regardless.

.EXAMPLE
    Invoke-BotnetTriage
    Runs full triage with default config, writes JSON to ..\output.

.EXAMPLE
    Invoke-BotnetTriage -IOCFile .\iocs\acme_2026-04.txt -DebugMode
    Runs with IOC correlation and verbose console output.

.EXAMPLE
    Invoke-BotnetTriage -StopAfterPhase Preflight
    Validates config and IOC file load, then exits 0.

.NOTES
    Author  : Ghost
    Created : 2026-04-09
    Version : 1.0.0

    Error codes:
      0  = Success (or clean phase-gate exit)
      10 = Input / config error (unreadable IOC file, output dir denied)
      11 = Malformed input (JSON weights/exclusions parse failure after
                           fallback rejection -- currently unreachable
                           because Resolve-Config always falls back)
      20 = Processing error (not used -- units fault-tolerate individually)
      40 = Output verification failed (JSON missing, empty, malformed)
      99 = Unhandled exception in the function body
#>


# ============================================================
# INLINE HELPER STUBS
# ------------------------------------------------------------
# These execute at dot-source / paste time. Each stub checks if
# the helper is already defined (meaning _Shared.ps1 was loaded
# first); if so, it does nothing. If not, it defines a minimal
# version of the helper so that the module can run standalone.
#
# This block MUST come before the function definition so that
# the function body can reference these helpers unambiguously.
# ============================================================

if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    function Write-Log {
        param(
            [Parameter(Mandatory)][string]$Message,
            [ValidateSet('DEBUG','INFO','WARN','ERROR','FATAL')][string]$Level = 'INFO'
        )
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $entry = "[$ts] [$Level] $Message"
        if ($script:LogFile) {
            try { Add-Content -Path $script:LogFile -Value $entry -ErrorAction Stop } catch { }
        }
        if ($Level -eq 'DEBUG' -and -not $DebugMode) { return }
        $color = switch ($Level) {
            'DEBUG' { 'Gray' }  'INFO'  { 'White' }
            'WARN'  { 'Yellow' } 'ERROR' { 'Red' }  'FATAL' { 'DarkRed' }
            default { 'White' }
        }
        Write-Host $entry -ForegroundColor $color
    }
}

if (-not (Get-Command Test-IsPrivateIP -ErrorAction SilentlyContinue)) {
    function Test-IsPrivateIP {
        param([Parameter(Mandatory)][string]$IPAddress)
        if ([string]::IsNullOrWhiteSpace($IPAddress)) { return $false }
        $ip = $null
        if (-not [System.Net.IPAddress]::TryParse($IPAddress, [ref]$ip)) { return $false }
        if ($ip.AddressFamily -eq 'InterNetworkV6') {
            if ($ip.IsIPv6LinkLocal -or $ip.IsIPv6SiteLocal) { return $true }
            if ([System.Net.IPAddress]::IsLoopback($ip)) { return $true }
            $fb = $ip.GetAddressBytes()[0]
            if (($fb -band 0xFE) -eq 0xFC) { return $true }
            return $false
        }
        $b = $ip.GetAddressBytes()
        if ($b[0] -eq 10)                                   { return $true }
        if ($b[0] -eq 127)                                  { return $true }
        if ($b[0] -eq 172 -and ($b[1] -ge 16 -and $b[1] -le 31)) { return $true }
        if ($b[0] -eq 192 -and $b[1] -eq 168)               { return $true }
        if ($b[0] -eq 169 -and $b[1] -eq 254)               { return $true }
        if ($b[0] -eq 0)                                    { return $true }
        if ($b[0] -ge 224)                                  { return $true }
        return $false
    }
}

if (-not (Get-Command Get-ProcessDetails -ErrorAction SilentlyContinue)) {
    function Get-ProcessDetails {
        param([Parameter(Mandatory)][int]$ProcessId)
        $r = [pscustomobject]@{
            ProcessId = $ProcessId; Name = $null; Path = $null
            CommandLine = $null; ParentPid = $null; User = $null
            SignerStatus = $null; SignerName = $null; Error = $null
        }
        try {
            $c = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop
            if ($c) {
                $r.Name = $c.Name; $r.Path = $c.ExecutablePath
                $r.CommandLine = $c.CommandLine; $r.ParentPid = $c.ParentProcessId
            }
        } catch { $r.Error = $_.Exception.Message }
        return $r
    }
}

if (-not (Get-Command Get-Secret -ErrorAction SilentlyContinue)) {
    function Get-Secret {
        param([Parameter(Mandatory)][string]$Name, [switch]$Required)
        $v = [Environment]::GetEnvironmentVariable($Name, 'Process')
        if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Name, 'User') }
        if ([string]::IsNullOrWhiteSpace($v)) {
            if ($Required) { throw "Required secret '$Name' not set" }
            return $null
        }
        return $v
    }
}

if (-not (Get-Command Resolve-Config -ErrorAction SilentlyContinue)) {
    function Resolve-Config {
        param(
            [Parameter(Mandatory)][string]$Path,
            [hashtable]$Fallback = @{},
            [string]$Label = (Split-Path $Path -Leaf)
        )
        if (-not (Test-Path $Path)) {
            Write-Log -Level WARN -Message "CONFIG_MISSING: $Label | Path: '$Path' | Using inline fallback"
            return $Fallback
        }
        try {
            return (Get-Content -Path $Path -Raw | ConvertFrom-Json -ErrorAction Stop)
        } catch {
            Write-Log -Level WARN -Message "CONFIG_MALFORMED: $Label | $($_.Exception.Message) | Using inline fallback"
            return $Fallback
        }
    }
}

if (-not (Get-Command Invoke-PhaseStart -ErrorAction SilentlyContinue)) {
    function Invoke-PhaseStart {
        param([Parameter(Mandatory)][string]$PhaseName)
        $script:PhaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Log -Level INFO -Message "PHASE_START: $PhaseName"
    }
}

if (-not (Get-Command Invoke-PhaseGate -ErrorAction SilentlyContinue)) {
    function Invoke-PhaseGate {
        param(
            [Parameter(Mandatory)][string]$PhaseName,
            [string]$Summary = ""
        )
        if ($script:PhaseTimer) { $script:PhaseTimer.Stop() }
        $phaseDuration = if ($script:PhaseTimer) { $script:PhaseTimer.Elapsed.TotalSeconds } else { 0 }
        if ($Summary) { Write-Log -Level INFO -Message "PHASE_SUMMARY: $PhaseName | $Summary" }
        Write-Log -Level INFO -Message "PHASE_END: $PhaseName | Phase Duration: ${phaseDuration}s"
        # Walk the call stack to find the caller's $StopAfterPhase param
        # (PowerShell dynamic scoping makes this implicit, but we use
        # Get-Variable defensively in case of edge cases under StrictMode).
        $sap = $null
        try { $sap = (Get-Variable -Name StopAfterPhase -Scope 1 -ErrorAction Stop).Value } catch { }
        if ($sap -eq $PhaseName) {
            if ($script:ScriptTimer) { $script:ScriptTimer.Stop() }
            $total = if ($script:ScriptTimer) { $script:ScriptTimer.Elapsed.TotalSeconds } else { 0 }
            Write-Log -Level INFO -Message "PHASE_GATE: Stopping cleanly after phase '$PhaseName' | Total Duration: ${total}s"
            $ex = [System.Management.Automation.RuntimeException]::new("PHASE_GATE_REACHED:$PhaseName")
            $er = [System.Management.Automation.ErrorRecord]::new($ex, 'PhaseGateReached', 'OperationStopped', $PhaseName)
            throw $er
        }
    }
}


# ============================================================
#                    Invoke-BotnetTriage
# ============================================================

function Invoke-BotnetTriage {
    [CmdletBinding()]
    param(
        [string]$OutputDir,

        [string]$IOCFile,

        [string]$ExclusionsFile,

        [string]$WeightsFile,

        [int]$DaysBackForAccounts = 7,

        [ValidateSet('Preflight','Collection','Processing','Output','None')]
        [string]$StopAfterPhase = 'None',

        [switch]$DryRun,

        [switch]$DebugMode
    )

    # Wrap the entire function body so a -StopAfterPhase gate
    # (which throws a tagged terminating error from
    # Invoke-PhaseGate) can be caught here and turned into a
    # clean function return, instead of bubbling out and killing
    # the caller's session via a script-level exit.
    try {

    # ----------------------------------------------------------
    # Inline helper: Test-IsUserWritablePath
    # ----------------------------------------------------------
    # Used by multiple units. Too small to warrant a separate file.
    function Test-IsUserWritablePath {
        param([string]$Path)
        if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
        $lc = $Path.ToLowerInvariant()
        $needles = @(
            $env:TEMP, $env:TMP, $env:APPDATA, $env:LOCALAPPDATA,
            'c:\programdata', 'c:\users\public',
            (Join-Path $env:USERPROFILE 'Downloads')
        ) | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() }
        foreach ($n in $needles) {
            if ($lc.StartsWith($n)) { return $true }
        }
        return $false
    }

    # ----------------------------------------------------------
    # Inline helper: Test-LOLBinPattern
    # ----------------------------------------------------------
    function Test-LOLBinPattern {
        param([string]$CommandLine)
        if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }
        $cl = $CommandLine.ToLowerInvariant()
        $patterns = @(
            'powershell.*-enc', 'powershell.*-e ', 'powershell.*encodedcommand',
            'rundll32.*\.dll,', 'regsvr32.*/s.*/u.*/i', 'regsvr32.*scrobj',
            'mshta.*http', 'mshta.*javascript:',
            'certutil.*-decode', 'certutil.*-urlcache',
            'bitsadmin.*transfer', 'wmic.*process.*call.*create'
        )
        foreach ($p in $patterns) {
            if ($cl -match $p) { return $true }
        }
        return $false
    }

    # ==========================================================
    # PRE-FLIGHT BOOTSTRAP
    # (happens before Phase A -- needed so Write-Log file target
    # and output dir exist before any unit runs)
    # ==========================================================

    $script:ScriptTimer = [System.Diagnostics.Stopwatch]::StartNew()

    # Resolve OutputDir default
    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        if ($PSScriptRoot) {
            $OutputDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
        } else {
            $OutputDir = Join-Path $env:TEMP 'BotnetTriage'
        }
    }

    try {
        if (-not (Test-Path $OutputDir)) {
            if ($DryRun) {
                Write-Host "[DRY-RUN] Would create output dir: $OutputDir"
            } else {
                New-Item -ItemType Directory -Path $OutputDir -Force -ErrorAction Stop | Out-Null
            }
        }
    } catch {
        Write-Host "[FATAL] Cannot create output dir '$OutputDir': $($_.Exception.Message)" -ForegroundColor Red
        exit 10
    }

    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $hostName = $env:COMPUTERNAME
    $script:LogFile = Join-Path $OutputDir "triage_${hostName}_${ts}.log"
    $jsonPath = Join-Path $OutputDir "BotnetTriage_${hostName}_${ts}.json"

    if (-not $DryRun) {
        try { New-Item -ItemType File -Path $script:LogFile -Force -ErrorAction Stop | Out-Null } catch { }
    }

    Write-Log -Level INFO -Message "SCRIPT_START: Invoke-BotnetTriage | Host: $hostName | User: $env:USERNAME"
    Write-Log -Level INFO -Message "ENV_SNAPSHOT: PSVersion=$($PSVersionTable.PSVersion) | OS=$([System.Environment]::OSVersion.VersionString) | OutputDir='$OutputDir'"
    Write-Log -Level INFO -Message "PARAMS: OutputDir='$OutputDir' | IOCFile='$IOCFile' | ExclusionsFile='$ExclusionsFile' | WeightsFile='$WeightsFile' | DaysBackForAccounts=$DaysBackForAccounts | StopAfterPhase=$StopAfterPhase | DryRun=$DryRun | DebugMode=$DebugMode"
    if ($DryRun)    { Write-Log -Level WARN -Message "DRY-RUN MODE ACTIVE -- no files will be written" }
    if ($DebugMode) { Write-Log -Level INFO -Message "DEBUG MODE ACTIVE -- DEBUG entries promoted to console" }

    # Function-local state containers
    $triageData = @{
        Connections    = @()
        ListeningPorts = @()
        ScheduledTasks = @()
        Services       = @()
        Autoruns       = @()
        DnsCache       = @()
        HostsFile      = @()
        LocalAccounts  = @()
    }
    $errors     = @()
    $configSource = 'file'  # flipped to 'inline-fallback' if Resolve-Config falls through

    # Inline unit lifecycle helper: wraps a unit body with start/end/failed
    # logging, updates $errors on failure, and NEVER rethrows -- per
    # PHASE1_PLAN: one unit failing does not abort the whole triage.
    function Invoke-TriageUnit {
        param(
            [Parameter(Mandatory)][string]$UnitName,
            [Parameter(Mandatory)][scriptblock]$Body
        )
        $t = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Log -Level INFO -Message "UNIT_START: $UnitName"
        try {
            & $Body
        } catch {
            $errMsg = $_.Exception.Message
            $line   = $_.InvocationInfo.ScriptLineNumber
            Write-Log -Level ERROR -Message "UNIT_FAILED: $UnitName | Error: $errMsg | Line: $line"
            Write-Log -Level DEBUG -Message "STACK_TRACE: $($_.ScriptStackTrace)"
            $errors += [pscustomobject]@{
                Unit      = $UnitName
                Error     = $errMsg
                Line      = $line
                Timestamp = (Get-Date -Format 'o')
            }
        } finally {
            $t.Stop()
            Write-Log -Level INFO -Message "UNIT_END: $UnitName | Duration: $($t.Elapsed.TotalSeconds)s"
        }
    }


    # ==========================================================
    # PHASE A -- PREFLIGHT
    # ==========================================================

    Invoke-PhaseStart -PhaseName 'Preflight'

    # ---- U-ParamValidate ----
    Invoke-TriageUnit -UnitName 'U-ParamValidate' -Body {
        if ($IOCFile -and -not (Test-Path $IOCFile)) {
            Write-Log -Level ERROR -Message "PARAM_ERROR: IOCFile not found: '$IOCFile'"
            throw "IOCFile '$IOCFile' does not exist"
        }

        # Elevation check -- warn only, don't fail. Lift to script scope so
        # U-WriteSummary can render a prominent banner and the JSON meta block
        # can record the elevation state for downstream tooling.
        $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $wp  = [System.Security.Principal.WindowsPrincipal]::new($wid)
        $isAdmin = $wp.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
        $script:Elevated = [bool]$isAdmin
        if (-not $isAdmin) {
            Write-Log -Level WARN -Message "NOT_ELEVATED: running as non-admin | Some data sources (CIM, accounts) may return partial results"
        } else {
            Write-Log -Level INFO -Message "ELEVATED: running with administrator privileges"
        }
    }

    # ---- U-LoadConfig ----
    Invoke-TriageUnit -UnitName 'U-LoadConfig' -Body {
        if ([string]::IsNullOrWhiteSpace($ExclusionsFile)) {
            if ($PSScriptRoot) {
                $ExclusionsFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'config\exclusions.json'
            }
        }
        if ([string]::IsNullOrWhiteSpace($WeightsFile)) {
            if ($PSScriptRoot) {
                $WeightsFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'config\triage-weights.json'
            }
        }

        $exclFallback = @{
            Processes      = @()
            Ports          = @()
            LocalOnlyPorts = @()
            PrivateSubnets = @('10.0.0.0/8','172.16.0.0/12','192.168.0.0/16')
            TrustedSigners = @('Microsoft Corporation','Microsoft Windows')
        }
        $weightsFallback = @{
            Connections    = @{ PrivateToPublicNonBrowser = 25; ProcessInTempOrAppData = 30; NonStandardPort = 20; SuspiciousParentProcess = 50; PathOutsideSystem32 = 40; EnrichmentIncomplete = 0; IOCMatchMultiplier = 2.0 }
            ListeningPorts = @{ HighPortAllInterfaces = 15; ListeningOnAllInterfaces = 10 }
            ScheduledTasks = @{ NonMicrosoftAuthor = 10; UserWritableActionPath = 25; LOLBinInArgs = 35 }
            Services       = @{ UserWritablePath = 30; Unsigned = 20; SuspiciousName = 15 }
            Autoruns       = @{ UserWritablePath = 25; LOLBinInCommand = 35 }
            DnsCache       = @{ RawIPEntry = 10; IOCMatchMultiplier = 2.0 }
            HostsFile      = @{ AnyNonDefaultEntry = 40 }
            LocalAccounts  = @{ RecentlyCreated = 30; RecentPasswordSet = 20; NewAdminGroupMember = 45 }
            Thresholds     = @{ High = 50; Medium = 25 }
        }

        $script:Exclusions    = Resolve-Config -Path $ExclusionsFile -Fallback $exclFallback -Label 'exclusions.json'
        $script:TriageWeights = Resolve-Config -Path $WeightsFile    -Fallback $weightsFallback -Label 'triage-weights.json'

        # Detect fallback usage -- if the returned object is a hashtable
        # (our $exclFallback) rather than a PSCustomObject (ConvertFrom-Json
        # output), Resolve-Config fell through.
        if ($script:Exclusions -is [hashtable] -or $script:TriageWeights -is [hashtable]) {
            $script:ConfigSource = 'inline-fallback'
        } else {
            $script:ConfigSource = 'file'
        }
        Write-Log -Level INFO -Message "CONFIG_RESOLVED: source=$($script:ConfigSource)"
    }

    # ---- U-LoadIOCs ----
    $script:IOCSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Invoke-TriageUnit -UnitName 'U-LoadIOCs' -Body {
        if (-not $IOCFile) {
            Write-Log -Level INFO -Message "IOC_FILE_ABSENT: no -IOCFile specified -- skipping IOC correlation"
            return
        }
        if (-not (Test-Path $IOCFile)) {
            Write-Log -Level WARN -Message "IOC_FILE_MISSING: '$IOCFile' -- continuing without IOCs"
            return
        }
        $lines = Get-Content -Path $IOCFile -ErrorAction Stop
        $added = 0
        foreach ($line in $lines) {
            $t = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($t)) { continue }
            if ($t.StartsWith('#')) { continue }
            [void]$script:IOCSet.Add($t)
            $added++
        }
        Write-Log -Level INFO -Message "IOC_FILE_LOADED: $added indicator(s) from '$IOCFile'"
    }

    Invoke-PhaseGate -PhaseName 'Preflight' -Summary "Config source: $($script:ConfigSource) | IOCs loaded: $($script:IOCSet.Count)"


    # ==========================================================
    # PHASE B -- COLLECTION
    # ==========================================================

    Invoke-PhaseStart -PhaseName 'Collection'

    # Build a process snapshot ONCE at the start of Collection so the
    # connection-snapshot and listening-port units can do dictionary
    # lookups instead of one Get-CimInstance Win32_Process call per
    # row. With ~100 connections and ~40 listeners, the per-row CIM
    # path takes ~90s on a typical laptop; the cache reduces the
    # whole pair of units to <2s.
    $procIndex = @{}
    try {
        $allProcs = Get-CimInstance -ClassName Win32_Process -ErrorAction Stop
        foreach ($p in $allProcs) {
            $procIndex[[int]$p.ProcessId] = [pscustomobject]@{
                ProcessId   = [int]$p.ProcessId
                Name        = $p.Name
                Path        = $p.ExecutablePath
                CommandLine = $p.CommandLine
                ParentPid   = $p.ParentProcessId
            }
        }
        Write-Log -Level DEBUG -Message "PROC_INDEX_BUILT: $($procIndex.Count) processes cached"
    } catch {
        Write-Log -Level WARN -Message "PROC_INDEX_FAILED: $($_.Exception.Message) -- units will fall back to slower per-row lookup"
    }

    # Build a parent-name index for quick lookup in U-ConnectionsSnapshot.
    # Maps ProcessId -> parent process Name. Used to detect SuspiciousParentProcess.
    $parentNameIndex = @{}
    foreach ($pid_ in $procIndex.Keys) {
        $ppid = $procIndex[$pid_].ParentPid
        if ($ppid -and $procIndex.ContainsKey([int]$ppid)) {
            $parentNameIndex[$pid_] = $procIndex[[int]$ppid].Name
        }
    }

    # ---- U-ConnectionsSnapshot ----
    Invoke-TriageUnit -UnitName 'U-ConnectionsSnapshot' -Body {
        $browserPattern = '^(chrome|firefox|msedge|iexplore|brave|opera|vivaldi|safari|edge)\.exe$'

        # Processes whose canonical System32 path and expected parent are known.
        # A connection from one of these with the wrong parent or wrong path is a
        # strong indicator of process injection / masquerading.
        $expectedParents = @{
            'svchost.exe'  = 'services.exe'
            'lsass.exe'    = 'wininit.exe'
            'csrss.exe'    = 'smss.exe'
        }
        $canonicalPaths = @{
            'svchost.exe'  = (Join-Path $env:SystemRoot 'System32\svchost.exe')
            'lsass.exe'    = (Join-Path $env:SystemRoot 'System32\lsass.exe')
            'csrss.exe'    = (Join-Path $env:SystemRoot 'System32\csrss.exe')
            'services.exe' = (Join-Path $env:SystemRoot 'System32\services.exe')
        }

        # Ports that are almost always legitimate on any Windows host.
        # A public connection to a port NOT in this list is additional signal.
        $commonPorts = @(80, 443, 8080, 8443, 53, 123, 25, 587, 465, 993, 995, 22, 3389, 5985, 5986, 21, 110, 143)

        # Per-run signer cache: path -> bool (signed by a trusted publisher).
        # Many legitimate apps install under %LOCALAPPDATA% by design (OneDrive,
        # Teams, VS Code, GitHub Desktop, Discord, Slack, Zoom). The path-based
        # ProcessInTempOrAppData detector must consult the TrustedSigners
        # allowlist before firing, or it produces a false High on every clean
        # Windows host that runs OneDrive. Authenticode lookups are ~50-200ms
        # so cache by path -- multiple connections from the same process must
        # not re-sign the binary.
        $signerCache = @{}
        $trustedSigners = @()
        if ($script:Exclusions -and $script:Exclusions.TrustedSigners) {
            $trustedSigners = @($script:Exclusions.TrustedSigners)
        }

        $conns = Get-NetTCPConnection -State Established -ErrorAction Stop
        $results = @()
        foreach ($c in $conns) {
            $remoteIsPrivate = Test-IsPrivateIP -IPAddress $c.RemoteAddress
            $localIsPrivate  = Test-IsPrivateIP -IPAddress $c.LocalAddress
            $pid_ = [int]$c.OwningProcess
            $pd = if ($procIndex.ContainsKey($pid_)) { $procIndex[$pid_] } else { Get-ProcessDetails -ProcessId $pid_ }
            $procNameLower = if ($pd.Name) { $pd.Name.ToLowerInvariant() } else { '' }

            $flags = @()

            # ---- PrivateToPublicNonBrowser ----
            if (-not $remoteIsPrivate -and $localIsPrivate) {
                if ($pd.Name -and $pd.Name -notmatch $browserPattern) {
                    $flags += 'PrivateToPublicNonBrowser'
                }
            }

            # ---- ProcessInTempOrAppData (signer-aware) ----
            # The path is suspicious only when the binary is NOT signed by a
            # trusted publisher. Microsoft OneDrive, Teams, VS Code, GitHub
            # Desktop, Discord, Slack, Zoom etc. all install under %LOCALAPPDATA%
            # legitimately and would otherwise produce a false High on every
            # clean Windows host. (Bug found: phase 1.2.1 hotfix 2026-04-09)
            if ($pd.Path -and (Test-IsUserWritablePath $pd.Path)) {
                $isTrustedSigner = $false
                if ($signerCache.ContainsKey($pd.Path)) {
                    $isTrustedSigner = $signerCache[$pd.Path]
                } else {
                    try {
                        $sig = Get-AuthenticodeSignature -FilePath $pd.Path -ErrorAction Stop
                        if ($sig.Status -eq 'Valid' -and $sig.SignerCertificate) {
                            $subject = $sig.SignerCertificate.Subject
                            foreach ($ts in $trustedSigners) {
                                if ($subject -like "*$ts*") { $isTrustedSigner = $true; break }
                            }
                        }
                    } catch {}
                    $signerCache[$pd.Path] = $isTrustedSigner
                }
                if (-not $isTrustedSigner) {
                    $flags += 'ProcessInTempOrAppData'
                }
            }

            # ---- PathOutsideSystem32 ----
            # Fires when a process that should only run from System32 is running
            # from somewhere else (masquerade / side-loading attack).
            if ($pd.Path -and $canonicalPaths.ContainsKey($procNameLower)) {
                $canonical = $canonicalPaths[$procNameLower]
                if ($pd.Path.ToLowerInvariant() -ne $canonical.ToLowerInvariant()) {
                    $flags += 'PathOutsideSystem32'
                }
            }

            # ---- SuspiciousParentProcess ----
            # Fires when a well-known system process has an unexpected parent --
            # the primary indicator of process hollowing / injection.
            $expectedParent = $expectedParents[$procNameLower]
            if ($expectedParent) {
                $actualParent = $parentNameIndex[$pid_]
                if ($actualParent -and $actualParent.ToLowerInvariant() -ne $expectedParent) {
                    $flags += 'SuspiciousParentProcess'
                }
            }

            # ---- NonStandardPort ----
            # Fires on any public connection to a port outside the common legitimate
            # set. Adds a second scoring axis independent of process identity.
            if (-not $remoteIsPrivate -and $c.RemotePort -notin $commonPorts) {
                $flags += 'NonStandardPort'
            }

            # IOC pre-retain: an IOC match alone is enough to keep this
            # row even if no heuristic flagged it. Score multiplier is
            # applied later by U-CorrelateIOCs.
            $iocHit = ($script:IOCSet.Count -gt 0 -and $c.RemoteAddress -and $script:IOCSet.Contains([string]$c.RemoteAddress))
            if ($flags.Count -gt 0 -or $iocHit) {
                # ---- EnrichmentIncomplete (diagnostic-only, weight 0) ----
                # Annotate retained rows where the proc cache could not return
                # full context (typically because we are non-elevated and the
                # process is owned by SYSTEM or another user). Tells the
                # operator their vetting context is missing for this specific
                # row, complementing the global NOT_ELEVATED banner.
                if ($pd -and (-not $pd.Path -or -not $pd.CommandLine)) {
                    $flags += 'EnrichmentIncomplete'
                }
                $results += [pscustomobject]@{
                    LocalAddress      = $c.LocalAddress
                    LocalPort         = $c.LocalPort
                    RemoteAddress     = $c.RemoteAddress
                    RemotePort        = $c.RemotePort
                    ProcessId         = $c.OwningProcess
                    ProcessName       = $pd.Name
                    ProcessPath       = $pd.Path
                    CommandLine       = $pd.CommandLine
                    ParentProcessName = $parentNameIndex[$pid_]
                    Flags             = $flags
                    Score             = 0
                    IOCMatch          = $false
                    Risk              = 'Low'
                }
            }
        }
        $triageData.Connections = $results
        Write-Log -Level INFO -Message "CONNECTIONS: $($results.Count) flagged of $($conns.Count) total established"
    }

    # ---- U-ListeningPorts ----
    Invoke-TriageUnit -UnitName 'U-ListeningPorts' -Body {
        $listens = Get-NetTCPConnection -State Listen -ErrorAction Stop
        $wellKnownServers = @(80, 443, 22, 445, 135, 139, 3389, 5985, 5986, 53, 88)
        # System processes that are expected to bind listeners.
        $sysListeners = '^(svchost|lsass|services|system|wininit|spoolsv|csrss|smss|audiodg|WUDFHost)\.exe$'
        $results = @()
        foreach ($l in $listens) {
            $pid_ = [int]$l.OwningProcess
            $pd = if ($procIndex.ContainsKey($pid_)) { $procIndex[$pid_] } else { Get-ProcessDetails -ProcessId $pid_ }
            $isSys = $pd.Name -and $pd.Name -match $sysListeners
            $flags = @()
            # HighPortAllInterfaces: high ephemeral port (>49152) AND accessible
            # externally (0.0.0.0 or ::). Purely local high-port listeners are
            # normal RPC/IPC channels and are NOT flagged.
            if ($l.LocalPort -gt 49152 -and -not $isSys) {
                if ($l.LocalAddress -eq '0.0.0.0' -or $l.LocalAddress -eq '::') {
                    $flags += 'HighPortAllInterfaces'
                }
            }
            if ($l.LocalAddress -eq '0.0.0.0' -and $l.LocalPort -notin $wellKnownServers) {
                if (-not $isSys) {
                    $flags += 'ListeningOnAllInterfaces'
                }
            }
            if ($flags.Count -gt 0) {
                $results += [pscustomobject]@{
                    LocalAddress = $l.LocalAddress
                    LocalPort    = $l.LocalPort
                    ProcessId    = $l.OwningProcess
                    ProcessName  = $pd.Name
                    ProcessPath  = $pd.Path
                    Flags        = $flags
                    Score        = 0
                    IOCMatch     = $false
                    Risk         = 'Low'
                }
            }
        }
        $triageData.ListeningPorts = $results
        Write-Log -Level INFO -Message "LISTENING_PORTS: $($results.Count) flagged of $($listens.Count) total listening"
    }

    # ---- U-ScheduledTasks ----
    Invoke-TriageUnit -UnitName 'U-ScheduledTasks' -Body {
        $tasks = Get-ScheduledTask -ErrorAction Stop
        $results = @()
        foreach ($t in $tasks) {
            $flags = @()
            $author = $t.Author
            if ($author -and $author -notmatch '^(Microsoft|SYSTEM|\$\(@%)') {
                $flags += 'NonMicrosoftAuthor'
            }
            # Scheduled task actions are polymorphic CIM instances:
            # MSFT_TaskExecAction has Execute/Arguments, but
            # MSFT_TaskComHandlerAction (and others) do NOT -- under
            # Set-StrictMode -Version Latest, accessing $a.Execute on a
            # COM-handler action throws. Probe via PSObject.Properties.
            $actionStrings = @()
            foreach ($a in $t.Actions) {
                $exec = if ($a.PSObject.Properties.Name -contains 'Execute')   { $a.Execute }   else { $null }
                $argv = if ($a.PSObject.Properties.Name -contains 'Arguments') { $a.Arguments } else { $null }
                if ($exec -and (Test-IsUserWritablePath $exec)) {
                    $flags += 'UserWritableActionPath'
                }
                $full = "$exec $argv".Trim()
                if ($full) { $actionStrings += $full }
                if (Test-LOLBinPattern -CommandLine $full) {
                    $flags += 'LOLBinInArgs'
                }
            }
            $actionsJoined = $actionStrings -join ' ; '
            $iocHit = $false
            if ($script:IOCSet.Count -gt 0 -and $actionsJoined) {
                foreach ($ioc in $script:IOCSet) {
                    if ($actionsJoined -match [regex]::Escape($ioc)) { $iocHit = $true; break }
                }
            }
            if ($flags.Count -gt 0 -or $iocHit) {
                $results += [pscustomobject]@{
                    TaskName = $t.TaskName
                    TaskPath = $t.TaskPath
                    Author   = $author
                    State    = [string]$t.State
                    Actions  = $actionsJoined
                    Flags    = ($flags | Select-Object -Unique)
                    Score    = 0
                    IOCMatch = $false
                    Risk     = 'Low'
                }
            }
        }
        $triageData.ScheduledTasks = $results
        Write-Log -Level INFO -Message "SCHEDULED_TASKS: $($results.Count) flagged of $($tasks.Count) total"
    }

    # ---- U-Services ----
    Invoke-TriageUnit -UnitName 'U-Services' -Body {
        $svcs = Get-CimInstance -ClassName Win32_Service -ErrorAction Stop
        $results = @()
        foreach ($s in $svcs) {
            $flags = @()
            $path = if ($s.PathName) { ($s.PathName -replace '^"([^"]+)".*', '$1') } else { $null }
            if ($path -and (Test-IsUserWritablePath $path)) {
                $flags += 'UserWritablePath'
            }
            # Authenticode check: ONLY flag truly unsigned. The
            # "untrusted signer" check is intentionally dropped -- it
            # produces a flood of false positives against any legitimate
            # third-party signed software (anti-virus other than the one
            # in our exclusion list, browsers, productivity apps, etc).
            # The triage-weights.json doesn't even score it. A real
            # signer-trust check needs a comprehensive trust list and
            # belongs in Phase 2 where IOC enrichment lives.
            if ($path -and (Test-Path $path -ErrorAction SilentlyContinue)) {
                try {
                    $sig = Get-AuthenticodeSignature -FilePath $path -ErrorAction Stop
                    if ($sig.Status -ne 'Valid' -and $sig.Status -ne 'UnknownError') {
                        $flags += 'Unsigned'
                    }
                } catch { }
            }
            # Service-name heuristic intentionally omitted in Phase 1.
            # The original `^[a-z]{8,}$` matched `wuauserv`,
            # `lanmanworkstation`, etc -- almost every legit Windows
            # service. A real entropy/randomness check belongs in
            # Phase 2 alongside the IOC correlator.
            $iocHit = $false
            if ($script:IOCSet.Count -gt 0 -and $s.PathName) {
                foreach ($ioc in $script:IOCSet) {
                    if ($s.PathName -match [regex]::Escape($ioc)) { $iocHit = $true; break }
                }
            }
            if ($flags.Count -gt 0 -or $iocHit) {
                $results += [pscustomobject]@{
                    Name        = $s.Name
                    DisplayName = $s.DisplayName
                    PathName    = $s.PathName
                    StartMode   = $s.StartMode
                    State       = $s.State
                    Flags       = ($flags | Select-Object -Unique)
                    Score       = 0
                    IOCMatch    = $false
                    Risk        = 'Low'
                }
            }
        }
        $triageData.Services = $results
        Write-Log -Level INFO -Message "SERVICES: $($results.Count) flagged of $($svcs.Count) total"
    }

    # ---- U-Autoruns ----
    Invoke-TriageUnit -UnitName 'U-Autoruns' -Body {
        $runKeys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
        )
        $results = @()
        foreach ($k in $runKeys) {
            if (-not (Test-Path $k)) { continue }
            try {
                $props = Get-ItemProperty -Path $k -ErrorAction Stop
                $names = $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }
                foreach ($n in $names) {
                    $cmd = [string]$n.Value
                    if ([string]::IsNullOrWhiteSpace($cmd)) { continue }
                    $flags = @()
                    # Extract the exe portion for path check
                    $exe = $cmd -replace '^"([^"]+)".*', '$1'
                    if ($exe -eq $cmd) { $exe = ($cmd -split ' ')[0] }
                    if (Test-IsUserWritablePath $exe) {
                        $flags += 'UserWritablePath'
                    }
                    if (Test-LOLBinPattern -CommandLine $cmd) {
                        $flags += 'LOLBinInCommand'
                    }
                    $iocHit = $false
                    if ($script:IOCSet.Count -gt 0) {
                        foreach ($ioc in $script:IOCSet) {
                            if ($cmd -match [regex]::Escape($ioc)) { $iocHit = $true; break }
                        }
                    }
                    if ($flags.Count -gt 0 -or $iocHit) {
                        $results += [pscustomobject]@{
                            Location    = $k
                            EntryName   = $n.Name
                            CommandLine = $cmd
                            Flags       = $flags
                            Score       = 0
                            IOCMatch    = $false
                            Risk        = 'Low'
                        }
                    }
                }
            } catch { }
        }
        $triageData.Autoruns = $results
        Write-Log -Level INFO -Message "AUTORUNS: $($results.Count) flagged entries across Run/RunOnce keys"
    }

    # ---- U-DnsCache ----
    Invoke-TriageUnit -UnitName 'U-DnsCache' -Body {
        $cache = @()
        try { $cache = Get-DnsClientCache -ErrorAction Stop } catch { }
        $results = @()
        foreach ($e in $cache) {
            $flags = @()
            $name = $e.Entry
            $data = $e.Data
            # Raw IP entry (A or AAAA record being cached as an IP-named entry)
            if ($name -match '^\d{1,3}(\.\d{1,3}){3}$') {
                $flags += 'RawIPEntry'
            }
            $iocHit = $false
            if ($script:IOCSet.Count -gt 0) {
                if (($name -and $script:IOCSet.Contains([string]$name)) -or
                    ($data -and $script:IOCSet.Contains([string]$data))) {
                    $iocHit = $true
                }
            }
            if ($flags.Count -gt 0 -or $iocHit) {
                $results += [pscustomobject]@{
                    Entry    = $name
                    Data     = $data
                    Type     = [string]$e.Type
                    Flags    = $flags
                    Score    = 0
                    IOCMatch = $false
                    Risk     = 'Low'
                }
            }
        }
        $triageData.DnsCache = $results
        Write-Log -Level INFO -Message "DNS_CACHE: $($results.Count) flagged of $($cache.Count) cached entries"
    }

    # ---- U-HostsFile ----
    Invoke-TriageUnit -UnitName 'U-HostsFile' -Body {
        $hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
        if (-not (Test-Path $hostsPath)) {
            Write-Log -Level WARN -Message "HOSTS_FILE_MISSING: '$hostsPath'"
            return
        }
        $lines = Get-Content -Path $hostsPath -ErrorAction Stop
        $results = @()
        foreach ($line in $lines) {
            $t = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($t)) { continue }
            if ($t.StartsWith('#')) { continue }
            $results += [pscustomobject]@{
                Line     = $t
                Flags    = @('AnyNonDefaultEntry')
                Score    = 0
                IOCMatch = $false
                Risk     = 'Low'
            }
        }
        $triageData.HostsFile = $results
        Write-Log -Level INFO -Message "HOSTS_FILE: $($results.Count) non-default entries"
    }

    # ---- U-LocalAccounts ----
    Invoke-TriageUnit -UnitName 'U-LocalAccounts' -Body {
        $cutoff = (Get-Date).AddDays(-$DaysBackForAccounts)
        $results = @()
        try {
            $users = Get-LocalUser -ErrorAction Stop
        } catch {
            Write-Log -Level WARN -Message "LOCAL_USERS_UNAVAILABLE: $($_.Exception.Message)"
            $users = @()
        }
        foreach ($u in $users) {
            $flags = @()
            # Get-LocalUser doesn't expose Created directly on all versions; PasswordLastSet is reliable.
            if ($u.PasswordLastSet -and $u.PasswordLastSet -gt $cutoff) {
                $flags += 'RecentPasswordSet'
            }
            # Heuristic "recently created": if SID was issued recently -- not directly available.
            # Fall back to PasswordLastSet as a proxy for user activity.
            if ($flags.Count -gt 0) {
                $results += [pscustomobject]@{
                    Name            = $u.Name
                    Enabled         = $u.Enabled
                    LastLogon       = [string]$u.LastLogon
                    PasswordLastSet = [string]$u.PasswordLastSet
                    Flags           = $flags
                    Score           = 0
                    IOCMatch        = $false
                    Risk            = 'Low'
                }
            }
        }
        # Administrators group members
        try {
            $admins = Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop
            foreach ($m in $admins) {
                # Match against the name-only portion (MACHINE\User -> User)
                $nameOnly = ($m.Name -split '\\')[-1]
                $existing = $results | Where-Object { $_.Name -eq $nameOnly }
                if ($existing) {
                    $existing.Flags += 'NewAdminGroupMember'
                } else {
                    # Only flag if this account is also flagged as recently changed;
                    # otherwise an admin is just a normal admin.
                    # Actually the plan says "new Administrators group member" -- we
                    # flag all admins for visibility and let the scorer decide.
                    $results += [pscustomobject]@{
                        Name            = $nameOnly
                        Enabled         = $null
                        LastLogon       = $null
                        PasswordLastSet = $null
                        Flags           = @('AdminGroupMember')
                        Score           = 0
                        IOCMatch        = $false
                        Risk            = 'Low'
                    }
                }
            }
        } catch {
            Write-Log -Level WARN -Message "LOCAL_GROUP_ADMINS_UNAVAILABLE: $($_.Exception.Message)"
        }
        $triageData.LocalAccounts = $results
        Write-Log -Level INFO -Message "LOCAL_ACCOUNTS: $($results.Count) flagged account(s)"
    }

    Invoke-PhaseGate -PhaseName 'Collection' -Summary "Collected findings across 8 data sources"


    # ==========================================================
    # PHASE C -- PROCESSING
    # ==========================================================

    Invoke-PhaseStart -PhaseName 'Processing'

    # ---- U-ApplyExclusions ----
    Invoke-TriageUnit -UnitName 'U-ApplyExclusions' -Body {
        $excludedProcs  = @()
        $excludedPorts  = @()
        $localOnlyPorts = @()
        $beaconWL       = @()
        if ($script:Exclusions.Processes)      { $excludedProcs  = @($script:Exclusions.Processes) }
        if ($script:Exclusions.Ports)          { $excludedPorts  = @($script:Exclusions.Ports) }
        if ($script:Exclusions.LocalOnlyPorts) { $localOnlyPorts = @($script:Exclusions.LocalOnlyPorts) }
        if ($script:Exclusions.BeaconWhitelist){ $beaconWL       = @($script:Exclusions.BeaconWhitelist) }

        $beforeConn = $triageData.Connections.Count
        $triageData.Connections = @($triageData.Connections | Where-Object {
            $pn = if ($_.ProcessName) { [System.IO.Path]::GetFileNameWithoutExtension($_.ProcessName) } else { '' }
            $keep = $true
            foreach ($ep in $excludedProcs) {
                if ($pn -eq $ep -or $pn -eq "$ep.exe") { $keep = $false; break }
            }
            $keep
        })

        # BeaconWhitelist: operator-confirmed benign process+port tuples.
        # Ships empty -- populated per-engagement after the operator has
        # verified a connection is benign (e.g. via packet capture).
        if ($beaconWL.Count -gt 0) {
            $beforeBW = $triageData.Connections.Count
            $triageData.Connections = @($triageData.Connections | Where-Object {
                $pn = if ($_.ProcessName) { [System.IO.Path]::GetFileNameWithoutExtension($_.ProcessName) } else { '' }
                $rp = [int]$_.RemotePort
                $suppress = $false
                foreach ($bw in $beaconWL) {
                    $bwProc = [System.IO.Path]::GetFileNameWithoutExtension([string]$bw.Process)
                    if ($pn -eq $bwProc -and $rp -eq [int]$bw.RemotePort) { $suppress = $true; break }
                }
                -not $suppress
            })
            Write-Log -Level INFO -Message "BEACON_WHITELIST_APPLIED: connections $beforeBW->$($triageData.Connections.Count)"
        }

        $beforeList = $triageData.ListeningPorts.Count
        $triageData.ListeningPorts = @($triageData.ListeningPorts | Where-Object {
            $keep = $true
            if ($_.LocalPort -in $excludedPorts) { $keep = $false }
            # LocalOnlyPorts: ports expected only on loopback (RPC, SMB helper ports, etc.)
            # Suppress them when the listener is actually loopback-only.
            if ($keep -and $localOnlyPorts.Count -gt 0) {
                if ($_.LocalAddress -in @('127.0.0.1','::1','0:0:0:0:0:0:0:1') -and $_.LocalPort -in $localOnlyPorts) {
                    $keep = $false
                }
            }
            if ($keep) {
                $pn = if ($_.ProcessName) { [System.IO.Path]::GetFileNameWithoutExtension($_.ProcessName) } else { '' }
                foreach ($ep in $excludedProcs) {
                    if ($pn -eq $ep -or $pn -eq "$ep.exe") { $keep = $false; break }
                }
            }
            $keep
        })

        $beforeSvc = $triageData.Services.Count
        $triageData.Services = @($triageData.Services | Where-Object {
            $keep = $true
            foreach ($ep in $excludedProcs) {
                if ($_.Name -eq $ep) { $keep = $false; break }
            }
            $keep
        })

        Write-Log -Level INFO -Message "EXCLUSIONS_APPLIED: connections $beforeConn->$($triageData.Connections.Count), listens $beforeList->$($triageData.ListeningPorts.Count), services $beforeSvc->$($triageData.Services.Count)"
    }

    # ---- U-ScoreFindings ----
    Invoke-TriageUnit -UnitName 'U-ScoreFindings' -Body {
        $w = $script:TriageWeights

        function Get-FlagWeight {
            param($Category, $Flag)
            $cat = $w.$Category
            if ($cat -and ($cat.PSObject.Properties.Name -contains $Flag)) {
                return [double]$cat.$Flag
            }
            if ($cat -is [hashtable] -and $cat.ContainsKey($Flag)) {
                return [double]$cat[$Flag]
            }
            return 0
        }

        foreach ($item in $triageData.Connections) {
            $s = 0; foreach ($f in $item.Flags) { $s += (Get-FlagWeight 'Connections' $f) }
            $item.Score = $s
        }
        foreach ($item in $triageData.ListeningPorts) {
            $s = 0; foreach ($f in $item.Flags) { $s += (Get-FlagWeight 'ListeningPorts' $f) }
            $item.Score = $s
        }
        foreach ($item in $triageData.ScheduledTasks) {
            $s = 0; foreach ($f in $item.Flags) { $s += (Get-FlagWeight 'ScheduledTasks' $f) }
            $item.Score = $s
        }
        foreach ($item in $triageData.Services) {
            $s = 0; foreach ($f in $item.Flags) { $s += (Get-FlagWeight 'Services' $f) }
            $item.Score = $s
        }
        foreach ($item in $triageData.Autoruns) {
            $s = 0; foreach ($f in $item.Flags) { $s += (Get-FlagWeight 'Autoruns' $f) }
            $item.Score = $s
        }
        foreach ($item in $triageData.DnsCache) {
            $s = 0; foreach ($f in $item.Flags) { $s += (Get-FlagWeight 'DnsCache' $f) }
            $item.Score = $s
        }
        foreach ($item in $triageData.HostsFile) {
            $s = 0; foreach ($f in $item.Flags) { $s += (Get-FlagWeight 'HostsFile' $f) }
            $item.Score = $s
        }
        foreach ($item in $triageData.LocalAccounts) {
            $s = 0; foreach ($f in $item.Flags) { $s += (Get-FlagWeight 'LocalAccounts' $f) }
            $item.Score = $s
        }

        $total = 0
        foreach ($k in $triageData.Keys) { $total += $triageData[$k].Count }
        Write-Log -Level INFO -Message "SCORED: $total total finding(s)"
    }

    # ---- U-CorrelateIOCs ----
    Invoke-TriageUnit -UnitName 'U-CorrelateIOCs' -Body {
        if ($script:IOCSet.Count -eq 0) {
            Write-Log -Level DEBUG -Message "IOC_CORRELATE_SKIPPED: no IOCs loaded"
            return
        }
        $multConn = 2.0
        if ($script:TriageWeights.Connections -and $script:TriageWeights.Connections.IOCMatchMultiplier) {
            $multConn = [double]$script:TriageWeights.Connections.IOCMatchMultiplier
        }
        $multDns = 2.0
        if ($script:TriageWeights.DnsCache -and $script:TriageWeights.DnsCache.IOCMatchMultiplier) {
            $multDns = [double]$script:TriageWeights.DnsCache.IOCMatchMultiplier
        }

        $hits = 0
        foreach ($c in $triageData.Connections) {
            if ($script:IOCSet.Contains($c.RemoteAddress)) {
                $c.IOCMatch = $true
                $c.Score = [double]$c.Score * $multConn
                if ($c.Score -eq 0) { $c.Score = 10 * $multConn }  # baseline for pure-IOC hit
                $hits++
            }
        }
        foreach ($d in $triageData.DnsCache) {
            if ($script:IOCSet.Contains($d.Entry) -or ($d.Data -and $script:IOCSet.Contains($d.Data))) {
                $d.IOCMatch = $true
                $d.Score = [double]$d.Score * $multDns
                if ($d.Score -eq 0) { $d.Score = 10 * $multDns }
                $hits++
            }
        }
        foreach ($h in $triageData.HostsFile) {
            foreach ($ioc in $script:IOCSet) {
                if ($h.Line -match [regex]::Escape($ioc)) {
                    $h.IOCMatch = $true
                    $h.Score = [double]$h.Score * 2.0
                    $hits++; break
                }
            }
        }
        # Tasks / services: match IOCs inside command lines / paths
        foreach ($t in $triageData.ScheduledTasks) {
            foreach ($ioc in $script:IOCSet) {
                if ($t.Actions -and $t.Actions -match [regex]::Escape($ioc)) {
                    $t.IOCMatch = $true
                    $t.Score = [double]$t.Score * 2.0
                    $hits++; break
                }
            }
        }
        foreach ($s in $triageData.Services) {
            foreach ($ioc in $script:IOCSet) {
                if ($s.PathName -and $s.PathName -match [regex]::Escape($ioc)) {
                    $s.IOCMatch = $true
                    $s.Score = [double]$s.Score * 2.0
                    $hits++; break
                }
            }
        }
        foreach ($a in $triageData.Autoruns) {
            foreach ($ioc in $script:IOCSet) {
                if ($a.CommandLine -and $a.CommandLine -match [regex]::Escape($ioc)) {
                    $a.IOCMatch = $true
                    $a.Score = [double]$a.Score * 2.0
                    if ($a.Score -eq 0) { $a.Score = 10 * 2.0 }
                    $hits++; break
                }
            }
        }
        Write-Log -Level INFO -Message "IOC_CORRELATED: $hits finding(s) matched an IOC"
    }

    # ---- U-ClassifyRisk ----
    Invoke-TriageUnit -UnitName 'U-ClassifyRisk' -Body {
        $th = $script:TriageWeights.Thresholds
        $high = if ($th) { [double]$th.High } else { 50 }
        $med  = if ($th) { [double]$th.Medium } else { 25 }

        $counts = @{ High = 0; Medium = 0; Low = 0 }
        foreach ($key in @('Connections','ListeningPorts','ScheduledTasks','Services','Autoruns','DnsCache','HostsFile','LocalAccounts')) {
            foreach ($item in $triageData[$key]) {
                $score = [double]$item.Score
                if ($score -ge $high) {
                    $item.Risk = 'High'; $counts.High++
                } elseif ($score -ge $med) {
                    $item.Risk = 'Medium'; $counts.Medium++
                } else {
                    $item.Risk = 'Low'; $counts.Low++
                }
            }
        }
        $script:Verdict = $counts
        Write-Log -Level INFO -Message "VERDICT: High=$($counts.High) Medium=$($counts.Medium) Low=$($counts.Low)"
    }

    Invoke-PhaseGate -PhaseName 'Processing' -Summary "Verdict: High=$($script:Verdict.High) Medium=$($script:Verdict.Medium) Low=$($script:Verdict.Low)"


    # ==========================================================
    # PHASE D -- OUTPUT
    # ==========================================================

    Invoke-PhaseStart -PhaseName 'Output'

    $script:ScriptTimer.Stop()
    $duration = [math]::Round($script:ScriptTimer.Elapsed.TotalSeconds, 2)
    $script:ScriptTimer.Start()  # keep running for later gate

    # Build the finalized JSON object (used by both U-WriteJson and U-WriteSummary)
    $topFindings = @()
    foreach ($key in $triageData.Keys) {
        foreach ($item in $triageData[$key]) {
            $topFindings += [pscustomobject]@{
                Category = $key
                Score    = $item.Score
                Risk     = $item.Risk
                Summary  = (($item | Select-Object -Property * -ExcludeProperty Score, Flags, Risk, IOCMatch | ConvertTo-Json -Compress -Depth 2))
                Flags    = $item.Flags
                IOCMatch = $item.IOCMatch
            }
        }
    }
    $topFindings = $topFindings | Sort-Object -Property Score -Descending | Select-Object -First 5

    $findingsBlock = [ordered]@{}
    foreach ($key in @('Connections','ListeningPorts','ScheduledTasks','Services','Autoruns','DnsCache','HostsFile','LocalAccounts')) {
        $camelKey = $key.Substring(0,1).ToLowerInvariant() + $key.Substring(1)
        $findingsBlock[$camelKey] = [ordered]@{
            count = $triageData[$key].Count
            items = $triageData[$key]
        }
    }

    $finalOutput = [ordered]@{
        meta = [ordered]@{
            module           = 'Invoke-BotnetTriage'
            version          = '1.0.0'
            hostname         = $hostName
            timestamp        = (Get-Date -Format 'o')
            durationSeconds  = $duration
            elevated         = [bool]$script:Elevated
            exclusionsLoaded = ($null -ne $script:Exclusions)
            iocsLoaded       = ($script:IOCSet.Count -gt 0)
            configSource     = $script:ConfigSource
        }
        verdict = [ordered]@{
            high         = $script:Verdict.High
            medium       = $script:Verdict.Medium
            low          = $script:Verdict.Low
            topFindings  = $topFindings
        }
        findings = $findingsBlock
        errors   = $errors
    }

    # ---- U-WriteJson ----
    Invoke-TriageUnit -UnitName 'U-WriteJson' -Body {
        if ($DryRun) {
            Write-Log -Level INFO -Message "[DRY-RUN] Would write JSON to '$jsonPath'"
            return
        }
        $finalOutput | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8 -ErrorAction Stop
        Write-Log -Level INFO -Message "JSON_WRITTEN: '$jsonPath'"
    }

    # ---- U-WriteSummary ----
    Invoke-TriageUnit -UnitName 'U-WriteSummary' -Body {
        $v = $script:Verdict
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host "  BOTNET TRIAGE VERDICT: $hostName" -ForegroundColor Cyan
        # Non-elevated callout: the warning at U-ParamValidate is a single log
        # line buried mid-output; an operator skimming the verdict needs a
        # prominent banner saying the data is partial. Only fires when we
        # KNOW non-elevated -- $script:Elevated -eq $null means unknown,
        # which we render as nothing rather than misleading the operator.
        if ($script:Elevated -eq $false) {
            Write-Host "  ** NOT ELEVATED -- VISIBILITY LIMITED **" -ForegroundColor Yellow
            Write-Host "     Connection enumeration may be incomplete." -ForegroundColor Yellow
            Write-Host "     Process paths/cmdlines may be null for non-owned processes." -ForegroundColor Yellow
            Write-Host "     Re-run as Administrator for full coverage." -ForegroundColor Yellow
        }
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host ("  HIGH:   {0,3}" -f $v.High)   -ForegroundColor Red
        Write-Host ("  MEDIUM: {0,3}" -f $v.Medium) -ForegroundColor Yellow
        Write-Host ("  LOW:    {0,3}" -f $v.Low)    -ForegroundColor Gray
        Write-Host "----------------------------------------------------------------" -ForegroundColor Cyan
        if ($topFindings.Count -eq 0) {
            Write-Host "  No findings flagged." -ForegroundColor Green
        } else {
            Write-Host "  TOP $($topFindings.Count) FINDINGS (by score):" -ForegroundColor Cyan
            $i = 1
            foreach ($f in $topFindings) {
                $riskColor = switch ($f.Risk) {
                    'High'   { 'Red' }
                    'Medium' { 'Yellow' }
                    default  { 'Gray' }
                }
                $flagStr = ($f.Flags -join ',')
                $iocTag  = if ($f.IOCMatch) { ' [IOC]' } else { '' }
                Write-Host ("  {0}. [{1,-6}] score={2,-6} {3} -- {4}{5}" -f $i, $f.Risk, $f.Score, $f.Category, $flagStr, $iocTag) -ForegroundColor $riskColor
                $i++
            }
        }
        Write-Host "================================================================" -ForegroundColor Cyan
        if ($DryRun) {
            Write-Host "  [DRY-RUN] JSON artifact NOT written." -ForegroundColor Yellow
        } else {
            Write-Host "  JSON artifact: $jsonPath" -ForegroundColor White
        }
        Write-Host ""
    }

    # ---- U-VerifyArtifacts ----
    Invoke-TriageUnit -UnitName 'U-VerifyArtifacts' -Body {
        if ($DryRun) {
            Write-Log -Level INFO -Message "[DRY-RUN] Skipping artifact verification"
            return
        }
        if (Get-Command Verify-JsonOutput -ErrorAction SilentlyContinue) {
            Verify-JsonOutput -Path $jsonPath -RequiredKeys @('meta','verdict','findings','errors')
        } else {
            # Inline fallback
            if (-not (Test-Path $jsonPath)) {
                Write-Log -Level ERROR -Message "VERIFY_FAILED: JSON not found at '$jsonPath'"
                exit 40
            }
            $size = (Get-Item $jsonPath).Length
            if ($size -lt 1) {
                Write-Log -Level ERROR -Message "VERIFY_FAILED: JSON empty at '$jsonPath'"
                exit 40
            }
            try {
                $parsed = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json -ErrorAction Stop
                foreach ($k in @('meta','verdict','findings','errors')) {
                    if (-not ($parsed.PSObject.Properties.Name -contains $k)) {
                        Write-Log -Level ERROR -Message "VERIFY_FAILED: JSON missing key '$k'"
                        exit 40
                    }
                }
                Write-Log -Level INFO -Message "VERIFY_OK: JSON '$jsonPath' | Size: ${size}B"
            } catch {
                Write-Log -Level ERROR -Message "VERIFY_FAILED: JSON parse error | $($_.Exception.Message)"
                exit 40
            }
        }
    }

    Invoke-PhaseGate -PhaseName 'Output' -Summary "Artifact: $jsonPath"

    $script:ScriptTimer.Stop()
    $finalDuration = [math]::Round($script:ScriptTimer.Elapsed.TotalSeconds, 2)
    Write-Log -Level INFO -Message "SCRIPT_COMPLETE: Invoke-BotnetTriage | Total Duration: ${finalDuration}s | Errors: $($errors.Count)"
    return 0

    } catch {
        if ($_.FullyQualifiedErrorId -eq 'PhaseGateReached') {
            # Clean phase-gate exit signaled by Invoke-PhaseGate.
            return 0
        }
        # Anything else is an unhandled error inside the function body.
        try {
            Write-Log -Level ERROR -Message "UNHANDLED: $($_.Exception.Message) | At: $($_.InvocationInfo.PositionMessage)"
        } catch {
            Write-Host "[FATAL] Unhandled error: $($_.Exception.Message)" -ForegroundColor Red
        }
        return 99
    }
}
