# graphify

- **graphify** (`~/.claude/skills/graphify/SKILL.md`) — any input to knowledge graph. Trigger: `/graphify`

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

# userEmail

The user's email address is ${env:CLAUDE_USER_EMAIL}.

# Excel reads

The `excel` MCP pages at `EXCEL_MCP_PAGING_CELLS_LIMIT` cells per response (default 5000, roughly 40k tokens).
Reading a wide sheet in full is expensive — narrow the column range first, or aggregate in Python and return
the summary instead of the grid. When a read is paged, walk every range in `pagingRanges` before answering;
a partial read that looks complete is the main failure mode here.
