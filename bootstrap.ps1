# Claude-Installer bootstrap.
#
# One-liner for a brand new machine -- installs Git if needed, clones the repo,
# and runs the installer:
#
#   irm https://raw.githubusercontent.com/andrewcornell2000-Work/Claude-Installer/main/bootstrap.ps1 | iex
#
# Optional overrides, set before piping to iex:
#   $env:CLAUDE_INSTALLER_DIR     = "D:\tools\Claude-Installer"   # clone location
#   $env:CLAUDE_INSTALLER_BRANCH  = "main"
#   $env:CLAUDE_INSTALLER_BUCKETS = "core,data"

$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/andrewcornell2000-Work/Claude-Installer.git"
$Branch  = if ($env:CLAUDE_INSTALLER_BRANCH) { $env:CLAUDE_INSTALLER_BRANCH } else { "main" }
$Target  = if ($env:CLAUDE_INSTALLER_DIR)    { $env:CLAUDE_INSTALLER_DIR }
           else { Join-Path $env:USERPROFILE "Claude-Installer" }

function Say  ([string]$m) { Write-Host "  $m" -ForegroundColor Cyan }
function Good ([string]$m) { Write-Host "  [ OK ]  $m" -ForegroundColor Green }
function Bad  ([string]$m) { Write-Host "  [FAIL]  $m" -ForegroundColor Red }

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
    & winget install --id Git.Git --silent --accept-package-agreements --accept-source-agreements | Out-Null
    $env:PATH = "$env:ProgramFiles\Git\cmd;$env:PATH"
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Bad "Git still not on PATH. Open a NEW terminal and re-run this bootstrap."
        exit 3
    }
}
Good "git $((& git --version) -replace 'git version ', '')"

# ── Clone or update ───────────────────────────────────────────────────────────
if (Test-Path (Join-Path $Target ".git")) {
    Say "Existing checkout at $Target -- pulling..."
    & git -C $Target pull --ff-only 2>&1 | Out-Null
    Good "updated"
} else {
    if (Test-Path $Target) {
        Bad "$Target exists but is not a git checkout. Move it aside or set `$env:CLAUDE_INSTALLER_DIR."
        exit 4
    }
    Say "Cloning into $Target ..."
    & git clone --branch $Branch --depth 1 $RepoUrl $Target 2>&1 | Out-Null
    if (-not (Test-Path (Join-Path $Target ".git"))) { Bad "clone failed"; exit 4 }
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
