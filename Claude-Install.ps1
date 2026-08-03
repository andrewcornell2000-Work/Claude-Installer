<#
.SYNOPSIS
    Install prerequisites for Claude Code, then hand off to Claude-Provision.ps1.

.DESCRIPTION
    Brings a bare Windows machine to a working Claude Code setup:
    Git, Node LTS, Python 3.10+, uv/uvx, the Claude Code CLI, and the Python
    packages the skills depend on. Then provisions MCPs, plugins, skills,
    agents, hooks and memory.

    Idempotent. Anything already present is left alone.

.PARAMETER SkipPrereqs
    Jump straight to provisioning. Use when Git/Node/Python are already sorted.

.PARAMETER SkipProvision
    Install prerequisites only.

.PARAMETER Buckets
    Passed through to Claude-Provision.ps1.

.EXAMPLE
    .\Claude-Install.ps1
.EXAMPLE
    .\Claude-Install.ps1 -Buckets core,data
#>
[CmdletBinding()]
param(
    [switch]$SkipPrereqs,
    [switch]$SkipProvision,
    [string[]]$Buckets
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Claude-Common.ps1")

$RepoRoot = $PSScriptRoot
Write-Banner "Claude-Installer -- Setup"
Update-PathFromRegistry

$failures = @()

function Install-ViaWinget {
    param([string]$Label, [string]$Id, [string]$Check)
    if (Test-CommandExists $Check) {
        Write-OK "$Label already installed  ($(Get-CommandVersion $Check))"
        return $true
    }
    if (-not (Test-CommandExists "winget")) {
        Write-Fail "$Label missing and winget is unavailable."
        Write-Info "Install $Label manually, then re-run."
        return $false
    }
    Write-Info "installing $Label via winget ($Id)..."
    & winget install --id $Id --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    Update-PathFromRegistry
    if (Test-CommandExists $Check) { Write-OK "$Label installed"; return $true }
    Write-Fail "$Label install did not put '$Check' on PATH. A new terminal may be needed."
    return $false
}

if (-not $SkipPrereqs) {

    Write-Step "Core tooling"
    if (-not (Install-ViaWinget -Label "Git"        -Id "Git.Git"             -Check "git"))    { $failures += "git" }
    if (-not (Install-ViaWinget -Label "Node LTS"   -Id "OpenJS.NodeJS.LTS"   -Check "node"))   { $failures += "node" }
    if (-not (Install-ViaWinget -Label "Python 3.12" -Id "Python.Python.3.12" -Check "python")) { $failures += "python" }

    if (Test-CommandExists "node") {
        $nodeMajor = ((Get-CommandVersion "node") -replace '[^\d.]', '') -split '\.' | Select-Object -First 1
        if ($nodeMajor -and [int]$nodeMajor -lt 18) {
            Write-Warn2 "Node $nodeMajor is below the required 18. Upgrade before relying on npx MCP servers."
        }
    }

    Write-Step "uv / uvx  (required by fetch, markitdown, duckdb)"
    if (Test-CommandExists "uvx") { Write-OK "uvx present  ($(Get-CommandVersion 'uvx'))" }
    else {
        if (Test-CommandExists "python") {
            Write-Info "installing uv via pip..."
            & python -m pip install --upgrade --quiet uv 2>&1 | Out-Null
            Update-PathFromRegistry
        }
        if (Test-CommandExists "uvx") { Write-OK "uvx installed" }
        else { Write-Warn2 "uvx not on PATH -- fetch, markitdown and duckdb will be skipped at provision time."; $failures += "uvx" }
    }

    Write-Step "Claude Code CLI"
    if (Test-CommandExists "claude") { Write-OK "claude present  ($(Get-CommandVersion 'claude'))" }
    else {
        if (-not (Test-CommandExists "npm")) {
            Write-Fail "npm unavailable -- cannot install the Claude Code CLI."
            $failures += "claude"
        } else {
            Write-Info "npm i -g @anthropic-ai/claude-code ..."
            & npm install -g "@anthropic-ai/claude-code" 2>&1 | Out-Null
            Update-PathFromRegistry
            if (Test-CommandExists "claude") { Write-OK "claude installed  ($(Get-CommandVersion 'claude'))" }
            else { Write-Fail "claude still not on PATH after npm install."; $failures += "claude" }
        }
    }

    Write-Step "Python packages"
    $reqFile = Join-Path $RepoRoot "requirements\python-requirements.txt"
    if (-not (Test-Path $reqFile)) { Write-Skip "requirements/python-requirements.txt not found" }
    elseif (-not (Test-CommandExists "python")) { Write-Skip "python unavailable" }
    else {
        Write-Info "pip install -U -r requirements/python-requirements.txt ..."
        & python -m pip install --upgrade --quiet -r $reqFile 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-OK "python packages installed" }
        else { Write-Warn2 "pip exited $LASTEXITCODE -- some packages may be missing. Run manually to see which." }
    }
}

# ── .env ──────────────────────────────────────────────────────────────────────
Write-Step "Configuration"
$envPath = Join-Path $RepoRoot ".env"
if (Test-Path $envPath) { Write-OK ".env present" }
else {
    Copy-Item -Path (Join-Path $RepoRoot ".env.template") -Destination $envPath -Force
    Write-OK ".env created from template"
    Write-Warn2 "Fill in .env before relying on the github / firecrawl / fal-ai / supabase servers."
    Write-Info  "notepad `"$envPath`""
}

# ── Auth ──────────────────────────────────────────────────────────────────────
Write-Step "Claude authentication"
if (Test-CommandExists "claude") {
    $authed = $false
    try { & claude auth status 2>&1 | Out-Null; $authed = ($LASTEXITCODE -eq 0) } catch { }
    if ($authed) { Write-OK "already signed in" }
    else {
        Write-Warn2 "not signed in"
        Write-Info  "run:  claude auth login"
    }
}

# ── Hand off ──────────────────────────────────────────────────────────────────
if ($failures.Count -gt 0) {
    Write-Banner "Prerequisites incomplete"
    Write-Host "  missing: $($failures -join ', ')" -ForegroundColor Red
    Write-Host "  Fix those, open a NEW terminal, then re-run this script." -ForegroundColor Yellow
    Write-Host ""
    exit 3
}

if ($SkipProvision) {
    Write-Banner "Prerequisites ready"
    Write-Host "  Next:  .\Claude-Provision.ps1" -ForegroundColor Cyan
    Write-Host ""
    exit 0
}

$provArgs = @{}
if ($Buckets) { $provArgs["Buckets"] = $Buckets }
& (Join-Path $RepoRoot "Claude-Provision.ps1") @provArgs
exit $LASTEXITCODE
