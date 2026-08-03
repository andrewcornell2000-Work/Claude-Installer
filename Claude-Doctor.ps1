<#
.SYNOPSIS
    Verify a Claude Code installation provisioned by this repo.

.DESCRIPTION
    Read-only. Checks prerequisites, MCP registration, plugins, skills, agents,
    settings and memory, then prints a pass/warn/fail table and exits non-zero
    if anything is broken.

.PARAMETER Fix
    Attempt the safe repairs (re-run provisioning for whatever is missing).

.EXAMPLE
    .\Claude-Doctor.ps1
.EXAMPLE
    .\Claude-Doctor.ps1 -Fix
#>
[CmdletBinding()]
param([switch]$Fix)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "Claude-Common.ps1")

$RepoRoot   = $PSScriptRoot
$ClaudeHome = Get-ClaudeHome
$EnvMap     = Read-DotEnv (Join-Path $RepoRoot ".env")

$Results = @()
function Add-Check {
    param([string]$Area, [string]$Name, [ValidateSet("PASS","WARN","FAIL")][string]$State, [string]$Detail = "")
    $script:Results += [PSCustomObject]@{ Area = $Area; Name = $Name; State = $State; Detail = $Detail }
}

Write-Banner "Claude-Installer -- Doctor"
Update-PathFromRegistry

# ── Prerequisites ─────────────────────────────────────────────────────────────
Write-Step "Prerequisites"
foreach ($t in @(
    @{ n = "git";    req = $true  },
    @{ n = "node";   req = $true  },
    @{ n = "npm";    req = $true  },
    @{ n = "python"; req = $true  },
    @{ n = "uvx";    req = $false },
    @{ n = "claude"; req = $true  }
)) {
    $v = Get-CommandVersion $t.n
    if ($v)          { Write-OK "$($t.n)  $v";                        Add-Check "prereq" $t.n "PASS" $v }
    elseif ($t.req)  { Write-Fail "$($t.n) not found";                Add-Check "prereq" $t.n "FAIL" "not on PATH" }
    else             { Write-Warn2 "$($t.n) not found (optional)";    Add-Check "prereq" $t.n "WARN" "not on PATH -- uvx servers will not run" }
}

# ── .env ──────────────────────────────────────────────────────────────────────
Write-Step "Configuration"
$envPath = Join-Path $RepoRoot ".env"
if (Test-Path $envPath) { Write-OK ".env present ($($EnvMap.Keys.Count) keys)"; Add-Check "config" ".env" "PASS" "$($EnvMap.Keys.Count) keys" }
else { Write-Warn2 ".env missing -- key-gated servers cannot start"; Add-Check "config" ".env" "WARN" "missing" }

# A token in .env is fine. A token committed to git is not.
$leaked = @()
foreach ($f in @("config\mcp.json", "config\plugins.json", "config\settings.template.json", "claude.manifest.json")) {
    $p = Join-Path $RepoRoot $f
    if (-not (Test-Path $p)) { continue }
    $txt = Get-Content -Raw -Path $p -Encoding UTF8
    if ($txt -match 'gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|fc-[A-Za-z0-9]{20,}') { $leaked += $f }
}
if ($leaked.Count -gt 0) {
    Write-Fail "credential-shaped string in tracked file(s): $($leaked -join ', ')"
    Add-Check "config" "secrets" "FAIL" ($leaked -join ", ")
} else { Write-OK "no credentials in tracked config"; Add-Check "config" "secrets" "PASS" }

# ── MCP servers ───────────────────────────────────────────────────────────────
Write-Step "MCP servers"
$catalog  = Read-JsonFile (Join-Path $RepoRoot "config\mcp.json")
$live     = @()
if (Test-CommandExists "claude") {
    try { $live = @(& claude mcp list 2>&1 | ForEach-Object { ($_ -split "[:\s]")[0] } | Where-Object { $_ }) } catch { }
}
if ($live.Count -eq 0) { Write-Warn2 "claude mcp list returned nothing -- cannot verify registration" }

$registered = 0
foreach ($name in $catalog.mcpServers.PSObject.Properties.Name) {
    $s      = $catalog.mcpServers.$name
    $bucket = if ($s.PSObject.Properties.Name -contains "_bucket") { $s._bucket } else { "core" }
    $needs  = @()
    if ($s.PSObject.Properties.Name -contains "_requires") { $needs = @($s._requires) }
    $missingKey = @($needs | Where-Object { -not (Resolve-Secret -Name $_ -EnvMap $EnvMap) })
    $cmdMissing = ($s.PSObject.Properties.Name -contains "_requiresCommand") -and (-not (Test-CommandExists $s._requiresCommand))

    if ($live -contains $name) { Write-OK "$name  [$bucket]"; Add-Check "mcp" $name "PASS" $bucket; $registered++ }
    elseif ($missingKey.Count) { Write-Skip "$name -- needs $($missingKey -join ', ')"; Add-Check "mcp" $name "WARN" "missing $($missingKey -join ',')" }
    elseif ($cmdMissing)       { Write-Skip "$name -- '$($s._requiresCommand)' not on PATH"; Add-Check "mcp" $name "WARN" "no $($s._requiresCommand)" }
    else                       { Write-Warn2 "$name not registered"; Add-Check "mcp" $name "WARN" "not registered" }
}
Write-Info "$registered of $($catalog.mcpServers.PSObject.Properties.Name.Count) catalog servers registered"

# ── Plugins ───────────────────────────────────────────────────────────────────
Write-Step "Plugins"
$pcat      = Read-JsonFile (Join-Path $RepoRoot "config\plugins.json")
$installed = Read-JsonFile (Join-Path $ClaudeHome "plugins\installed_plugins.json")
foreach ($p in $pcat.plugins) {
    $have = $installed -and ($installed.plugins.PSObject.Properties.Name -contains $p.id)
    if ($have) { Write-OK $p.id; Add-Check "plugin" $p.id "PASS" }
    else       { Write-Warn2 "$($p.id) not installed"; Add-Check "plugin" $p.id "WARN" "not installed" }
}

# ── Skills / agents ───────────────────────────────────────────────────────────
Write-Step "Skills and agents"
$srcSkills  = @(Get-ChildItem -Path (Join-Path $RepoRoot "skills") -Directory -ErrorAction SilentlyContinue)
$destSkills = @(Get-ChildItem -Path (Join-Path $ClaudeHome "skills") -Directory -ErrorAction SilentlyContinue)

# Only skills in a selected bucket are expected on disk. A held-back skill is a
# deliberate choice, not a fault -- flagging it would train you to ignore doctor.
$sbCat = Read-JsonFile (Join-Path $RepoRoot "skills\_buckets.json")
$sbSel = if ($EnvMap.ContainsKey("CLAUDE_SKILL_BUCKETS")) { $EnvMap["CLAUDE_SKILL_BUCKETS"] -split "," }
         elseif ($sbCat) { $sbCat._defaultSkillBuckets }
         else { @("core", "data", "powerbi") }
$sbSel = @($sbSel | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })

$expected = @($srcSkills | Where-Object {
    $b = if ($sbCat -and $sbCat.skills.PSObject.Properties.Name -contains $_.Name) { $sbCat.skills.($_.Name) } else { "core" }
    ($sbSel -contains "all") -or ($sbSel -contains $b)
})
$held    = $srcSkills.Count - $expected.Count
$missing = @($expected.Name | Where-Object { $destSkills.Name -notcontains $_ })

if ($missing.Count -eq 0) {
    Write-OK "$($expected.Count) skills installed  (buckets: $($sbSel -join ', '))"
    if ($held -gt 0) { Write-Info "$held held back by bucket selection -- expected" }
    Add-Check "skills" "sync" "PASS" "$($expected.Count) of $($srcSkills.Count)"
} else {
    Write-Warn2 "$($missing.Count) selected skills not installed: $($missing -join ', ')"
    Add-Check "skills" "sync" "WARN" "$($missing.Count) missing"
}

# Descriptions are the permanent context cost -- bodies only load on trigger.
$descChars = 0
foreach ($d in $destSkills) {
    $sk = Join-Path $d.FullName "SKILL.md"
    if (-not (Test-Path $sk)) { continue }
    $inFm = $false; $inDesc = $false; $buf = @()
    foreach ($line in Get-Content -Path $sk -Encoding UTF8) {
        if ($line.Trim() -eq "---") { if ($inFm) { break } else { $inFm = $true; continue } }
        if (-not $inFm) { continue }
        if ($line -match '^[A-Za-z_][A-Za-z0-9_-]*:') {
            if ($line -match '^description:\s*(.*)$') { $inDesc = $true; $buf += $Matches[1] }
            elseif ($inDesc) { break }
        } elseif ($inDesc) { $buf += $line.Trim() }
    }
    $descChars += ($buf -join " ").Trim('"', "'").Length
}
$descTokens = [int]($descChars / 4)
if ($descTokens -le 1500) { Write-OK "skill descriptions ~$descTokens tokens always in context"; Add-Check "skills" "context-cost" "PASS" "~$descTokens tok" }
else { Write-Warn2 "skill descriptions ~$descTokens tokens always in context -- consider trimming or narrowing buckets"; Add-Check "skills" "context-cost" "WARN" "~$descTokens tok" }

# A SKILL.md without frontmatter never triggers.
$bad = @()
foreach ($d in $destSkills) {
    $sk = Join-Path $d.FullName "SKILL.md"
    if (-not (Test-Path $sk)) { $bad += "$($d.Name) (no SKILL.md)"; continue }
    $head = (Get-Content -Path $sk -TotalCount 5 -Encoding UTF8) -join "`n"
    if ($head -notmatch '(?m)^name:\s*\S') { $bad += "$($d.Name) (no name:)" }
    elseif ($head -notmatch '(?m)^description:\s*\S') { $bad += "$($d.Name) (no description:)" }
}
if ($bad.Count -eq 0) { Write-OK "all skill frontmatter valid"; Add-Check "skills" "frontmatter" "PASS" }
else { Write-Warn2 "$($bad.Count) skills with bad frontmatter: $($bad -join ', ')"; Add-Check "skills" "frontmatter" "WARN" "$($bad.Count) bad" }

# Mojibake check -- the defect that shipped in the Alfred skill set.
$moji = @()
foreach ($f in Get-ChildItem -Path (Join-Path $ClaudeHome "skills") -Filter "*.md" -Recurse -ErrorAction SilentlyContinue) {
    $t = Get-Content -Raw -Path $f.FullName -Encoding UTF8
    if ($t -match 'â€|â†|â”') { $moji += $f.Name }
}
if ($moji.Count -eq 0) { Write-OK "no mojibake in skill text"; Add-Check "skills" "encoding" "PASS" }
else { Write-Warn2 "$($moji.Count) files with mojibake"; Add-Check "skills" "encoding" "WARN" "$($moji.Count) files" }

$srcAgents  = @(Get-ChildItem -Path (Join-Path $RepoRoot "agents") -Filter "*.md" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "README.md" })
$destAgents = @(Get-ChildItem -Path (Join-Path $ClaudeHome "agents") -Filter "*.md" -File -ErrorAction SilentlyContinue)
if ($destAgents.Count -ge $srcAgents.Count) { Write-OK "$($destAgents.Count) agents installed"; Add-Check "agents" "sync" "PASS" "$($destAgents.Count)" }
else { Write-Warn2 "$($srcAgents.Count - $destAgents.Count) agents missing"; Add-Check "agents" "sync" "WARN" "incomplete" }

# ── Settings and hooks ────────────────────────────────────────────────────────
Write-Step "Settings and hooks"
$settings = Read-JsonFile (Join-Path $ClaudeHome "settings.json")
if (-not $settings) { Write-Fail "settings.json missing or unparseable"; Add-Check "settings" "file" "FAIL" }
else {
    Write-OK "settings.json parses"
    Add-Check "settings" "file" "PASS"
    $deadHooks = @()
    if ($settings.PSObject.Properties.Name -contains "hooks") {
        foreach ($evt in $settings.hooks.PSObject.Properties.Name) {
            foreach ($grp in $settings.hooks.$evt) {
                foreach ($h in $grp.hooks) {
                    if ($h.command -match '"([^"]+\.py)"') {
                        $script = $Matches[1]
                        if (-not (Test-Path $script)) { $deadHooks += "$evt -> $(Split-Path -Leaf $script)" }
                    }
                }
            }
        }
    }
    if ($deadHooks.Count -eq 0) { Write-OK "all hook scripts resolve"; Add-Check "settings" "hooks" "PASS" }
    else {
        Write-Fail "$($deadHooks.Count) hook(s) point at missing files: $($deadHooks -join ', ')"
        Add-Check "settings" "hooks" "FAIL" ($deadHooks -join ", ")
    }
    if ($settings.PSObject.Properties.Name -contains "statusLine") {
        if ($settings.statusLine.command -match '-File "([^"]+)"' -and -not (Test-Path $Matches[1])) {
            Write-Fail "statusLine points at a missing script -- this errors on every prompt"
            Add-Check "settings" "statusline" "FAIL" "dead path"
        } else { Write-OK "statusLine resolves"; Add-Check "settings" "statusline" "PASS" }
    }
}

$memPath = Join-Path $ClaudeHome "CLAUDE.md"
if (Test-Path $memPath) { Write-OK "CLAUDE.md present"; Add-Check "memory" "CLAUDE.md" "PASS" }
else { Write-Warn2 "CLAUDE.md missing"; Add-Check "memory" "CLAUDE.md" "WARN" "missing" }

# ── Stale state ───────────────────────────────────────────────────────────────
Write-Step "Stale state"
$legacyRoot = Join-Path $env:USERPROFILE ".agents\skills"
$legacy = @(Get-ChildItem -Path $legacyRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "alfred-*" -or $_.Name -like "maersk-ai-*" })
if ($legacy.Count -eq 0) { Write-OK "no legacy prefixed skill dirs"; Add-Check "stale" "legacy-skills" "PASS" }
else { Write-Warn2 "$($legacy.Count) legacy dirs in ~/.agents/skills"; Add-Check "stale" "legacy-skills" "WARN" "$($legacy.Count) dirs" }

# Anything under Temp is one cleanup sweep away from breaking.
$tempRefs = @()
$claudeJson = Read-JsonFile (Join-Path $env:USERPROFILE ".claude.json")
if ($claudeJson -and $claudeJson.PSObject.Properties.Name -contains "mcpServers") {
    foreach ($n in $claudeJson.mcpServers.PSObject.Properties.Name) {
        $blob = $claudeJson.mcpServers.$n | ConvertTo-Json -Depth 8
        if ($blob -match '\\\\Temp\\\\|/Temp/') { $tempRefs += $n }
    }
}
if ($tempRefs.Count -eq 0) { Write-OK "no MCP paths under Temp"; Add-Check "stale" "temp-paths" "PASS" }
else {
    Write-Fail "MCP server(s) pointing into Temp: $($tempRefs -join ', ')"
    Write-Info "Temp is swept periodically -- re-run Claude-Provision.ps1 to repoint."
    Add-Check "stale" "temp-paths" "FAIL" ($tempRefs -join ", ")
}

# ── Report ────────────────────────────────────────────────────────────────────
Write-Banner "Report"
# Out-Host, not the default pipeline: Format-Table is deferred and otherwise
# renders after the summary line below it.
$Results | Format-Table -AutoSize -Property @(
    @{ L = "AREA";   E = { $_.Area } },
    @{ L = "CHECK";  E = { $_.Name } },
    @{ L = "STATE";  E = { $_.State } },
    @{ L = "DETAIL"; E = { $_.Detail } }
) | Out-Host
$pass = @($Results | Where-Object State -eq "PASS").Count
$warn = @($Results | Where-Object State -eq "WARN").Count
$fail = @($Results | Where-Object State -eq "FAIL").Count
Write-Host "  pass $pass   warn $warn   fail $fail" -ForegroundColor $(if ($fail) { "Red" } elseif ($warn) { "Yellow" } else { "Green" })
Write-Host ""

if ($Fix -and ($fail -gt 0 -or $warn -gt 0)) {
    Write-Host "  -Fix: re-running provisioning..." -ForegroundColor Cyan
    & (Join-Path $RepoRoot "Claude-Provision.ps1")
    exit $LASTEXITCODE
}
if ($fail -gt 0) { Write-Host "  Repair with: .\Claude-Doctor.ps1 -Fix" -ForegroundColor Yellow; Write-Host ""; exit 1 }
exit 0
