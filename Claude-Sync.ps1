<#
.SYNOPSIS
    Pull the latest Claude-Installer, refresh tooling, re-provision.

.DESCRIPTION
    The routine "bring this machine up to date" command. Pulls the repo,
    upgrades the Claude CLI and Python packages, updates plugins, then
    re-runs provisioning and doctor.

.PARAMETER NoPull
    Skip git pull -- re-provision from the working tree as-is.

.PARAMETER NoUpgrade
    Skip CLI and package upgrades.

.EXAMPLE
    .\Claude-Sync.ps1
#>
[CmdletBinding()]
param([switch]$NoPull, [switch]$NoUpgrade)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "Claude-Common.ps1")

$RepoRoot = $PSScriptRoot
Write-Banner "Claude-Installer -- Sync"
Update-PathFromRegistry

if (-not $NoPull) {
    Write-Step "Pull latest"
    if (-not (Test-Path (Join-Path $RepoRoot ".git"))) { Write-Skip "not a git checkout" }
    elseif (-not (Test-CommandExists "git")) { Write-Skip "git not on PATH" }
    else {
        $dirty = & git -C $RepoRoot status --porcelain 2>$null
        if ($dirty) {
            Write-Warn2 "working tree has local changes -- pulling with rebase autostash"
            & git -C $RepoRoot pull --rebase --autostash 2>&1 | ForEach-Object { Write-Info $_ }
        } else {
            & git -C $RepoRoot pull --ff-only 2>&1 | ForEach-Object { Write-Info $_ }
        }
        if ($LASTEXITCODE -eq 0) { Write-OK "repo up to date  ($(& git -C $RepoRoot rev-parse --short HEAD))" }
        else { Write-Warn2 "git pull exited $LASTEXITCODE -- continuing with the local tree" }
    }
}

if (-not $NoUpgrade) {
    Write-Step "Upgrade tooling"

    if (Test-CommandExists "npm") {
        Write-Info "npm i -g @anthropic-ai/claude-code@latest ..."
        & npm install -g "@anthropic-ai/claude-code@latest" 2>&1 | Out-Null
        Update-PathFromRegistry
        if ($LASTEXITCODE -eq 0) { Write-OK "claude CLI  $(Get-CommandVersion 'claude')" }
        else { Write-Warn2 "claude CLI upgrade exited $LASTEXITCODE" }
    }

    $req = Join-Path $RepoRoot "requirements\python-requirements.txt"
    if ((Test-CommandExists "python") -and (Test-Path $req)) {
        Write-Info "pip install -U -r requirements/python-requirements.txt ..."
        & python -m pip install --upgrade --quiet -r $req 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-OK "python packages" }
        else { Write-Warn2 "pip exited $LASTEXITCODE" }
    }

    if (Test-CommandExists "claude") {
        Write-Info "claude plugin update --all ..."
        & claude plugin update --all 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-OK "plugins" } else { Write-Warn2 "plugin update exited $LASTEXITCODE" }
    }

    # npx/uvx MCP servers resolve @latest on every spawn -- nothing to upgrade here.
    Write-Skip "npx/uvx MCP servers -- resolved at spawn, nothing pinned"
}

Write-Step "Re-provision"
& (Join-Path $RepoRoot "Claude-Provision.ps1")
$provExit = $LASTEXITCODE

Write-Step "Verify"
& (Join-Path $RepoRoot "Claude-Doctor.ps1")
$docExit = $LASTEXITCODE

Write-Host ""
Write-Host "  Restart Claude Code to pick up MCP and plugin changes." -ForegroundColor Yellow
Write-Host ""
if ($provExit -ne 0 -or $docExit -ne 0) { exit 1 }
exit 0
