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

**15 MCP servers**, bucket-gated. Anything missing a key or a runtime is skipped with a printed reason rather than registered broken.

| Bucket | Servers |
|---|---|
| `core` | github, context7, filesystem |
| `powerbi` | powerbi-modeling-mcp |
| `data` | excel, duckdb, markitdown, longhand |
| `web` | playwright, fetch, parallel-search, firecrawl |
| `webdev` | magic, fal-ai, supabase, vercel |

Default is all five buckets. Profiles in `claude.manifest.json`: `work` (default), `analyst` (no web/webdev), `minimal` (core only).

**52 skills in the repo, 27 installed by default** → `~/.claude/skills`

Skills are bucket-gated too, and for a different reason than MCPs: every installed skill's `description` line sits in context permanently, used or not. Bodies only load when a skill triggers.

| Bucket | Skills | ~tokens | Default |
|---|---|---|---|
| `core` | 10 | 375 | yes |
| `data` | 7 | 170 | yes |
| `powerbi` | 10 | 501 | yes |
| `design` | 17 | 793 | no |
| `web` | 8 | 542 | no |

Default set: **27 skills, ~1,046 tokens.** All 52 ship in the repo — install a held-back bucket without re-cloning:

```powershell
.\Claude-Provision.ps1 -Only skills -SkillBuckets all
```

Deselecting a bucket archives those skills to `~/.claude/backups` rather than leaving them to cost context.

**3 agents** → `~/.claude/agents`
**6 hooks** → wired into `~/.claude/settings.json`
**Plugins** → caveman, plus the official Anthropic marketplace registered

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
