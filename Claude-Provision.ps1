<#
.SYNOPSIS
    Provision Claude Code from this repo: MCP servers, plugins, skills, agents, hooks, settings, memory.

.DESCRIPTION
    Idempotent. Safe to re-run. Every skipped item prints why it was skipped.
    Only ~/.claude is touched -- no Cursor, no Codex, no Claude Desktop.

.PARAMETER Buckets
    Comma-separated MCP buckets, or "all". Overrides CLAUDE_BUCKETS in .env.
    Default: core,powerbi,data,web,webdev

.PARAMETER SkillBuckets
    Comma-separated skill buckets, or "all". Overrides CLAUDE_SKILL_BUCKETS in .env.
    Default: core,data,powerbi -- see skills/_buckets.json.
    Skills are gated separately from MCPs because their cost model differs: every
    installed skill's description sits in context permanently, whether used or not.

.PARAMETER Only
    Restrict the run to named sections: mcp, plugins, skills, agents, hooks, memory.

.PARAMETER DryRun
    Print what would change without writing anything or calling the claude CLI.

.EXAMPLE
    .\Claude-Provision.ps1
.EXAMPLE
    .\Claude-Provision.ps1 -Buckets core,data -DryRun
.EXAMPLE
    .\Claude-Provision.ps1 -Only skills,agents
#>
[CmdletBinding()]
param(
    [string[]]$Buckets,
    [string[]]$SkillBuckets,
    [ValidateSet("mcp", "plugins", "skills", "agents", "hooks", "memory", "repos")]
    [string[]]$Only,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Claude-Common.ps1")

$RepoRoot   = $PSScriptRoot
$ClaudeHome = Get-ClaudeHome
$EnvMap     = Read-DotEnv (Join-Path $RepoRoot ".env")
$Sections   = if ($Only) { $Only } else { @("mcp", "plugins", "skills", "agents", "hooks", "memory", "repos") }
function Use-Section([string]$n) { return $Sections -contains $n }

$Summary = [ordered]@{ added = @(); skipped = @(); failed = @() }
function Note-Added   ([string]$m) { $Summary.added   += $m }
function Note-Skipped ([string]$m) { $Summary.skipped += $m }
function Note-Failed  ([string]$m) { $Summary.failed  += $m }

Write-Banner "Claude-Installer -- Provision$(if ($DryRun) { '  (DRY RUN)' })"
Update-PathFromRegistry

if (-not (Test-Path (Join-Path $RepoRoot ".env"))) {
    Write-Warn2 "No .env found. Key-gated MCP servers will be skipped."
    Write-Info  "Copy .env.template to .env and fill in what you need, then re-run."
}
if (-not (Test-CommandExists "claude")) {
    Write-Fail "claude CLI not on PATH. Run Claude-Install.ps1 first."
    exit 3
}

# ── Path tokens ───────────────────────────────────────────────────────────────
$DataDir = Join-Path $RepoRoot "data"
if (-not $DryRun -and -not (Test-Path $DataDir)) { New-Item -ItemType Directory -Force -Path $DataDir | Out-Null }

$Tokens = @{
    repoRoot           = $RepoRoot
    claudeHome         = $ClaudeHome
    dataDir            = $DataDir
    financeDir         = Resolve-FinanceDir -EnvMap $EnvMap
    powerBiMcp         = Resolve-PowerBiMcp
    cavemanStatusline  = Resolve-CavemanStatusline
}

# ── Buckets ───────────────────────────────────────────────────────────────────
$catalog = Read-JsonFile (Join-Path $RepoRoot "config\mcp.json")
if (-not $catalog) { Write-Fail "config/mcp.json missing or unparseable."; exit 4 }

$selected = $null
if ($Buckets)                                        { $selected = $Buckets }
elseif ($EnvMap.ContainsKey("CLAUDE_BUCKETS"))       { $selected = $EnvMap["CLAUDE_BUCKETS"] -split "," }
else                                                 { $selected = $catalog._defaultBuckets }
$selected = @($selected | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
$allBuckets = ($selected -contains "all")
if (-not ($selected -contains "core")) { $selected += "core" }   # core is never optional

# ══════════════════════════════════════════════════════════════════════════════
# MCP servers
# ══════════════════════════════════════════════════════════════════════════════
if (Use-Section "mcp") {
    Write-Step "MCP servers  (buckets: $(if ($allBuckets) { 'all' } else { $selected -join ', ' }))"

    foreach ($name in $catalog.mcpServers.PSObject.Properties.Name) {
        $s      = $catalog.mcpServers.$name
        $bucket = if ($s.PSObject.Properties.Name -contains "_bucket") { $s._bucket } else { "core" }

        if (-not $allBuckets -and $selected -notcontains $bucket) {
            Write-Skip "$name -- bucket '$bucket' not selected"; Note-Skipped "$name (bucket)"; continue
        }

        # External command must exist (uvx, docker, longhand, ...)
        if ($s.PSObject.Properties.Name -contains "_requiresCommand") {
            if (-not (Test-CommandExists $s._requiresCommand)) {
                Write-Skip "$name -- '$($s._requiresCommand)' not on PATH"; Note-Skipped "$name (no $($s._requiresCommand))"; continue
            }
        }

        # Path token must have resolved (powerBiMcp)
        if ($s.PSObject.Properties.Name -contains "_requiresToken") {
            if (-not $Tokens[$s._requiresToken]) {
                Write-Skip "$name -- $($s._requiresToken) not found on this machine"; Note-Skipped "$name (no $($s._requiresToken))"; continue
            }
        }

        # Required secrets
        $missing = @()
        $envArgs = @()
        $requires = @()
        if ($s.PSObject.Properties.Name -contains "_requires") { $requires = @($s._requires) }

        if ($s.PSObject.Properties.Name -contains "env") {
            foreach ($k in $s.env.PSObject.Properties.Name) {
                $raw = [string]$s.env.$k
                $val = $raw
                if ($raw -match '^\$\{env:(.+)\}$') {
                    $varName = $Matches[1]
                    $aliases = @()
                    if ($s.PSObject.Properties.Name -contains "_aliases" -and
                        $s._aliases.PSObject.Properties.Name -contains $varName) { $aliases = @($s._aliases.$varName) }
                    $val = Resolve-Secret -Name $varName -EnvMap $EnvMap -Aliases $aliases
                    if (-not $val -and $s.PSObject.Properties.Name -contains "_envDefaults" -and
                        $s._envDefaults.PSObject.Properties.Name -contains $k) { $val = [string]$s._envDefaults.$k }
                }
                if ($val) { $envArgs += @("--env", "$k=$val") }
                elseif ($requires -contains $k) { $missing += $k }
            }
        }
        foreach ($r in $requires) {
            if (-not (Resolve-Secret -Name $r -EnvMap $EnvMap) -and $missing -notcontains $r) { $missing += $r }
        }
        if ($missing.Count -gt 0) {
            Write-Skip "$name -- missing $($missing -join ', ') in .env"; Note-Skipped "$name (no key)"; continue
        }

        # Build the claude mcp add invocation
        $isHttp = ($s.PSObject.Properties.Name -contains "url")
        if ($isHttp) {
            $url = Expand-PathTokens -Value ([string]$s.url) -Tokens $Tokens
            foreach ($r in $requires) {
                $v = Resolve-Secret -Name $r -EnvMap $EnvMap
                if ($v) { $url = $url.Replace('${env:' + $r + '}', $v) }
            }
            if (Test-HasUnresolvedToken $url) {
                Write-Skip "$name -- unresolved token in url"; Note-Skipped "$name (token)"; continue
            }
            $addArgs = @("mcp", "add", "--transport", "http", "--scope", "user", $name, $url)
        }
        else {
            $cmd = Expand-PathTokens -Value ([string]$s.command) -Tokens $Tokens
            if (Test-HasUnresolvedToken $cmd) {
                Write-Skip "$name -- unresolved token in command"; Note-Skipped "$name (token)"; continue
            }
            $sargs = @()
            if ($s.PSObject.Properties.Name -contains "args") {
                foreach ($a in $s.args) {
                    $ex = Expand-PathTokens -Value ([string]$a) -Tokens $Tokens
                    if (Test-HasUnresolvedToken $ex) { $ex = $null }
                    if ($null -ne $ex) { $sargs += $ex }
                }
            }
            $addArgs = @("mcp", "add", "--scope", "user") + $envArgs + @($name, "--") + @($cmd) + $sargs
        }

        if ($DryRun) { Write-OK "$name -- would register"; Write-Info "claude $(Format-RedactedCommand -Args $addArgs)"; Note-Added $name; continue }

        # Remove-then-add keeps this idempotent across catalog edits.
        & claude mcp remove $name --scope user 2>&1 | Out-Null
        $out = & claude @addArgs 2>&1
        if ($LASTEXITCODE -eq 0) { Write-OK "$name"; Note-Added $name }
        else {
            Write-Fail "$name -- claude mcp add exited $LASTEXITCODE"
            Write-Info (($out | Select-Object -First 2) -join " ")
            Note-Failed $name
        }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# Plugins
# ══════════════════════════════════════════════════════════════════════════════
if (Use-Section "plugins") {
    Write-Step "Plugins and marketplaces"
    $pcat = Read-JsonFile (Join-Path $RepoRoot "config\plugins.json")
    if (-not $pcat) { Write-Warn2 "config/plugins.json missing -- skipping plugins." }
    else {
        foreach ($m in $pcat.marketplaces) {
            if ($DryRun) { Write-OK "marketplace $($m.name) -- would add"; continue }
            & claude plugin marketplace add $m.source 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-OK "marketplace $($m.name)" }
            else { Write-Warn2 "marketplace $($m.name) -- add exited $LASTEXITCODE (may already exist)" }
        }
        foreach ($p in $pcat.plugins) {
            if ($DryRun) { Write-OK "plugin $($p.id) -- would install"; Note-Added "plugin $($p.id)"; continue }
            & claude plugin install $p.id 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-OK "plugin $($p.id)"; Note-Added "plugin $($p.id)" }
            else {
                Write-Warn2 "plugin $($p.id) -- install exited $LASTEXITCODE"
                Write-Info  "manual: claude plugin install $($p.id)"
                Note-Failed "plugin $($p.id)"
            }
        }
        # Statusline path depends on the plugin cache existing, so re-resolve after install.
        $Tokens.cavemanStatusline = Resolve-CavemanStatusline
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# Skills
# ══════════════════════════════════════════════════════════════════════════════
if (Use-Section "skills") {
    $src  = Join-Path $RepoRoot "skills"
    $dest = Join-Path $ClaudeHome "skills"
    $sbCat = Read-JsonFile (Join-Path $src "_buckets.json")

    $sbSel = $null
    if ($SkillBuckets)                                    { $sbSel = $SkillBuckets }
    elseif ($EnvMap.ContainsKey("CLAUDE_SKILL_BUCKETS"))  { $sbSel = $EnvMap["CLAUDE_SKILL_BUCKETS"] -split "," }
    elseif ($sbCat)                                       { $sbSel = $sbCat._defaultSkillBuckets }
    else                                                  { $sbSel = @("core", "data", "powerbi") }
    $sbSel = @($sbSel | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
    $allSkills = ($sbSel -contains "all")

    Write-Step "Skills -> ~/.claude/skills  (buckets: $(if ($allSkills) { 'all' } else { $sbSel -join ', ' }))"
    if (-not (Test-Path $src)) { Write-Warn2 "skills/ missing in repo." }
    else {
        if (-not $DryRun -and -not (Test-Path $dest)) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }
        $n = 0; $held = 0
        foreach ($d in Get-ChildItem -Path $src -Directory) {
            $bucket = "core"
            if ($sbCat -and $sbCat.skills.PSObject.Properties.Name -contains $d.Name) { $bucket = $sbCat.skills.($d.Name) }
            if (-not $allSkills -and $sbSel -notcontains $bucket) { $held++; continue }
            $target = Join-Path $dest $d.Name
            if ($DryRun) { $n++; continue }
            if (Test-Path $target) { Remove-Item -Path $target -Recurse -Force }
            Copy-Item -Path $d.FullName -Destination $target -Recurse -Force
            $n++
        }
        Write-OK "$n skills synced$(if ($DryRun) { ' (would be)' })"
        Note-Added "$n skills"
        if ($held -gt 0) {
            Write-Skip "$held skills held back -- buckets not selected"
            Write-Info  "install them with: .\Claude-Provision.ps1 -Only skills -SkillBuckets all"
        }

        # A held-back skill left over from a previous run keeps costing context.
        if (-not $DryRun -and $sbCat) {
            $stale = @()
            foreach ($d in Get-ChildItem -Path $dest -Directory -ErrorAction SilentlyContinue) {
                if ($sbCat.skills.PSObject.Properties.Name -notcontains $d.Name) { continue }
                $b = $sbCat.skills.($d.Name)
                if (-not $allSkills -and $sbSel -notcontains $b) { $stale += $d }
            }
            if ($stale.Count -gt 0) {
                $arch = Join-Path $ClaudeHome "backups\skills-deselected-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                New-Item -ItemType Directory -Force -Path $arch | Out-Null
                foreach ($d in $stale) { Move-Item -Path $d.FullName -Destination (Join-Path $arch $d.Name) -Force }
                Write-OK "$($stale.Count) deselected skills archived to $arch"
            }
        }

        # Legacy prefixed copies in the old ~/.agents root shadow the canonical set.
        $legacyRoot = Join-Path $env:USERPROFILE ".agents\skills"
        if (Test-Path $legacyRoot) {
            $legacy = @(Get-ChildItem -Path $legacyRoot -Directory -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -like "alfred-*" -or $_.Name -like "maersk-ai-*" })
            if ($legacy.Count -gt 0) {
                Write-Warn2 "$($legacy.Count) legacy prefixed skill dirs still in ~/.agents/skills"
                Write-Info  "These are superseded by the canonical set. Remove with: .\Claude-Reset.ps1 -LegacySkillsOnly"
            }
        }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# Agents
# ══════════════════════════════════════════════════════════════════════════════
if (Use-Section "agents") {
    Write-Step "Agents -> ~/.claude/agents"
    $src  = Join-Path $RepoRoot "agents"
    $dest = Join-Path $ClaudeHome "agents"
    if (-not (Test-Path $src)) { Write-Warn2 "agents/ missing in repo." }
    else {
        if (-not $DryRun -and -not (Test-Path $dest)) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }
        $n = 0
        foreach ($f in Get-ChildItem -Path $src -Filter "*.md" -File) {
            if ($f.Name -eq "README.md") { continue }
            if (-not $DryRun) { Copy-Item -Path $f.FullName -Destination (Join-Path $dest $f.Name) -Force }
            $n++
        }
        Write-OK "$n agents synced$(if ($DryRun) { ' (would be)' })"
        Note-Added "$n agents"
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# Hooks + settings.json  (merge, never clobber)
# ══════════════════════════════════════════════════════════════════════════════
if (Use-Section "hooks") {
    Write-Step "Hooks and settings.json"
    $tplPath = Join-Path $RepoRoot "config\settings.template.json"
    $tplRaw  = if (Test-Path $tplPath) { Get-Content -Raw -Path $tplPath -Encoding UTF8 } else { $null }
    if (-not $tplRaw) { Write-Warn2 "config/settings.template.json missing -- skipping." }
    else {
        $tplRaw = Expand-PathTokens -Value $tplRaw -Tokens $Tokens -JsonEscape
        $tpl    = $tplRaw | ConvertFrom-Json

        # Drop the statusline entirely if caveman is not installed -- a broken
        # statusline command prints an error on every single prompt.
        if (-not $Tokens.cavemanStatusline -and $tpl.PSObject.Properties.Name -contains "statusLine") {
            $tpl.PSObject.Properties.Remove("statusLine")
            Write-Skip "statusLine -- caveman plugin not installed"
        }

        $settingsPath = Join-Path $ClaudeHome "settings.json"
        $existing     = Read-JsonFile $settingsPath
        if (-not $existing) { $existing = [PSCustomObject]@{} }

        if (-not $DryRun) {
            $bk = Backup-File $settingsPath
            if ($bk) { Write-Info "backup: $bk" }
        }

        foreach ($k in $tpl.PSObject.Properties.Name) {
            if ($k -eq '$comment') { continue }
            if ($existing.PSObject.Properties.Name -contains $k) {
                $existing.PSObject.Properties.Remove($k)
            }
            $existing | Add-Member -NotePropertyName $k -NotePropertyValue $tpl.$k -Force
        }

        if ($DryRun) { Write-OK "settings.json -- would merge $(($tpl.PSObject.Properties.Name | Where-Object { $_ -ne '$comment' }) -join ', ')" }
        else {
            Write-JsonFile -Path $settingsPath -Object $existing
            Write-OK "settings.json merged"
            Note-Added "settings.json"
        }

        $missingHooks = @()
        foreach ($h in Get-ChildItem -Path (Join-Path $RepoRoot "hooks") -Filter "*.py" -File -ErrorAction SilentlyContinue) {
            if (-not (Test-Path $h.FullName)) { $missingHooks += $h.Name }
        }
        if ($missingHooks.Count -eq 0) { Write-OK "hook scripts present in repo (run from $RepoRoot\hooks)" }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# Companion repos
# ══════════════════════════════════════════════════════════════════════════════
if (Use-Section "repos") {
    Write-Step "Companion repos"
    $rcat = Read-JsonFile (Join-Path $RepoRoot "config\repos.json")
    if (-not $rcat) { Write-Skip "config/repos.json missing" }
    else {
        foreach ($r in $rcat.repos) {
            $dir = [string]$r.dir
            if ($dir -match '^\$\{env:(.+)\}$') {
                $resolved = Resolve-Secret -Name $Matches[1] -EnvMap $EnvMap
                $dir = if ($resolved) { $resolved } else { [string]$r.default }
            }
            $dir = [Environment]::ExpandEnvironmentVariables($dir)

            if (Test-Path (Join-Path $dir ".git")) {
                if ($DryRun) { Write-OK "$($r.name) -- would pull"; continue }
                & git -C $dir pull --ff-only 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-OK "$($r.name) up to date  ($dir)" }
                else { Write-Warn2 "$($r.name) -- pull exited $LASTEXITCODE; local tree left as-is" }
                continue
            }
            if (Test-Path $dir) {
                Write-Warn2 "$($r.name) -- $dir exists but is not a git checkout; skipping"
                Note-Skipped "$($r.name) (dir occupied)"
                continue
            }
            if ($DryRun) { Write-OK "$($r.name) -- would clone to $dir  (~$($r.sizeMB) MB)"; Note-Added $r.name; continue }

            # gh carries auth, so private repos clone without a credential helper.
            Write-Info "cloning $($r.slug) (~$($r.sizeMB) MB) -- this takes a minute"
            if (Test-CommandExists "gh") { & gh repo clone $r.slug $dir 2>&1 | Out-Null }
            else { & git clone "https://github.com/$($r.slug).git" $dir 2>&1 | Out-Null }

            if (Test-Path (Join-Path $dir ".git")) { Write-OK "$($r.name) cloned to $dir"; Note-Added $r.name }
            else {
                Write-Warn2 "$($r.name) -- clone failed$(if ($r.private) { ' (private repo: gh auth login)' })"
                Write-Info  "used by: $($r.usedBy)"
                Note-Skipped "$($r.name) (clone failed)"
            }
        }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# Memory  (~/.claude/CLAUDE.md)
# ══════════════════════════════════════════════════════════════════════════════
if (Use-Section "memory") {
    Write-Step "Global memory -> ~/.claude/CLAUDE.md"
    $src = Join-Path $RepoRoot "config\CLAUDE.md"
    if (-not (Test-Path $src)) { Write-Warn2 "config/CLAUDE.md missing." }
    else {
        $text  = Get-Content -Raw -Path $src -Encoding UTF8
        $email = Resolve-Secret -Name "CLAUDE_USER_EMAIL" -EnvMap $EnvMap
        if ($email) { $text = $text.Replace('${env:CLAUDE_USER_EMAIL}', $email) }
        else {
            $text = ($text -split "`n" | Where-Object { $_ -notmatch '\$\{env:CLAUDE_USER_EMAIL\}' }) -join "`n"
            Write-Skip "user email -- CLAUDE_USER_EMAIL not set in .env"
        }
        $target = Join-Path $ClaudeHome "CLAUDE.md"
        if ($DryRun) { Write-OK "CLAUDE.md -- would write" }
        else {
            $bk = Backup-File $target
            if ($bk) { Write-Info "backup: $bk" }
            Write-TextNoBom -Path $target -Text $text
            Write-OK "CLAUDE.md written"
            Note-Added "CLAUDE.md"
        }
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Banner "Summary"
Write-Host "  added:   $($Summary.added.Count)" -ForegroundColor Green
Write-Host "  skipped: $($Summary.skipped.Count)" -ForegroundColor DarkGray
if ($Summary.skipped.Count) { Write-Host "           $($Summary.skipped -join ', ')" -ForegroundColor DarkGray }
if ($Summary.failed.Count) {
    Write-Host "  failed:  $($Summary.failed.Count)" -ForegroundColor Red
    Write-Host "           $($Summary.failed -join ', ')" -ForegroundColor Red
}
Write-Host ""
Write-Host "  Verify with: .\Claude-Doctor.ps1" -ForegroundColor Cyan
Write-Host "  Restart Claude Code for MCP changes to take effect." -ForegroundColor Yellow
Write-Host ""

if ($Summary.failed.Count -gt 0) { exit 1 }
exit 0
