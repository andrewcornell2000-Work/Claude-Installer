# Claude-Installer

Provisions a Windows machine for **Claude Code** — MCP servers, plugins, skills, agents, hooks, settings and global memory — from one repo, in one command.

Claude Code only. No Cursor, no Codex, no Claude Desktop. That is the entire point: its predecessor ([Alfred](https://github.com/andrewcornell2000-Work/Alfred)) drove three harnesses from one catalog, and the shared catalog is where the drift came from.

---

## New machine, from nothing

This repo is **private**, so the clone needs auth. Paste this into PowerShell:

```powershell
winget install --id GitHub.cli --silent --accept-package-agreements --accept-source-agreements; gh auth login; gh repo clone andrewcornell2000-Work/Claude-Installer "$env:USERPROFILE\Claude-Installer"; & "$env:USERPROFILE\Claude-Installer\bootstrap.ps1"
```

`gh auth login` is interactive — pick GitHub.com → HTTPS → login with a browser.

Everything after that is unattended: `bootstrap.ps1` installs Git if missing, then runs the full installer.

## Already cloned

Double-click `Install-Claude.bat`, or:

```powershell
.\Claude-Install.ps1
```

## Updating later

```powershell
.\Claude-Sync.ps1
```

---

## Commands

| Script | Does |
|---|---|
| `Claude-Install.ps1` | Prerequisites (Git, Node, Python, uv, Claude CLI, pip packages) then provision |
| `Claude-Provision.ps1` | MCPs, plugins, skills, agents, hooks, settings, memory. Idempotent |
| `Claude-Doctor.ps1` | Read-only verification. `-Fix` re-provisions what is broken |
| `Claude-Sync.ps1` | Pull, upgrade tooling and plugins, re-provision, verify |
| `Claude-Reset.ps1` | Undo. Archives rather than deletes. Requires an explicit mode |

Useful flags:

```powershell
.\Claude-Provision.ps1 -DryRun                  # show what would change
.\Claude-Provision.ps1 -Buckets core,data       # subset of MCP servers
.\Claude-Provision.ps1 -Only skills,agents      # one section
.\Claude-Reset.ps1 -LegacySkillsOnly            # clear superseded alfred-*/maersk-ai-* dirs
```

---

## What gets installed

**11 MCP servers**, bucket-gated. Anything missing a key or a runtime is skipped with a printed reason rather than registered broken.

| Bucket | Servers |
|---|---|
| `core` | github, context7, filesystem, graphify |
| `powerbi` | powerbi-modeling-mcp |
| `data` | excel, duckdb, markitdown |
| `web` | fetch, parallel-search |
| `webdev` | higgsfield |

`graphify` serves a prebuilt `graph.json` over MCP. It needs the `graphify-mcp` binary (`uv tool install -U "graphifyy[mcp]"` — the `[mcp]` extra is mandatory, without it the server starts, fails to import `mcp` and shows only as "Connection closed"; catalogued in `requirements/uv-tools.txt` and installed by `Claude-Install.ps1`) **and** a graph that already exists — resolved from `GRAPHIFY_GRAPH` in `.env`, else the newest `graph.json` under `%LOCALAPPDATA%\graphify-workspace`. Before the first `/graphify` build there is nothing to serve, so the server is skipped; re-run `Claude-Provision.ps1` once a graph exists. The skill works from the CLI either way — the MCP is the cheaper query path, not a prerequisite.

Note the workspace location. graphify defaults to `graphify-out/` relative to the working directory, which on a corpus that lives in OneDrive or SharePoint means the converted copy of every source document, the extraction cache and a multi-MB `graph.json` all sync back to the share. `config/CLAUDE.md` therefore pins graph output to `%LOCALAPPDATA%\graphify-workspace\<corpus-name>\` and the MCP resolver reads from there. That rule is memory text, not enforcement — nothing blocks a `graphify-out/` written into a synced folder today.

Default is all five buckets. Profiles in `claude.manifest.json`: `work` (default), `analyst` (no web/webdev), `minimal` (core only).

**60 skills in the repo, 43 installed by default** → `~/.claude/skills`

Skills are bucket-gated too, and for a different reason than MCPs: every installed skill's `description` line sits in context permanently, used or not. Bodies only load when a skill triggers.

| Bucket | Skills | ~tokens | Default | |
|---|---|---|---|---|
| `core` | 13 | 820 | yes | planning, handoff, github, graphify, ambition/parallelism reflexes |
| `data` | 11 | 644 | yes | Excel, analysis, reconciliation, labour cost, spreadsheet verification gates |
| `powerbi` | 10 | 503 | yes | model editing, Power Query, reports, dataflows |
| `webapp` | 9 | 555 | yes | building and polishing web apps |
| `design` | 9 | 503 | no | brand kits, mobile mockups, overlapping taste skills |
| `web` | 8 | 368 | no | Supabase, Vercel, browsing, trend research |

`webapp` is a curated slice of the design skills — component patterns, UI audit, accessibility, visual direction, reference-image generation — rather than all 17. The wider `design` bucket holds the ones with heavy overlap or a narrow use (mobile screens, logo systems, the legacy `design-taste-frontend-v1`).

Default set: **43 skills, ~2,522 tokens.** All 60 ship in the repo — install a held-back bucket without re-cloning:

```powershell
.\Claude-Provision.ps1 -Only skills -SkillBuckets all
```

Deselecting a bucket archives those skills to `~/.claude/backups` rather than leaving them to cost context.

**3 agents** → `~/.claude/agents`
**8 hooks** → wired into `~/.claude/settings.json`, including two guard rails on the shell tools:

- `hooks/edr-guard/` — `PreToolUse` on Bash and PowerShell. Denies the command shapes corporate EDR scores as ransomware (kill-then-delete in one call, recursive deletes under OneDrive or the profile content folders, multi-PID `Stop-Process`). Normalises backtick/caret escaping and decodes `-EncodedCommand` before matching. Suite: `python hooks/edr-guard/run_tests.py` (49 cases).
- `hooks/sync-guard/` — `PreToolUse` on Bash, PowerShell and Write. Denies creating an AI/tool byproduct (`graphify-out`, `node_modules`, `.venv`, `.agents`, `.cursor`, `HANDOFF*.md`, …) under a folder that names a sync provider (OneDrive, SharePoint, Dropbox, Google Drive, iCloud Drive) — checked against the command *and* the tool call's cwd, since the incident that motivated it was a relative path run from a synced working directory. Suite: `python hooks/sync-guard/run_tests.py` (21 cases).
**Plugins** → caveman, plus the official Anthropic marketplace registered

**Companion repos** — cloned alongside rather than vendored, listed in `config/repos.json`:

| Repo | Size | Used by |
|---|---|---|
| `design-inspo-library` | ~540 MB | `design-inspo` skill |

114 curated web design plates on a three-axis taxonomy. Kept out of this repo because it would multiply the installer's size by 25× for content Claude only reads the index of. Cloned on first provision, fast-forwarded after. Override the location with `CLAUDE_INSPO_DIR`.

---

## Configuration

Copy `.env.template` to `.env` and fill in what you need. `.env` is gitignored.

| Key | Needed for |
|---|---|
| `CLAUDE_USER_EMAIL` | Written into `~/.claude/CLAUDE.md` |
| `CLAUDE_FINANCE_DIR` | Scope of the `filesystem` MCP. Auto-detected if unset |
| `CLAUDE_BUCKETS` | Which MCP buckets to install |
| `GITHUB_PERSONAL_ACCESS_TOKEN` | `github` server |
| `FIRECRAWL_API_KEY` | `firecrawl` server |
| `FAL_KEY` | `fal-ai` server |
| `SUPABASE_PROJECT_REF` | `supabase` server |
| `CONTEXT7_API_KEY`, `PARALLEL_API_KEY` | Optional — raise rate limits |

Claude auth is not a key here:

```bash
claude auth login
```

---

## Design notes

Things that broke before, and what this repo does instead.

**No version numbers in paths.** The Power BI MCP lives in a versioned VS Code extension dir, and the caveman statusline lives in a commit-sha-named cache dir. Both are resolved by globbing at provision time. A hardcoded version is a time bomb.

**Nothing under `%TEMP%`.** DuckDB's database goes in `<repo>\data`, not a session scratchpad. `Claude-Doctor.ps1` fails the run if any registered MCP path points into Temp.

**`settings.json` is merged, not overwritten**, and backed up to `~/.claude/backups` first. Your own keys survive a re-provision.

**Skills are deduped and encoding-repaired.** The source set had the same skill under three names (`alfred-*`, `maersk-ai-*`, bare) across two roots, and 23 files were mojibake-corrupted (`â€"` where an em dash belonged). Doctor checks for both.

**One Excel server.** The old catalog defined two with opposite access models (`excellm` for open workbooks, `ExcelMcp` for closed) and three skills documented tool names from a server that was not installed. Now: `@negokaz/excel-mcp-server`, with `excel-editing` documenting its actual seven tools.

**Skipped is not failed.** A server with no key prints why it was skipped and the run continues. Only genuine errors set a non-zero exit.

---

## Known gaps

- Windows only. The scripts are PowerShell and use winget.
- Some skills still mention Cursor or Codex in prose. Dead paths and wrong-harness instructions were fixed; incidental mentions were left alone.
- `claude plugin update --all` is assumed to exist. If your CLI predates it, `Claude-Sync.ps1` warns and continues.
