#!/usr/bin/env python3
"""PreToolUse guard: block shell commands that EDR scores as ransomware.

Background
----------
On 2026-08-10 a Claude Code PowerShell call killed nine PIDs and then recursively
force-deleted two OneDrive Desktop folders in one invocation. Corporate EDR raised
a "known ransomware campaign" alert against host MMDW5NXLP07H066 and it reached the
IT security team. The intent was benign; the shape was not distinguishable from an
encryptor releasing file locks before destroying user data on a cloud-synced path.

This hook denies that shape, and the common ways of arriving at it, before the
command reaches a shell. It is wired as a PreToolUse hook on Bash and PowerShell.

Design notes
------------
* Normalises the command first, so backtick/caret escaping and -EncodedCommand
  base64 cannot smuggle a blocked pattern past the regexes.
* Recursive force deletes are permitted under known-disposable roots (C:\\Dev, temp
  directories, node_modules and friends) so ordinary build cleanup still works.
  Anything touching OneDrive or a user profile data folder is denied outright.
* Fails open on malformed input: an unparsable payload must not wedge every shell
  call in the session.
"""

import base64
import json
import re
import sys

# --- normalisation --------------------------------------------------------

ENCODED_COMMAND = re.compile(
    r"(?i)-e(?:nc|ncoded|ncodedcommand)?\s+([A-Za-z0-9+/=]{16,})"
)


def normalise(cmd):
    """Strip shell escaping and inline any base64 payload, so patterns can't hide."""
    text = cmd.replace("`", "").replace("^", "")

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


# --- pattern groups -------------------------------------------------------

# Process termination, including PowerShell aliases (spps, kill) and WMI/.NET routes.
KILL = re.compile(
    r"(?i)\b(stop-process|spps|taskkill|pskill|pkill|killall)\b|"
    r"\bkill\b\s*(-9|\(|\$)|"
    r"\.kill\s*\(|"
    r"\bwmic\b[^\n;|]*\bprocess\b[^\n;|]*\b(delete|terminate|call)\b|"
    r"invoke-cimmethod[^\n;|]*terminate"
)

# More than one PID handed to a single termination call.
KILL_MANY = re.compile(
    r"(?i)(stop-process|spps)[^\n;|]*-id\s+[\d\s]*\d\s*,\s*\d|"
    r"taskkill[^\n;|]*(/pid\s+\d+[^\n;|]*){2,}|"
    r"get-process[^\n;|]*-id\s+[\d\s]*\d\s*,\s*\d"
)

# Any deletion verb at all, including PowerShell aliases ri/rm/del/erase/rd/rmdir.
ANY_DELETE = re.compile(
    r"(?i)\b(remove-item|erase|rmdir|clear-content)\b|"
    r"(?<![\w-])\b(rm|ri|del|rd)\b|"
    r"\[(system\.)?io\.(directory|file)\]::delete|"
    r"\.delete\s*\(\s*\)"
)

# Recursive destructive delete, PowerShell or POSIX or .NET.
RECURSIVE_DELETE = re.compile(
    r"(?i)(remove-item|(?<![\w-])\b(ri|rm|del)\b)[^\n;|]*-recurse|"
    r"\b(rmdir|rd)\b[^\n;|]*/s|"
    r"(?<![\w-])\brm\b[^\n;|]*(-[a-z]*r[a-z]*f|-[a-z]*f[a-z]*r|--recursive)|"
    r"\[(system\.)?io\.directory\]::delete\s*\([^)]*,\s*\$?true"
)

# Recursive enumeration piped into a delete: gci -Recurse | Remove-Item
PIPED_RECURSIVE_DELETE = re.compile(
    r"(?i)\b(get-childitem|gci|ls|dir)\b[^\n;]*-recurse[^\n;]*\|[^\n;]*"
    r"(remove-item|(?<![\w-])\b(ri|rm|del)\b)"
)

# Wildcard sweep of a directory's contents.
WILDCARD_DELETE = re.compile(
    r"(?i)(remove-item|(?<![\w-])\b(ri|rm|del)\b)[^\n;|]*[\\/]\*"
)

# Cloud-synced or user-data paths, including env-var and tilde forms.
PROTECTED_PATH = re.compile(
    r"(?i)onedrive|"
    r"(?:[a-z]:|/[a-z])[\\/]+users[\\/]+[^\\/\"'\n]+[\\/]+"
    r"(desktop|documents|downloads|pictures|videos|music)|"
    r"(\$env:userprofile|%userprofile%|\$home|~|\$env:onedrive|%onedrive%)"
    r"[\\/]+(desktop|documents|downloads|pictures|videos|music|onedrive)"
)

# Roots where recursive force deletes are ordinary housekeeping.
SAFE_ROOT = re.compile(
    r"(?i)c:[\\/]+dev[\\/]|"
    r"[\\/]temp[\\/]|[\\/]tmp[\\/]|\$env:temp|%temp%|"
    r"\b(node_modules|__pycache__|\.venv|\.next|dist|build|out|coverage|\.pytest_cache)\b"
)

FORCE_NOCONFIRM = re.compile(r"(?i)-force\b|-confirm:\s*\$false|(?<![\w-])-f\b")

# Commands whose only real-world use is destroying recovery or hiding tracks.
# Any one of these alone is a high-severity EDR detection.
ANTI_FORENSIC = re.compile(
    r"(?i)vssadmin[^\n;|]*\bdelete\b[^\n;|]*shadows|"
    r"\bwbadmin\b[^\n;|]*\bdelete\b|"
    r"get-wmiobject[^\n;|]*win32_shadowcopy[^\n;|]*\bdelete\b|"
    r"bcdedit[^\n;|]*(recoveryenabled\s+no|bootstatuspolicy\s+ignoreallfailures)|"
    r"\bcipher\b[^\n;|]*/w|"
    r"wevtutil[^\n;|]*\bcl\b|\bclear-eventlog\b|"
    r"fsutil[^\n;|]*usn[^\n;|]*deletejournal"
)

# Disabling endpoint protection.
DEFENDER_TAMPER = re.compile(
    r"(?i)set-mppreference[^\n;|]*-disable|"
    r"add-mppreference[^\n;|]*exclusionpath|"
    r"\bsc\b[^\n;|]*(stop|delete)[^\n;|]*(windefend|sense|sysmon)|"
    r"stop-service[^\n;|]*(windefend|sense|sysmon)"
)

# Decode-then-execute, the classic obfuscated-payload pattern.
DECODE_AND_RUN = re.compile(
    r"(?i)frombase64string[\s\S]{0,200}?(invoke-expression|\biex\b)|"
    r"(invoke-expression|\biex\b)[\s\S]{0,200}?frombase64string"
)

REWRITE = (
    " Rewrite it: delete one explicit path per call without -Recurse, or move the "
    "target to C:\\Dev\\Scratch\\ instead of deleting it. Keep any process "
    "termination in a separate tool call from any delete. If the destructive form "
    "is genuinely required, explain it and ask the user to run it themselves."
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


def scan(cmd):
    """Return a deny reason for cmd, or None if it is allowed."""
    if ANTI_FORENSIC.search(cmd):
        return (
            "Blocked: this command destroys backups, shadow copies, or event logs. "
            "That is a high-severity ransomware indicator and will page the security "
            "team. An agent session must never run it."
        )

    if DEFENDER_TAMPER.search(cmd):
        return (
            "Blocked: this command disables or excludes paths from endpoint "
            "protection. Agent sessions must not modify security tooling."
        )

    if DECODE_AND_RUN.search(cmd):
        return (
            "Blocked: base64 payload decoded and executed. Obfuscated execution is "
            "treated as malware by EDR regardless of intent. Run the plain command."
        )

    if KILL.search(cmd) and ANY_DELETE.search(cmd):
        return (
            "Blocked: this command terminates processes and deletes files in the same "
            "invocation. That is the canonical ransomware sequence and it fired the "
            "corporate EDR ransomware rule on 2026-08-10." + REWRITE
        )

    if KILL_MANY.search(cmd):
        return (
            "Blocked: mass process termination (multiple PIDs in one call). EDR reads "
            "this as an encryptor releasing file locks. Terminate one named process at "
            "a time, or close the application normally."
        )

    recursive = RECURSIVE_DELETE.search(cmd) or PIPED_RECURSIVE_DELETE.search(cmd)

    if (recursive or WILDCARD_DELETE.search(cmd)) and PROTECTED_PATH.search(cmd):
        return (
            "Blocked: bulk delete targeting a OneDrive-synced or user-profile data "
            "folder. EDR scores bulk destruction under those paths as ransomware, and "
            "OneDrive propagates the deletion to the shared SharePoint site for every "
            "user on it." + REWRITE
        )

    if recursive and FORCE_NOCONFIRM.search(cmd) and not SAFE_ROOT.search(cmd):
        return (
            "Blocked: recursive force delete with confirmation suppressed, on a path "
            "outside the known-disposable roots (C:\\Dev, temp directories, "
            "node_modules and similar). Target explicit individual paths, or confirm "
            "the path is disposable." + REWRITE
        )

    return None


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    if payload.get("tool_name") not in ("Bash", "PowerShell"):
        sys.exit(0)

    raw = (payload.get("tool_input") or {}).get("command") or ""
    if not raw.strip():
        sys.exit(0)

    reason = scan(normalise(raw))
    if reason:
        deny(reason)

    sys.exit(0)


if __name__ == "__main__":
    main()
