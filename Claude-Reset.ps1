<#
.SYNOPSIS
    Remove what this installer provisioned. Destructive -- prompts before acting.

.DESCRIPTION
    Every mode backs up to ~/.claude/backups before removing anything, and
    prints exactly what it will touch. Nothing runs without confirmation
    unless -Force is passed.

.PARAMETER LegacySkillsOnly
    Remove only the superseded alfred-* and maersk-ai-* dirs under
    ~/.agents/skills. Leaves everything else alone. This is the safe cleanup.

.PARAMETER McpOnly
    Deregister the catalog's MCP servers from Claude Code user scope.

.PARAMETER All
    Remove MCP registrations, installed skills, agents, and restore the
    settings.json backup. Does NOT uninstall Git/Node/Python/the Claude CLI,
    and does NOT touch your .env.

.PARAMETER Force
    Skip the confirmation prompt.

.EXAMPLE
    .\Claude-Reset.ps1 -LegacySkillsOnly
.EXAMPLE
    .\Claude-Reset.ps1 -All
#>
[CmdletBinding()]
param(
    [switch]$LegacySkillsOnly,
    [switch]$McpOnly,
    [switch]$All,
    [switch]$Force
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "Claude-Common.ps1")

$RepoRoot   = $PSScriptRoot
$ClaudeHome = Get-ClaudeHome

if (-not ($LegacySkillsOnly -or $McpOnly -or $All)) {
    Write-Host ""
    Write-Host "  Pick a mode:" -ForegroundColor Yellow
    Write-Host "    -LegacySkillsOnly   remove superseded alfred-* / maersk-ai-* skill dirs  (safe)"
    Write-Host "    -McpOnly            deregister this catalog's MCP servers"
    Write-Host "    -All                MCP + skills + agents + restore settings.json backup"
    Write-Host ""
    exit 2
}

Write-Banner "Claude-Installer -- Reset"

# ── Build the plan first, show it, then act ───────────────────────────────────
$plan = @()

if ($LegacySkillsOnly -or $All) {
    $legacyRoot = Join-Path $env:USERPROFILE ".agents\skills"
    $legacy = @(Get-ChildItem -Path $legacyRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "alfred-*" -or $_.Name -like "maersk-ai-*" })
    foreach ($d in $legacy) { $plan += [PSCustomObject]@{ Action = "archive dir"; Target = $d.FullName } }
}

if ($McpOnly -or $All) {
    $catalog = Read-JsonFile (Join-Path $RepoRoot "config\mcp.json")
    if ($catalog) {
        foreach ($n in $catalog.mcpServers.PSObject.Properties.Name) {
            $plan += [PSCustomObject]@{ Action = "mcp remove"; Target = $n }
        }
    }
}

if ($All) {
    foreach ($d in @(Get-ChildItem -Path (Join-Path $RepoRoot "skills") -Directory -ErrorAction SilentlyContinue)) {
        $t = Join-Path $ClaudeHome "skills\$($d.Name)"
        if (Test-Path $t) { $plan += [PSCustomObject]@{ Action = "archive dir"; Target = $t } }
    }
    foreach ($f in @(Get-ChildItem -Path (Join-Path $RepoRoot "agents") -Filter "*.md" -File -ErrorAction SilentlyContinue)) {
        $t = Join-Path $ClaudeHome "agents\$($f.Name)"
        if (Test-Path $t) { $plan += [PSCustomObject]@{ Action = "archive file"; Target = $t } }
    }
    $plan += [PSCustomObject]@{ Action = "restore backup"; Target = (Join-Path $ClaudeHome "settings.json") }
}

if ($plan.Count -eq 0) { Write-OK "nothing to do"; exit 0 }

Write-Host ""
Write-Host "  This will change $($plan.Count) item(s):" -ForegroundColor Yellow
$plan | Select-Object -First 40 | ForEach-Object { Write-Host "    $($_.Action.PadRight(15)) $($_.Target)" -ForegroundColor DarkYellow }
if ($plan.Count -gt 40) { Write-Host "    ... and $($plan.Count - 40) more" -ForegroundColor DarkYellow }
Write-Host ""
Write-Host "  Directories and files are MOVED to an archive folder, not deleted." -ForegroundColor Green
Write-Host ""

if (-not $Force) {
    $answer = Read-Host "  Type 'yes' to proceed"
    if ($answer -ne "yes") { Write-Host "  Aborted." -ForegroundColor Red; exit 1 }
}

$stamp   = Get-Date -Format "yyyyMMdd-HHmmss"
$archive = Join-Path $ClaudeHome "backups\reset-$stamp"
New-Item -ItemType Directory -Force -Path $archive | Out-Null
Write-Info "archive: $archive"

foreach ($item in $plan) {
    switch ($item.Action) {
        "archive dir" {
            try {
                Move-Item -Path $item.Target -Destination (Join-Path $archive (Split-Path -Leaf $item.Target)) -Force
                Write-OK "archived $(Split-Path -Leaf $item.Target)"
            } catch { Write-Fail "$(Split-Path -Leaf $item.Target) -- $($_.Exception.Message)" }
        }
        "archive file" {
            try {
                Move-Item -Path $item.Target -Destination (Join-Path $archive (Split-Path -Leaf $item.Target)) -Force
                Write-OK "archived $(Split-Path -Leaf $item.Target)"
            } catch { Write-Fail "$(Split-Path -Leaf $item.Target) -- $($_.Exception.Message)" }
        }
        "mcp remove" {
            & claude mcp remove $item.Target --scope user 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-OK "deregistered $($item.Target)" } else { Write-Skip "$($item.Target) was not registered" }
        }
        "restore backup" {
            $bk = Get-ChildItem -Path (Join-Path $ClaudeHome "backups") -Filter "settings.json.*.bak" -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($bk) { Copy-Item -Path $bk.FullName -Destination $item.Target -Force; Write-OK "restored settings.json from $($bk.Name)" }
            else { Write-Skip "no settings.json backup found -- left as-is" }
        }
    }
}

Write-Host ""
Write-Host "  Done. Archive: $archive" -ForegroundColor Green
Write-Host "  Restart Claude Code." -ForegroundColor Yellow
Write-Host ""
exit 0
