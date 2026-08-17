# graphify

- **graphify** (`~/.claude/skills/graphify/SKILL.md`) — any input to knowledge graph. Trigger: `/graphify`

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

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
