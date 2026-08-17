#!/usr/bin/env python3
"""Test suite for sync_guard.py.

Safety: this runner imports the guard as a module and calls scan_command()/
scan_file_path() directly. No subprocess is spawned for the unit cases, so no
fixture string is ever placed on a process command line. The end-to-end block
below does spawn one, but the payload travels over stdin only and the spawned
command line is just "python sync_guard.py".
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from sync_guard import normalise, scan_command, scan_file_path  # noqa: E402

with open(os.path.join(HERE, "test_cases.json"), encoding="utf-8") as fh:
    cases = json.load(fh)

failures = []


def run_case(case):
    if case["tool"] in ("Bash", "PowerShell"):
        return scan_command(normalise(case["command"]), case.get("cwd"))
    return scan_file_path(case.get("file_path"), case.get("cwd"))


print("must DENY")
for case in cases["must_deny"]:
    if case["tool"] not in ("Bash", "PowerShell", "Write"):
        raise AssertionError(f"must_deny case uses an out-of-scope tool: {case['name']}")
    reason = run_case(case)
    if reason:
        print("  pass  %s" % case["name"])
    else:
        print("  FAIL  %s  <- allowed but should be denied" % case["name"])
        failures.append(case["name"])

print("\nmust ALLOW")
for case in cases["must_allow"]:
    if case["tool"] not in ("Bash", "PowerShell", "Write"):
        # Out-of-scope tool: guard's main() would ignore it before ever calling
        # scan_*(). Nothing to run; the tool-filtering itself is covered by the
        # end-to-end block below.
        print("  pass  %s  (out of scope by tool_name, verified end-to-end)" % case["name"])
        continue
    reason = run_case(case)
    if reason is None:
        print("  pass  %s" % case["name"])
    else:
        print("  FAIL  %s  <- denied: %s" % (case["name"], reason[:90]))
        failures.append(case["name"])

total = len(cases["must_deny"]) + len(cases["must_allow"])

# End-to-end: exercise the real hook contract (stdin JSON in, decision JSON out).
print("\nend to end (stdin contract)")
import subprocess  # noqa: E402

GUARD = os.path.join(HERE, "sync_guard.py")


def via_hook(tool, cwd, command=None, file_path=None):
    tool_input = {}
    if command is not None:
        tool_input["command"] = command
    if file_path is not None:
        tool_input["file_path"] = file_path
    payload = json.dumps({"tool_name": tool, "cwd": cwd, "tool_input": tool_input})
    proc = subprocess.run(
        [sys.executable, GUARD], input=payload, capture_output=True, text=True
    )
    out = proc.stdout.strip()
    return json.loads(out) if out else None


e2e = [
    (
        "PowerShell denies the proven leak shape",
        "PowerShell",
        "C:\\Users\\ACO324\\OneDrive - Maersk Group",
        cases["must_deny"][0]["command"],
        None,
        "deny",
    ),
    (
        "Write denies graphify-out under OneDrive",
        "Write",
        "C:\\Dev",
        None,
        cases["must_deny"][6]["file_path"],
        "deny",
    ),
    (
        "PowerShell allows the same command from a local cwd",
        "PowerShell",
        "C:\\Dev\\Scratch",
        cases["must_allow"][0]["command"],
        None,
        None,
    ),
    (
        "Edit tool is ignored regardless of path",
        "Edit",
        "C:\\Users\\ACO324\\OneDrive - Maersk Group",
        None,
        cases["must_deny"][6]["file_path"],
        None,
    ),
]

for name, tool, cwd, command, file_path, expected in e2e:
    result = via_hook(tool, cwd, command, file_path)
    if expected == "deny":
        ok = (
            result is not None
            and result.get("hookSpecificOutput", {}).get("permissionDecision") == "deny"
            and result["hookSpecificOutput"].get("permissionDecisionReason")
        )
    else:
        ok = result is None
    print("  %s  %s" % ("pass" if ok else "FAIL", name))
    if not ok:
        failures.append(name)

total += len(e2e)
print("\n%d/%d passed" % (total - len(failures), total))
sys.exit(1 if failures else 0)
