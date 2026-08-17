# graphify

- **graphify** (`~/.claude/skills/graphify/SKILL.md`) — any input to knowledge graph. Trigger: `/graphify`

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

## Graph output stays on local disk

The skill writes to `graphify-out/` **relative to the current working directory**. That default is
wrong whenever the corpus lives in a synced folder (OneDrive, SharePoint, Dropbox, Google Drive),
and it is wrong quietly — nothing errors, the files just upload.

What lands in that folder is not only the graph. `converted/` holds a full text copy of every
source document, `cache/` holds the extraction cache, and `graph.json` plus `graph.html` run to
several MB each. On a shared drive that republishes the entire corpus, in a second readable
format, to everyone with access to the site.

So: build every graph under `%LOCALAPPDATA%\graphify-workspace\<corpus-name>\`, on local disk, and
pass that path **absolutely** in every command — the working directory is not the workspace, so a
relative `graphify-out/` in any step of the skill must be substituted, not inherited. Local
`AppData` rather than `Documents` matters on a machine with known-folder redirection turned on,
where `Documents` is itself synced.

Corollary: a corpus and its graph live on opposite sides of the sync boundary on purpose. Moving
source files to local disk drops them out of the graph's root; moving the workspace into the synced
tree uploads the copies. Flag either tradeoff rather than silently picking one.

## No AI byproducts in synced folders

Same reasoning, wider than graphify. Never create `graphify-out/`, handoff or session-note markdown,
scratch scripts, agent-workspace dirs (`.agents/`, `.cursor/`), `node_modules/`, `__pycache__/`,
`.venv/` or `dist/` inside a synced folder — every one of them syncs to every other user on the
share. Keep them under a local scratch root (`C:\Dev\Scratch\<origin-name>\` on this machine), and
give anything with an ongoing identity its own folder under `C:\Dev\<Area>\` instead. Dev projects
that generate a dependency tree are created there from the start, not moved afterwards.

Functional config is the exception and does belong in the synced tree: `CLAUDE.md`,
`.graphifyignore`, and a `.claude/` folder holding real hooks. A per-project `.claude/` containing
only a `settings.local.json` permission cache is clutter — do not create one.

# userEmail

The user's email address is ${env:CLAUDE_USER_EMAIL}.

# Destructive shell commands (EDR)

This machine is monitored by corporate EDR. On 2026-08-10 a Claude Code PowerShell call
killed nine PIDs and then recursively force-deleted two OneDrive Desktop folders in a single
invocation; it raised a "known ransomware campaign" alert to the IT security team. The
behaviour was benign, but the shape is what ransomware detection scores on.

A `PreToolUse` hook (`hooks/edr-guard/edr_guard.py` in the Claude-Installer clone, wired into
`~/.claude/settings.json` at provision time) now hard-blocks these shapes on every Bash and
PowerShell call. It normalises backtick/caret escaping and decodes `-EncodedCommand` payloads
first, so obfuscation does not get past it. Do not try to route around it — satisfy the rules
instead:

- Never terminate processes and delete files in the same command. Separate tool calls.
- Never `Remove-Item -Recurse` / `rm -rf` anything under a synced OneDrive folder or under
  `Desktop`, `Documents`, `Downloads`, `Pictures` in any user profile. OneDrive also
  propagates such deletions to the shared SharePoint site.
- Delete one explicit path per call. Prefer moving unwanted files to `C:\Dev\Scratch\` over
  deleting them.
- Never `Stop-Process` a list of PIDs. Kill one named process, or close the app normally.
- Keep scratch and temp work under `C:\Dev\`, which is not synced.

If a genuinely destructive operation is required, explain it and ask the user to run it
themselves rather than issuing it from an agent session.

# Excel reads

The `excel` MCP pages at `EXCEL_MCP_PAGING_CELLS_LIMIT` cells per response (default 5000, roughly 40k tokens).
Reading a wide sheet in full is expensive — narrow the column range first, or aggregate in Python and return
the summary instead of the grid. When a read is paged, walk every range in `pagingRanges` before answering;
a partial read that looks complete is the main failure mode here.
