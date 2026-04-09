<#
.SYNOPSIS
    Botnet Detection Toolkit launcher / dot-sourcer.

.DESCRIPTION
    Deploy.ps1 is the canonical entry point for the botnet-detection
    toolkit when invoked via `git clone` deployment. It is responsible
    for the entire bootstrap sequence:

        Init -> Logging -> EnvSnapshot -> ImportDotEnv -> ImportLocalConfig
            -> MaskedParams -> OutputDir -> DotSourceModules -> LoadConfig
            -> Announce

    After Deploy.ps1 completes, the operator's session has:
        - $script:LogFile pointing at the deploy log
        - All helper functions from modules/_Shared.ps1 in scope
        - All Invoke-* commands from modules/*.ps1 in scope
        - $script:Exclusions and $script:TriageWeights populated
        - .env values loaded into the process environment (if .env exists)

    Standalone-paste path: when `git clone` is blocked (the typical
    SentinelOne/N-Able RemoteShell scenario), operators do NOT run
    Deploy.ps1. Instead they paste a single Invoke-* module file
    directly into the target shell. Each module ships with inline
    fallback stubs of the helpers it needs, so the paste path works
    without _Shared.ps1 ever loading.

    Deploy.ps1 is therefore optimized for the cloned-repo path. It
    does NOT try to be standalone -- it assumes the repo layout exists.

.PARAMETER OutputDir
    Where logs and artifacts go. Defaults to "$PSScriptRoot\output".

.PARAMETER DryRun
    Skip all writes; log "[DRY-RUN]" prefixes for would-be operations.

.PARAMETER DebugMode
    Promote DEBUG-level log entries from file-only to console.

.EXAMPLE
    . .\Deploy.ps1
    Invoke-BotnetTriage -IOCFile .\iocs\engagement-2026-04.txt

.EXAMPLE
    . .\Deploy.ps1 -DryRun -DebugMode

.NOTES
    Exit codes:
        0  -- full success
        10 -- config file missing (non-fatal; Deploy continues with warnings)
        20 -- module dot-source failure (a critical helper file failed to load)
        99 -- unhandled error
#>

[CmdletBinding()]
param(
    [string]$OutputDir,
    [switch]$DryRun,
    [switch]$DebugMode
)

# ============================================================
#region  U-Init
# Purpose : Strict mode, error preference, stopwatch, anchors.
# ============================================================
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:ScriptTimer = [System.Diagnostics.Stopwatch]::StartNew()
$script:DeployRoot  = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($script:DeployRoot)) {
    # Edge case: dot-sourced from a position where $PSScriptRoot is empty.
    # Fall back to the current location.
    $script:DeployRoot = (Get-Location).Path
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $script:DeployRoot 'output'
}

# Track unit-level success / failure for the final FULL/PARTIAL announcement.
$script:DeployStatus = [ordered]@{}
$script:DeployErrors = @()
#endregion U-Init


# ============================================================
#region  U-OutputDir (early)
# Purpose : Output dir must exist BEFORE U-Logging because the
#           log file lives inside it. This breaks the strict
#           PHASE1_PLAN.md ordering of "U-OutputDir = step 7"
#           but the dependency is mechanical: U-Logging needs a
#           writable directory.
# ============================================================
try {
    if (-not (Test-Path $OutputDir)) {
        if ($DryRun) {
            Write-Host "[DRY-RUN] Would create output dir: $OutputDir"
        } else {
            New-Item -ItemType Directory -Path $OutputDir -Force -ErrorAction Stop | Out-Null
        }
    }
    $script:DeployStatus['U-OutputDir'] = 'OK'
} catch {
    Write-Host "[FATAL] Cannot create output dir '$OutputDir': $($_.Exception.Message)" -ForegroundColor Red
    exit 10
}
#endregion U-OutputDir


# ============================================================
#region  U-Logging
# Purpose : Initialize $script:LogFile and emit SCRIPT_START.
#           Cannot use Write-Log yet because _Shared.ps1 is not
#           dot-sourced -- define an INLINE bootstrap logger that
#           is replaced by the authoritative one after dot-source.
# ============================================================
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogFile = Join-Path $OutputDir "deploy_${ts}.log"
$script:DebugMode = [bool]$DebugMode

if (-not $DryRun) {
    try { New-Item -ItemType File -Path $script:LogFile -Force -ErrorAction Stop | Out-Null } catch { }
}

# Inline bootstrap Write-Log -- used until _Shared.ps1 dot-sources its
# authoritative version (which has the same signature). After dot-source
# Write-Log gets redefined and this version is replaced.
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line  = "[$stamp] [$Level] $Message"
    if ($Level -ne 'DEBUG' -or $script:DebugMode) {
        $color = switch ($Level) { 'WARN' { 'Yellow' }; 'ERROR' { 'Red' }; 'DEBUG' { 'DarkGray' }; default { 'Gray' } }
        Write-Host $line -ForegroundColor $color
    }
    if ($script:LogFile -and -not $DryRun) {
        try { Add-Content -Path $script:LogFile -Value $line -ErrorAction Stop } catch { }
    }
}

Write-Log -Level INFO -Message "SCRIPT_START: Deploy.ps1 | Host: $env:COMPUTERNAME | User: $env:USERNAME | LogFile: $script:LogFile"
if ($DryRun)    { Write-Log -Level WARN -Message "DRY-RUN MODE ACTIVE - no files will be written" }
if ($DebugMode) { Write-Log -Level INFO -Message "DEBUG MODE ACTIVE - DEBUG entries promoted to console" }
$script:DeployStatus['U-Logging'] = 'OK'
#endregion U-Logging


# ============================================================
# UNIT WRAPPER
# ============================================================
# Each remaining unit logs UNIT_START / UNIT_END / UNIT_FAILED
# via this wrapper, recording success / failure into
# $script:DeployStatus for the final FULL/PARTIAL announcement.
function Invoke-DeployUnit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$UnitName,
        [Parameter(Mandatory)][scriptblock]$Body,
        [switch]$Critical
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Log -Level INFO -Message "UNIT_START: $UnitName"
    try {
        & $Body
        $sw.Stop()
        Write-Log -Level INFO -Message "UNIT_END: $UnitName | Duration: $($sw.Elapsed.TotalSeconds)s"
        $script:DeployStatus[$UnitName] = 'OK'
    } catch {
        $sw.Stop()
        $msg = "UNIT_FAILED: $UnitName | $($_.Exception.Message) | At: $($_.InvocationInfo.PositionMessage)"
        Write-Log -Level ERROR -Message $msg
        $script:DeployStatus[$UnitName] = 'FAILED'
        $script:DeployErrors += [pscustomobject]@{ Unit = $UnitName; Error = $_.Exception.Message }
        if ($Critical) {
            Write-Log -Level ERROR -Message "CRITICAL_UNIT_FAILED: $UnitName -- aborting Deploy.ps1"
            exit 20
        }
    }
}


# ============================================================
#region  U-EnvSnapshot
# ============================================================
Invoke-DeployUnit -UnitName 'U-EnvSnapshot' -Body {
    $isAdmin = $false
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = [System.Security.Principal.WindowsPrincipal]::new($id)
        $isAdmin = $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { }
    Write-Log -Level INFO -Message ("ENV_SNAPSHOT: PSVersion={0} | OS={1} | Host={2} | User={3} | Elevated={4} | CWD='{5}' | DeployRoot='{6}'" -f `
        $PSVersionTable.PSVersion, [System.Environment]::OSVersion.VersionString, $env:COMPUTERNAME, $env:USERNAME, $isAdmin, (Get-Location).Path, $script:DeployRoot)
}
#endregion U-EnvSnapshot


# ============================================================
#region  U-DotSourceModules
# Purpose : Dot-source _Shared.ps1 first so Import-DotEnv,
#           Import-LocalConfig, Get-MaskedParams, and Resolve-Config
#           are available for the units below. Then dot-source the
#           Invoke-* modules.
#
# Critical: yes -- without _Shared.ps1 the rest of the bootstrap
#           units have no way to do their job.
#
# IMPORTANT -- this unit is NOT wrapped in Invoke-DeployUnit. The
# wrapper invokes its body via `& $Body`, which creates a child
# scope. Functions defined inside a child scope die when that scope
# pops, so dot-sourcing _Shared.ps1 from within the wrapper would
# load all helpers into a transient function scope and they would
# vanish before the next unit could call them. Dot-sourcing has to
# happen at SCRIPT scope.
# ============================================================
$sw = [System.Diagnostics.Stopwatch]::StartNew()
Write-Log -Level INFO -Message "UNIT_START: U-DotSourceModules"
$dotSourceFailed = $false
try {
    $sharedPath = Join-Path $script:DeployRoot 'modules\_Shared.ps1'
    if (-not (Test-Path $sharedPath)) {
        throw "modules\_Shared.ps1 not found at '$sharedPath'"
    }
    . $sharedPath
    Write-Log -Level INFO -Message "DOTSOURCE_OK: modules\_Shared.ps1"
} catch {
    $sw.Stop()
    Write-Log -Level ERROR -Message "UNIT_FAILED: U-DotSourceModules | $($_.Exception.Message)"
    Write-Log -Level ERROR -Message "CRITICAL_UNIT_FAILED: U-DotSourceModules -- aborting Deploy.ps1"
    $script:DeployStatus['U-DotSourceModules'] = 'FAILED'
    exit 20
}

# Module files: dot-source each individually so one bad file doesn't
# block the others. _Shared.ps1 is intentionally excluded (already
# loaded above) and any file starting with '_' is treated as private.
$moduleDir = Join-Path $script:DeployRoot 'modules'
$moduleFiles = @(Get-ChildItem -Path $moduleDir -Filter 'Invoke-*.ps1' -ErrorAction SilentlyContinue)
if ($moduleFiles.Count -eq 0) {
    Write-Log -Level WARN -Message "DOTSOURCE_NO_MODULES: no Invoke-*.ps1 files found in '$moduleDir'"
} else {
    foreach ($mf in $moduleFiles) {
        try {
            . $mf.FullName
            Write-Log -Level INFO -Message "DOTSOURCE_OK: modules\$($mf.Name)"
        } catch {
            $dotSourceFailed = $true
            Write-Log -Level ERROR -Message "DOTSOURCE_FAILED: modules\$($mf.Name) | $($_.Exception.Message)"
            $script:DeployErrors += [pscustomobject]@{ Unit = 'U-DotSourceModules'; Error = "$($mf.Name): $($_.Exception.Message)" }
        }
    }
}
$sw.Stop()
if ($dotSourceFailed) {
    Write-Log -Level WARN -Message "UNIT_END: U-DotSourceModules | Duration: $($sw.Elapsed.TotalSeconds)s | partial -- see DOTSOURCE_FAILED entries"
    $script:DeployStatus['U-DotSourceModules'] = 'PARTIAL'
} else {
    Write-Log -Level INFO -Message "UNIT_END: U-DotSourceModules | Duration: $($sw.Elapsed.TotalSeconds)s"
    $script:DeployStatus['U-DotSourceModules'] = 'OK'
}

# Track which functions came from our modules so U-Announce can
# distinguish toolkit commands from any Invoke-* polluting the
# session from PSModulePath (Microsoft Graph, Pester, etc.).
$script:ToolkitFunctionNames = @()
foreach ($mf in $moduleFiles) {
    # Re-parse the file to extract its top-level function names. Cheap,
    # ~ms per file, and avoids relying on `(Get-Command).ScriptBlock.File`
    # which is not always populated for dot-sourced functions.
    try {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($mf.FullName, [ref]$tokens, [ref]$errs)
        $fnAsts = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        foreach ($fn in $fnAsts) {
            if ($fn.Name -like 'Invoke-*' -and $fn.Name -ne 'Invoke-DeployUnit') {
                $script:ToolkitFunctionNames += $fn.Name
            }
        }
    } catch { }
}
$script:ToolkitFunctionNames = @($script:ToolkitFunctionNames | Select-Object -Unique)


# ============================================================
#region  U-ImportDotEnv
# ============================================================
Invoke-DeployUnit -UnitName 'U-ImportDotEnv' -Body {
    $envPath = Join-Path $script:DeployRoot '.env'
    if (-not (Test-Path $envPath)) {
        Write-Log -Level WARN -Message "CONFIG_MISSING: .env file not found at '$envPath' (non-fatal -- Phase 1 has no API dependencies)"
        return
    }
    $count = Import-DotEnv -Path $envPath
    Write-Log -Level INFO -Message "DOTENV_RESULT: $count variable(s) loaded from .env"
}
#endregion U-ImportDotEnv


# ============================================================
#region  U-ImportLocalConfig
# Purpose : Merge config/config.example.json with optional
#           config/config.local.json (local wins).
# ============================================================
Invoke-DeployUnit -UnitName 'U-ImportLocalConfig' -Body {
    $examplePath = Join-Path $script:DeployRoot 'config\config.example.json'
    $localPath   = Join-Path $script:DeployRoot 'config\config.local.json'
    $script:GlobalConfig = Import-LocalConfig -ExamplePath $examplePath -LocalPath $localPath
    Write-Log -Level DEBUG -Message "GLOBAL_CONFIG_KEYS: $((($script:GlobalConfig.PSObject.Properties.Name) -join ','))"
}
#endregion U-ImportLocalConfig


# ============================================================
#region  U-MaskedParams
# Purpose : Emit a single PARAMS log line summarizing how
#           Deploy.ps1 was invoked, with sensitive values masked.
# ============================================================
Invoke-DeployUnit -UnitName 'U-MaskedParams' -Body {
    $paramTable = @{
        OutputDir = $OutputDir
        DryRun    = [bool]$DryRun
        DebugMode = [bool]$DebugMode
    }
    $masked = Get-MaskedParams -Parameters $paramTable
    Write-Log -Level INFO -Message "PARAMS: $masked"
}
#endregion U-MaskedParams


# ============================================================
#region  U-LoadConfig
# Purpose : Populate $script:Exclusions and $script:TriageWeights
#           from config/exclusions.json and config/triage-weights.json.
#           Hardcoded fallbacks when files absent -- Resolve-Config
#           handles the file-vs-fallback decision and logs the result.
# ============================================================
Invoke-DeployUnit -UnitName 'U-LoadConfig' -Body {
    $exclPath    = Join-Path $script:DeployRoot 'config\exclusions.json'
    $weightsPath = Join-Path $script:DeployRoot 'config\triage-weights.json'

    $exclFallback = @{
        Processes      = @('SentinelAgent.exe','MsMpEng.exe')
        Ports          = @(7680)
        PrivateSubnets = @('10.0.0.0/8','172.16.0.0/12','192.168.0.0/16')
        TrustedSigners = @('Microsoft Corporation')
    }
    $weightsFallback = @{
        Description    = 'Inline fallback (Deploy.ps1)'
        Connections    = @{ PrivateToPublicNonBrowser = 25; ProcessInTempOrAppData = 30; IOCMatchMultiplier = 2.0 }
        ListeningPorts = @{ HighPortNonServerProcess = 15; ListeningOnAllInterfaces = 10 }
        ScheduledTasks = @{ NonMicrosoftAuthor = 10; UserWritableActionPath = 25; LOLBinInArgs = 35 }
        Services       = @{ UserWritablePath = 30; Unsigned = 20 }
        Autoruns       = @{ UserWritablePath = 25; LOLBinInCommand = 35 }
        DnsCache       = @{ RawIPEntry = 10; IOCMatchMultiplier = 2.0 }
        HostsFile      = @{ AnyNonDefaultEntry = 40 }
        LocalAccounts  = @{ RecentlyCreated = 30; RecentPasswordSet = 20; NewAdminGroupMember = 45 }
        Thresholds     = @{ High = 50; Medium = 25 }
    }

    $script:Exclusions    = Resolve-Config -Path $exclPath    -Fallback $exclFallback    -Label 'exclusions.json'
    $script:TriageWeights = Resolve-Config -Path $weightsPath -Fallback $weightsFallback -Label 'triage-weights.json'

    $exclSource    = if ($script:Exclusions    -is [hashtable]) { 'inline-fallback' } else { 'file' }
    $weightsSource = if ($script:TriageWeights -is [hashtable]) { 'inline-fallback' } else { 'file' }
    Write-Log -Level INFO -Message "CONFIG_RESOLVED: exclusions=$exclSource | triage-weights=$weightsSource"
}
#endregion U-LoadConfig


# ============================================================
#region  U-Announce
# Purpose : Print available Invoke-* commands and final status.
# ============================================================
Invoke-DeployUnit -UnitName 'U-Announce' -Body {
    # Filter to functions whose names came from our modules/Invoke-*.ps1
    # files (captured into $script:ToolkitFunctionNames during U-DotSourceModules).
    # Cross-check that each is actually defined in the current session -- a
    # name in the AST list that isn't in scope means the file failed to
    # dot-source even though parsing succeeded.
    $available = @()
    foreach ($name in $script:ToolkitFunctionNames) {
        if (Get-Command $name -CommandType Function -ErrorAction SilentlyContinue) {
            $available += $name
        }
    }
    if ($available.Count -gt 0) {
        Write-Log -Level INFO -Message "AVAILABLE_COMMANDS: $($available -join ', ')"
    } else {
        Write-Log -Level WARN -Message "AVAILABLE_COMMANDS: none -- no toolkit Invoke-* commands found in scope"
    }
}
#endregion U-Announce


# ============================================================
# FINAL STATUS
# ============================================================
$script:ScriptTimer.Stop()
$total = [math]::Round($script:ScriptTimer.Elapsed.TotalSeconds, 2)
$failed = @($script:DeployStatus.GetEnumerator() | Where-Object { $_.Value -eq 'FAILED' })
if ($failed.Count -eq 0) {
    Write-Log -Level INFO -Message "FULL_SUCCESS: Deploy.ps1 complete | $($script:DeployStatus.Count) unit(s) OK | Total Duration: ${total}s"
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "  Botnet Detection Toolkit ready" -ForegroundColor Green
    Write-Host "  Available: Invoke-BotnetTriage" -ForegroundColor Green
    Write-Host "  Example:   Invoke-BotnetTriage -IOCFile .\iocs\<engagement>.txt" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host ""
} else {
    $failedNames = ($failed | ForEach-Object Key) -join ', '
    Write-Log -Level WARN -Message "PARTIAL_SUCCESS: Deploy.ps1 complete with errors | Failed units: $failedNames | Total Duration: ${total}s"
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host "  Botnet Detection Toolkit loaded with WARNINGS" -ForegroundColor Yellow
    Write-Host "  Failed units: $failedNames" -ForegroundColor Yellow
    Write-Host "  Review log: $script:LogFile" -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host ""
}
