# ClaudeGuards

Guard rails that stop a Claude Code session from issuing shell commands the
corporate EDR agent scores as ransomware.

## Why this exists

On 2026-08-10 a Claude Code PowerShell call did two things in one invocation:

1. terminated nine PIDs with `Stop-Process -Force`, then
2. recursively force-deleted two folders under
   `OneDrive - Maersk Group\Desktop`.

EDR raised **"A process associated with a known ransomware campaign launched"**
against host `MMDW5NXLP07H066`, and the alert reached the IT security team. The
intent was benign — cleaning up test folders — but the behaviour is exactly what
an encryptor does: release file locks, then destroy user data on a cloud-synced
path. Detection scores behaviour, not intent.

## What is installed

`edr_guard.py` runs as a Claude Code `PreToolUse` hook on the `Bash` and
`PowerShell` tools, wired in `C:\Users\ACO324\.claude\settings.json`:

```json
"PreToolUse": [
  {
    "matcher": "Bash|PowerShell",
    "hooks": [
      { "type": "command", "command": "python \"C:\\Dev\\ClaudeGuards\\edr_guard.py\"" }
    ]
  }
]
```

It inspects each command before it reaches a shell and returns a `deny` decision
for the shapes below. The deny reason tells the model how to rewrite, so it
self-corrects rather than retrying. This is enforced by the harness, not by
prompt instructions — the model cannot talk its way past it.

### Denied

| Shape | Example |
|---|---|
| Process termination and file deletion in one command | the original alert |
| Bulk delete under OneDrive or a user-profile data folder | `Remove-Item ~\Documents\x -Recurse` |
| Recursive force delete outside known-disposable roots | `Remove-Item D:\Shared\a -Recurse -Force` |
| Multiple PIDs to one termination call | `Stop-Process -Id 1,2,3` |
| Recursive enumeration piped to a delete | `gci $env:USERPROFILE\Desktop -Recurse \| ri` |
| Wildcard sweep of a protected directory | `Remove-Item C:\Users\...\Desktop\* -Force` |
| Shadow copy / backup / event log destruction | `vssadmin delete shadows`, `wevtutil cl` |
| Endpoint protection tampering | `Set-MpPreference -DisableRealtimeMonitoring` |
| Base64 payload decoded and executed | `iex ([Text.Encoding]::UTF8.GetString(...))` |

Commands are normalised before matching: backticks and carets are stripped, and
`-EncodedCommand` base64 is decoded and re-scanned, so obfuscation does not get
a pattern past the regexes.

### Allowed

Ordinary work is untouched. Recursive force deletes are permitted under
known-disposable roots — `C:\Dev`, temp directories, `node_modules`, `dist`,
`build`, `.venv`, `__pycache__` — so build cleanup still works. Copying or
moving files into and out of OneDrive is fine; only bulk destruction there is
blocked.

## Tests

```bash
python C:\Dev\ClaudeGuards\run_tests.py
```

49 cases: 28 in `test_cases.json` that must be denied, 17 that must be allowed,
plus 4 end-to-end checks of the real hook contract (stdin JSON in, decision JSON
out) covering both tools and the non-shell-tool passthrough.

**The suite cannot trigger an EDR alert.** The runner imports the guard as a
Python module and calls `scan()` directly. No subprocess is spawned, no shell is
invoked, and no fixture string is ever placed on a process command line — which
is what EDR inspects. Fixtures live in a `.json` data file rather than a `.ps1`
or `.cmd`, so no script scanner treats them as runnable.

Add a case to `test_cases.json` and re-run when tightening a pattern.

## Notes

- Hook changes are read at session start. After editing `settings.json` or the
  guard, restart Claude Code before relying on the new behaviour.
- The matching rule set is also written into `C:\Users\ACO324\.claude\CLAUDE.md`
  so sessions avoid these shapes in the first place, rather than discovering
  them by getting blocked.
- Everything here is on local disk. Nothing in this guard writes to OneDrive.
