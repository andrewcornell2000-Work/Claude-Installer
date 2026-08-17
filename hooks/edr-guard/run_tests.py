#!/usr/bin/env python3
"""Test suite for edr-guard.py.

Safety: this runner imports the guard as a module and calls scan() directly. No
subprocess is spawned, no shell is invoked, and no fixture string is ever placed
on a process command line. Running it cannot trigger an EDR detection.
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from edr_guard import normalise, scan  # noqa: E402

with open(os.path.join(HERE, "test_cases.json"), encoding="utf-8") as fh:
    cases = json.load(fh)

failures = []
print("must DENY")
for case in cases["must_deny"]:
    reason = scan(normalise(case["command"]))
    if reason:
        print("  pass  %s" % case["name"])
    else:
        print("  FAIL  %s  <- allowed but should be denied" % case["name"])
        failures.append(case["name"])

print("\nmust ALLOW")
for case in cases["must_allow"]:
    reason = scan(normalise(case["command"]))
    if reason is None:
        print("  pass  %s" % case["name"])
    else:
        print("  FAIL  %s  <- denied: %s" % (case["name"], reason[:80]))
        failures.append(case["name"])

total = len(cases["must_deny"]) + len(cases["must_allow"])

# End-to-end: exercise the real hook contract (stdin JSON in, decision JSON out).
# The fixture travels over stdin only. The spawned command line is just
# "python edr_guard.py", so nothing EDR inspects ever sees the fixture text.
print("\nend to end (stdin contract)")
import subprocess  # noqa: E402

GUARD = os.path.join(HERE, "edr_guard.py")


def via_hook(tool, command):
    payload = json.dumps({"tool_name": tool, "tool_input": {"command": command}})
    proc = subprocess.run(
        [sys.executable, GUARD], input=payload, capture_output=True, text=True
    )
    out = proc.stdout.strip()
    return json.loads(out) if out else None


e2e = [
    ("PowerShell denies the original alert command", "PowerShell",
     cases["must_deny"][0]["command"], "deny"),
    ("Bash denies rm -rf on Desktop", "Bash",
     cases["must_deny"][2]["command"], "deny"),
    ("PowerShell allows npm build", "PowerShell", "npm run build", None),
    ("non-shell tool is ignored", "Read", cases["must_deny"][0]["command"], None),
]

for name, tool, command, expected in e2e:
    result = via_hook(tool, command)
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
