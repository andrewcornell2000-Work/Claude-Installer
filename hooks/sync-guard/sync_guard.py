#!/usr/bin/env python3
"""PreToolUse guard: keep AI/tool byproducts out of synced folders.

Background
----------
On 2026-08-17 a `graphify-out\\` directory was found sitting at the root of the
"OneDrive - Maersk Group" folder: 293 files, ~430 MB (converted copies of every
source document plus the extraction cache). OneDrive propagates everything under
that root to the shared SharePoint site, so every other user with access to the
site downloads it on their next sync. Nothing errored when it was created -- the
graphify skill's default output path (`graphify-out/`) is relative to the current
working directory, and the working directory that day was the OneDrive root.

The written rule ("graph output stays on local disk", `config/CLAUDE.md`) already
existed before that leak happened. Text-only memory did not stop it. This hook
enforces it at the tool-call boundary instead: it denies creating or writing a
named AI/tool byproduct path (graphify-out, node_modules, __pycache__, .venv,
.agents, .cursor, .alfred, ai-workspace, or a HANDOFF*.md / AGENTS.md file)
anywhere under a folder whose path names a known sync provider (OneDrive,
SharePoint, Dropbox, Google Drive, iCloud Drive).

Design notes
------------
* Checked against both the command/path text AND the tool call's cwd, because the
  proven failure mode is a *relative* path (`graphify-out`) run from a synced
  working directory -- the command text alone never mentions "OneDrive".
* Read-only operations are not blocked. Only write-shaped commands (mkdir,
  New-Item, Out-File, Set-Content, Copy-Item, git clone, npm/pip/uv install,
  Python's .write_text()/.write_bytes()/open(...,'w'), or plain `>` redirection)
  trip the guard.
* Scoped to Bash, PowerShell and Write. Not Edit/NotebookEdit: those modify a
  file that already exists, which is not how the bulk-clutter failure mode
  happens -- and blocking edits to pre-existing project files would be a false
  positive with no corresponding real incident.
* Ambiguous generic names (`dist`, `build`, `out`, `coverage`) are deliberately
  NOT on the block list -- those are also plausible names for a real deliverable
  folder a user wants in OneDrive. Only names that are unambiguously tool/agent
  byproducts are blocked. This trades some false negatives for not annoying
  legitimate work.
* Fails open on malformed input: an unparsable payload must not wedge every
  shell call or file write in the session.
"""

import json
import os
import re
import sys

# --- normalisation (same approach as hooks/edr-guard/edr_guard.py) --------

import base64

ENCODED_COMMAND = re.compile(
    r"(?i)-e(?:nc|ncoded|ncodedcommand)?\s+([A-Za-z0-9+/=]{16,})"
)


HEREDOC_OPEN = re.compile(r"<<-?\s*(['\"]?)(\w+)\1")


def strip_data_blocks(raw):
    """Blank out heredoc/here-string bodies.

    The text between `<<'EOF' ... EOF` (bash) or `@'...'@` / `@"..."@`
    (PowerShell here-strings) is literal data handed to a command's stdin or a
    variable -- it is not further shell syntax, and scanning it for shell verbs
    is a category error. A `git commit -F - <<'EOF' ... EOF` whose message
    happens to describe this very hook (mentions "npm install", "git clone", a
    bare ">") would otherwise trip it on its own documentation. This must run
    on the RAW command, before whitespace is collapsed -- heredoc terminators
    are newline-delimited.
    """
    result = raw
    while True:
        m = HEREDOC_OPEN.search(result)
        if not m:
            break
        delim = m.group(2)
        end_pat = re.compile(rf"(?m)^\s*{re.escape(delim)}\s*$")
        end_m = end_pat.search(result, m.end())
        if not end_m:
            break  # unterminated in what we can see -- leave rest as-is
        result = result[: m.end()] + " " + result[end_m.end() :]

    result = re.sub(r"(?s)@'.*?'@", " ", result)
    result = re.sub(r'(?s)@".*?"@', " ", result)
    return result


def normalise(cmd):
    """Strip shell escaping, inline any base64 payload, blank data blocks."""
    text = strip_data_blocks(cmd).replace("`", "").replace("^", "")

    for blob in ENCODED_COMMAND.findall(cmd):
        for encoding in ("utf-16-le", "utf-8"):
            try:
                decoded = base64.b64decode(blob + "=" * (-len(blob) % 4)).decode(
                    encoding, errors="ignore"
                )
            except Exception:
                continue
            if decoded.strip():
                text += "\n" + decoded
                break

    return re.sub(r"\s+", " ", text)


# --- pattern groups ---------------------------------------------------------

SYNCED_MARKER = re.compile(
    r"(?i)onedrive|sharepoint|dropbox|google\s*drive|icloud\s*drive"
)

BYPRODUCT_NAMES = [
    "graphify-out",
    ".agents",
    ".cursor",
    ".alfred",
    "node_modules",
    "__pycache__",
    ".venv",
    "ai-workspace",
]
_NAME_ALT = "|".join(re.escape(n) for n in BYPRODUCT_NAMES)
_BOUND_L = r'(?:^|[\s"\'\\/=,;|])'
_BOUND_R = r'(?:[\s"\'\\/=,;|]|$)'
# Name is captured in group 1 so callers can report the clean name -- the boundary
# chars are consumed by the match (Python's re has no variable-width lookbehind
# for a "^ or one of these chars" alternation) but must not leak into the report.
BYPRODUCT_DIR = re.compile(rf"(?i){_BOUND_L}({_NAME_ALT}){_BOUND_R}")

BYPRODUCT_FILE = re.compile(r"(?i)\b((?:handoff[\w.-]*\.md)|(?:agents\.md))\b")

# npm/pnpm/yarn install writes node_modules as a side effect -- the command text
# never spells the directory name, so BYPRODUCT_DIR alone can't see it.
PACKAGE_INSTALL = re.compile(r"(?i)\b(npm|pnpm|yarn)\s+(install|i|add)\b")

WRITE_VERB = re.compile(
    r"(?i)\b(mkdir|md|new-item)\b|"
    r"\bout-file\b|\bset-content\b|\badd-content\b|"
    r"\b(copy-item|cp|copy|xcopy|robocopy)\b|"
    r"\bgit\s+clone\b|"
    r"\b(npm|pnpm|yarn)\s+(install|i|add)\b|"
    r"\b(pip|uv\s+pip)\s+install\b|"
    r"\buv\s+tool\s+install\b|"
    r"\btouch\b|"
    r"\.write_text\s*\(|\.write_bytes\s*\(|"
    r"open\s*\([^)]*['\"][wax]|"
    r"(?<![-=<])>(?!=)"  # bare redirection, not ->, =>, >=
)

DENY_MSG = (
    "Blocked: this creates {what} under a synced folder ({provider}). On "
    "2026-08-17 exactly this shape (graphify-out/, relative to a OneDrive "
    "working directory) put 430 MB / 293 files -- converted source documents "
    "plus an extraction cache -- into the shared SharePoint site for every "
    "other user on it. Build it under C:\\Dev\\ or "
    "%LOCALAPPDATA%\\graphify-workspace\\ instead (see config/CLAUDE.md), and "
    "copy only the finished deliverable into OneDrive if one is needed there."
)


def deny(reason):
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            }
        )
    )
    sys.exit(0)


def _provider(text):
    m = SYNCED_MARKER.search(text)
    return m.group(0) if m else "a synced folder"


def scan_command(cmd, cwd):
    """Return a deny reason for a Bash/PowerShell command, or None."""
    synced_text = SYNCED_MARKER.search(cmd)
    synced_cwd = cwd and SYNCED_MARKER.search(cwd)
    if not (synced_text or synced_cwd):
        return None
    provider = _provider(cmd) if synced_text else _provider(cwd)

    if PACKAGE_INSTALL.search(cmd):
        return DENY_MSG.format(what="'node_modules' (created by npm/pnpm/yarn install)", provider=provider)

    hit = BYPRODUCT_DIR.search(cmd) or BYPRODUCT_FILE.search(cmd)
    if not hit:
        return None
    if not WRITE_VERB.search(cmd):
        return None

    return DENY_MSG.format(what=f"'{hit.group(1)}'", provider=provider)


def scan_file_path(file_path, cwd):
    """Return a deny reason for a Write tool call, or None."""
    if not file_path:
        return None

    abs_path = file_path if os.path.isabs(file_path) else os.path.join(cwd or "", file_path)
    norm = abs_path.replace("/", "\\")

    if not SYNCED_MARKER.search(norm):
        return None

    hit = BYPRODUCT_DIR.search(norm) or BYPRODUCT_FILE.search(os.path.basename(norm))
    if not hit:
        return None

    return DENY_MSG.format(what=f"'{hit.group(1)}'", provider=_provider(norm))


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    tool = payload.get("tool_name")
    ti = payload.get("tool_input") or {}
    cwd = payload.get("cwd") or os.getcwd()

    if tool in ("Bash", "PowerShell"):
        raw = ti.get("command") or ""
        if not raw.strip():
            sys.exit(0)
        reason = scan_command(normalise(raw), cwd)
    elif tool == "Write":
        file_path = ti.get("file_path") or ""
        reason = scan_file_path(file_path, cwd)
    else:
        sys.exit(0)

    if reason:
        deny(reason)

    sys.exit(0)


if __name__ == "__main__":
    main()
