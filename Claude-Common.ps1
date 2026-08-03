<#
.SYNOPSIS
    Shared helpers for the Claude-Installer scripts. Dot-source, do not run directly.
#>

Set-StrictMode -Version Latest

# ── Output ────────────────────────────────────────────────────────────────────
$script:StepNo = 0
function Write-Step  ([string]$m) { $script:StepNo++; Write-Host ""; Write-Host "[$script:StepNo] $m" -ForegroundColor Cyan }
function Write-OK    ([string]$m) { Write-Host "    [ OK ]   $m" -ForegroundColor Green }
function Write-Skip  ([string]$m) { Write-Host "    [SKIP]   $m" -ForegroundColor DarkGray }
function Write-Warn2 ([string]$m) { Write-Host "    [WARN]   $m" -ForegroundColor Yellow }
function Write-Fail  ([string]$m) { Write-Host "    [FAIL]   $m" -ForegroundColor Red }
function Write-Info  ([string]$m) { Write-Host "             $m" -ForegroundColor DarkYellow }

function Write-Banner ([string]$title) {
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor Blue
    Write-Host "    $title" -ForegroundColor White
    Write-Host "  ==============================================================" -ForegroundColor Blue
}

# ── Paths ─────────────────────────────────────────────────────────────────────
function Get-RepoRoot   { Split-Path -Parent $PSCommandPath }
function Get-ClaudeHome { Join-Path $env:USERPROFILE ".claude" }

# ── File IO ───────────────────────────────────────────────────────────────────
# Claude Code's JSON parser rejects a UTF-8 BOM. Always write without one.
function Write-TextNoBom {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Text)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try   { return Get-Content -Raw -Path $Path -Encoding UTF8 | ConvertFrom-Json }
    catch { Write-Warn2 "Could not parse JSON: $Path -- $($_.Exception.Message)"; return $null }
}

function Write-JsonFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Object)
    Write-TextNoBom -Path $Path -Text ($Object | ConvertTo-Json -Depth 24)
}

function Backup-File {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $stamp  = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = Join-Path (Get-ClaudeHome) "backups"
    if (-not (Test-Path $backup)) { New-Item -ItemType Directory -Force -Path $backup | Out-Null }
    $dest = Join-Path $backup ("{0}.{1}.bak" -f (Split-Path -Leaf $Path), $stamp)
    Copy-Item -Path $Path -Destination $dest -Force
    return $dest
}

# ── Command discovery ─────────────────────────────────────────────────────────
function Test-CommandExists {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-CommandVersion {
    param([Parameter(Mandatory)][string]$Name, [string]$Arg = "--version")
    if (-not (Test-CommandExists $Name)) { return $null }
    try {
        $out = & $Name $Arg 2>&1 | Select-Object -First 1
        return ($out | Out-String).Trim()
    } catch { return $null }
}

# npm global shims (claude.cmd) are not always on PATH in a fresh shell.
function Update-PathFromRegistry {
    $parts = @()
    foreach ($hive in @("HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment", "HKCU:\Environment")) {
        try {
            $p = (Get-ItemProperty -Path $hive -Name Path -ErrorAction Stop).Path
            if ($p) { $parts += $p }
        } catch { }
    }
    $npmDir = Join-Path $env:APPDATA "npm"
    if (Test-Path $npmDir) { $parts += $npmDir }
    if (Test-CommandExists "npm") {
        try { $g = (& npm prefix -g 2>$null); if ($g -and (Test-Path $g)) { $parts += $g } } catch { }
    }
    $parts += $env:PATH
    $env:PATH = ($parts | Where-Object { $_ } | Select-Object -Unique) -join ";"
}

# ── .env ──────────────────────────────────────────────────────────────────────
function Read-DotEnv {
    param([string]$Path)
    $map = @{}
    if ($Path -and (Test-Path $Path)) {
        foreach ($line in Get-Content -Path $Path -Encoding UTF8) {
            $t = $line.Trim()
            if (-not $t -or $t.StartsWith("#")) { continue }
            $i = $t.IndexOf("=")
            if ($i -lt 1) { continue }
            $k = $t.Substring(0, $i).Trim()
            $v = $t.Substring($i + 1).Trim().Trim('"').Trim("'")
            if ($k) { $map[$k] = $v }
        }
    }
    return $map
}

# .env wins over machine env, so a checked-out repo is self-describing.
function Resolve-Secret {
    param([Parameter(Mandatory)][string]$Name, [hashtable]$EnvMap, [string[]]$Aliases = @())
    foreach ($key in @($Name) + $Aliases) {
        if ($EnvMap -and $EnvMap.ContainsKey($key) -and $EnvMap[$key]) { return $EnvMap[$key] }
        $machine = [Environment]::GetEnvironmentVariable($key)
        if ($machine) { return $machine }
    }
    return $null
}

# ── Path tokens ───────────────────────────────────────────────────────────────
function Resolve-FinanceDir {
    param([hashtable]$EnvMap)
    $explicit = Resolve-Secret -Name "CLAUDE_FINANCE_DIR" -EnvMap $EnvMap
    if ($explicit -and (Test-Path $explicit)) { return $explicit }
    if ($explicit) { Write-Warn2 "CLAUDE_FINANCE_DIR is set but does not exist: $explicit" }

    foreach ($base in @($env:USERPROFILE)) {
        $hit = Get-ChildItem -Path $base -Directory -Filter "OneDrive*" -ErrorAction SilentlyContinue |
               ForEach-Object { Get-ChildItem -Path $_.FullName -Directory -Filter "*Finance*General*" -ErrorAction SilentlyContinue } |
               Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    Write-Warn2 "No finance folder auto-detected -- filesystem MCP will be scoped to your user profile."
    Write-Info  "Set CLAUDE_FINANCE_DIR in .env to scope it properly."
    return $env:USERPROFILE
}

# The Power BI MCP ships inside a versioned VS Code extension dir. Never hardcode the version.
function Resolve-PowerBiMcp {
    $roots = @(
        (Join-Path $env:USERPROFILE ".vscode\extensions"),
        (Join-Path $env:USERPROFILE ".cursor\extensions")
    )
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $ext = Get-ChildItem -Path $root -Directory -Filter "*powerbi-modeling-mcp*" -ErrorAction SilentlyContinue |
               Sort-Object Name -Descending | Select-Object -First 1
        if ($ext) {
            $exe = Join-Path $ext.FullName "server\powerbi-modeling-mcp.exe"
            if (Test-Path $exe) { return $exe }
        }
    }
    return $null
}

# The caveman plugin cache dir is named by commit sha, which changes on every update.
function Resolve-CavemanStatusline {
    $base = Join-Path (Get-ClaudeHome) "plugins\cache\caveman\caveman"
    if (-not (Test-Path $base)) { return $null }
    $ver = Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $ver) { return $null }
    $ps1 = Join-Path $ver.FullName "src\hooks\caveman-statusline.ps1"
    if (Test-Path $ps1) { return $ps1 }
    return $null
}

function Expand-PathTokens {
    # -JsonEscape when substituting into raw JSON text: Windows paths are full of
    # backslashes, and C:\Users lands as the invalid escape \U without it.
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][hashtable]$Tokens,
        [switch]$JsonEscape
    )
    foreach ($k in $Tokens.Keys) {
        if ($null -eq $Tokens[$k]) { continue }
        $v = [string]$Tokens[$k]
        if ($JsonEscape) { $v = $v.Replace('\', '\\').Replace('"', '\"') }
        $Value = $Value.Replace('${' + $k + '}', $v)
    }
    return $Value
}

# Never print a resolved secret. Dry-run output and logs go to terminals,
# scrollback and screenshots.
function Format-RedactedCommand {
    param([Parameter(Mandatory)][string[]]$Args)
    $out = @()
    for ($i = 0; $i -lt $Args.Count; $i++) {
        $a = $Args[$i]
        if ($a -eq "--env" -and $i + 1 -lt $Args.Count) {
            $pair = $Args[$i + 1]
            $eq   = $pair.IndexOf("=")
            if ($eq -gt 0) {
                $key = $pair.Substring(0, $eq)
                $val = $pair.Substring($eq + 1)
                # Tuning knobs are not secrets; anything long and opaque is.
                $safe = ($key -match '(?i)limit|timeout|size|count|level|mode|browser') -or $val.Length -le 8
                $shown = if ($safe) { $val } else { "<redacted:$($val.Length) chars>" }
                $out += @($a, "$key=$shown")
                $i++
                continue
            }
        }
        elseif ($a -match '^(https?://[^?]+)\?(.+)$') { $out += "$($Matches[1])?<redacted>"; continue }
        $out += $a
    }
    return ($out -join " ")
}

function Test-HasUnresolvedToken {
    param([string]$Value)
    return ($Value -match '\$\{[A-Za-z_][A-Za-z0-9_:]*\}')
}
