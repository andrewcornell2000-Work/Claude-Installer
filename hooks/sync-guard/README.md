# sync-guard

`PreToolUse` hook on `Bash | PowerShell | Write`. Denies creating or writing a named
AI/tool byproduct path (`graphify-out`, `node_modules`, `__pycache__`, `.venv`,
`.agents`, `.cursor`, `.alfred`, `ai-workspace`, or a `HANDOFF*.md` / `AGENTS.md`
file) under a folder whose path names a known sync provider — OneDrive, SharePoint,
Dropbox, Google Drive, iCloud Drive.

## Why

On 2026-08-17 a `graphify-out\` directory was found sitting at the root of the
"OneDrive - Maersk Group" folder: 293 files, ~430 MB — converted copies of every
source document in the corpus plus the extraction cache. OneDrive propagates
everything under that root to the shared SharePoint site, so every other user with
access downloads it on their next sync. Nothing errored — the graphify skill's
default output path is relative to the working directory, and the working
directory that day was the OneDrive root.

The rule this enforces ("graph output stays on local disk", see the project
`CLAUDE.md` at the OneDrive root and the graphify section of `config/CLAUDE.md`
here) already existed as written memory before that leak happened. It didn't stop
it — an agent session doesn't reliably re-derive "am I currently inside a synced
folder" from prose on every tool call. This hook checks mechanically instead.

## How it decides

1. Is the command text, or the tool call's `cwd`, under a synced folder? (Checks
   for `onedrive`, `sharepoint`, `dropbox`, `google drive`, `icloud drive` — case
   insensitive, anywhere in the path.) If neither, allow — this is the case that
   catches the *relative*-path leak: `New-Item -Path graphify-out` never mentions
   OneDrive in the command text, only the session's cwd does.
2. Is a byproduct name present, or is this an `npm`/`pnpm`/`yarn install` (which
   creates `node_modules` as a side effect the command text never spells out)?
3. For a shell command: does it also look like a write — `mkdir`/`New-Item`,
   `Out-File`/`Set-Content`/`Add-Content`, `Copy-Item`/`cp`/`robocopy`,
   `git clone`, `pip`/`uv install`, Python's `.write_text()`/`.write_bytes()`/
   `open(..., 'w')`, or a bare `>` redirect? Read-only commands (`Get-ChildItem`,
   `cat`, `Get-Content`) are never blocked.

All three true → deny with a message naming the byproduct and pointing at where it
should go instead (`C:\Dev\` or `%LOCALAPPDATA%\graphify-workspace\`).

## A note on false positives

Heredoc and here-string bodies (`<<'EOF' ... EOF`, `@'...'@`) are blanked out before
matching -- they're literal data, not further shell syntax, so scanning them for
shell verbs is wrong. This was found the hard way: the first commit that added this
hook tripped over its own commit message, because `git commit -F - <<'EOF'` was
describing "npm install" and a bare `>` in prose, from a synced working directory.
That exact case is now `test_cases.json`'s heredoc must-allow case.

Residual gap: a trigger word inside a *non-heredoc* quoted string (a `-m "..."`
commit message, an inline `echo "npm install is dangerous"`) is still scanned as
command text and can still false-positive. Not fixed, because distinguishing real
shell syntax from an arbitrary quoted string via regex reliably needs a real shell
parser, and heredocs cover the pattern this repo's own git workflow actually uses.

## Deliberately out of scope

- **`Edit`/`NotebookEdit`** — those modify a file that already exists. The proven
  failure mode is bulk *creation*, not editing something already there; blocking
  edits would be a false positive with no matching real incident.
- **Ambiguous generic names** — `dist`, `build`, `out`, `coverage` are not on the
  block list. Those are also plausible names for a real deliverable folder a user
  wants in OneDrive. Only names that are unambiguously tool/agent byproducts are
  blocked; this trades a few false negatives for not getting in the way of
  legitimate work.

## Test suite

```powershell
python hooks\sync-guard\run_tests.py
```

21 cases: unit-level `scan_command()`/`scan_file_path()` checks plus an end-to-end
pass over the real stdin-JSON/stdout-JSON hook contract. No fixture string is ever
placed on a spawned process's command line.
