# Claude-Installer bootstrap.
#
# This repo is PRIVATE, so an unauthenticated `irm ... | iex` cannot reach it.
# On a new machine, install the GitHub CLI, sign in, then run this file:
#
#   winget install --id GitHub.cli
#   gh auth login
#   gh repo clone andrewcornell2000-Work/Claude-Installer "$env:USERPROFILE\Claude-Installer"
#   & "$env:USERPROFILE\Claude-Installer\bootstrap.ps1"
#
# Optional overrides:
#   $env:CLAUDE_INSTALLER_DIR     = "D:\tools\Claude-Installer"   # clone location
#   $env:CLAUDE_INSTALLER_BRANCH  = "main"
#   $env:CLAUDE_INSTALLER_BUCKETS = "core,data"

$ErrorActionPreference = "Stop"

$RepoSlug = "andrewcornell2000-Work/Claude-Installer"
$RepoUrl  = "https://github.com/$RepoSlug.git"
$Branch  = if ($env:CLAUDE_INSTALLER_BRANCH) { $env:CLAUDE_INSTALLER_BRANCH } else { "main" }
$Target  = if ($env:CLAUDE_INSTALLER_DIR)    { $env:CLAUDE_INSTALLER_DIR }
           else { Join-Path $env:USERPROFILE "Claude-Installer" }

function Say  ([string]$m) { Write-Host "  $m" -ForegroundColor Cyan }
function Good ([string]$m) { Write-Host "  [ OK ]  $m" -ForegroundColor Green }
function Bad  ([string]$m) { Write-Host "  [FAIL]  $m" -ForegroundColor Red }

# Windows PowerShell 5.1 wraps a native command's stderr lines as terminating
# NativeCommandErrors when merged via `2>&1`, regardless of exit code -- so
# under $ErrorActionPreference = "Stop" a benign stderr notice kills the whole
# bootstrap. Route native calls that touch stderr through here.
function Invoke-Native {
    param([Parameter(Mandatory)][scriptblock]$Command)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { & $Command }
    finally { $ErrorActionPreference = $prev }
}

Write-Host ""
Write-Host "  ==============================================================" -ForegroundColor Blue
Write-Host "    Claude-Installer -- bootstrap" -ForegroundColor White
Write-Host "  ==============================================================" -ForegroundColor Blue
Write-Host ""

# ── Git ───────────────────────────────────────────────────────────────────────
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Say "Git not found -- installing via winget..."
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Bad "winget unavailable. Install Git manually from https://git-scm.com/download/win then re-run."
        exit 3
    }
    Invoke-Native { & winget install --id Git.Git --silent --accept-package-agreements --accept-source-agreements } | Out-Null
    $env:PATH = "$env:ProgramFiles\Git\cmd;$env:PATH"
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Bad "Git still not on PATH. Open a NEW terminal and re-run this bootstrap."
        exit 3
    }
}
Good "git $((& git --version) -replace 'git version ', '')"

# ── Clone or update ───────────────────────────────────────────────────────────
# The repo is private. `gh` carries the auth; plain git needs a credential
# helper already configured, so prefer gh and fall back only if it is absent.
$gh = Get-Command gh -ErrorAction SilentlyContinue

if (Test-Path (Join-Path $Target ".git")) {
    Say "Existing checkout at $Target -- pulling..."
    Invoke-Native { & git -C $Target pull --ff-only 2>&1 } | Out-Null
    if ($LASTEXITCODE -ne 0) { Bad "pull failed -- check your GitHub auth (gh auth status)"; exit 4 }
    Good "updated"
} else {
    if (Test-Path $Target) {
        Bad "$Target exists but is not a git checkout. Move it aside or set `$env:CLAUDE_INSTALLER_DIR."
        exit 4
    }
    Say "Cloning into $Target ..."
    if ($gh) {
        Invoke-Native { & gh auth status 2>&1 } | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Bad "gh is installed but not signed in. Run:  gh auth login"
            exit 5
        }
        Invoke-Native { & gh repo clone $RepoSlug $Target -- --branch $Branch 2>&1 } | Out-Null
    } else {
        Say "gh not found -- trying plain git (needs a credential helper for a private repo)"
        Invoke-Native { & git clone --branch $Branch $RepoUrl $Target 2>&1 } | Out-Null
    }
    if (-not (Test-Path (Join-Path $Target ".git"))) {
        Bad "clone failed. This repo is private -- install the GitHub CLI and sign in:"
        Write-Host "     winget install --id GitHub.cli" -ForegroundColor Yellow
        Write-Host "     gh auth login" -ForegroundColor Yellow
        exit 4
    }
    Good "cloned"
}

# ── Run ───────────────────────────────────────────────────────────────────────
Write-Host ""
Say "Running installer..."
Write-Host ""

$installArgs = @{}
if ($env:CLAUDE_INSTALLER_BUCKETS) { $installArgs["Buckets"] = $env:CLAUDE_INSTALLER_BUCKETS -split "," }

& (Join-Path $Target "Claude-Install.ps1") @installArgs
$code = $LASTEXITCODE

Write-Host ""
Write-Host "  Repo: $Target" -ForegroundColor Cyan
if ($code -ne 0) {
    Write-Host "  Installer exited $code -- read the output above, fix, then run:" -ForegroundColor Yellow
    Write-Host "    cd `"$Target`"; .\Claude-Install.ps1" -ForegroundColor Yellow
}
Write-Host ""
exit $code
