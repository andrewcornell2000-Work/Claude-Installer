---
name: parallel-first
description: >
  Automatic parallelization reflex. On EVERY substantive task - before starting work, when
  planning, when a long-running step begins, when waiting on anything (an agent, a build, a
  human), or when the user mentions speed, deadlines, or "I don't have much time" - scan for
  work that can run concurrently and hand it to agents immediately. Trigger especially when
  about to do multi-file reads, multi-part analysis, verification, spec-writing, doc updates,
  or any pipeline with independent stages. The user's time is the scarce resource; idle
  wall-clock while one thing runs serially is the failure mode this skill removes.
---

# Parallel-first — keep every lane full

## Why this skill exists

On 2026-08-04 the owner watched a spreadsheet rebuild run as: scouts (5 agents) → specs
(4 agents) → mapping fix (2 agents) + tail prep (4 agents) running simultaneously — while the
owner said: "handing over to more agents and doing different tasks helps me a lot more than you
think." The serial version of that day would have taken several times longer. The bottleneck is
never the model thinking harder; it is lanes sitting empty.

## The reflex — run this scan at every step boundary

Ask, every time a task starts or a step completes:

1. **What is the critical path?** Name the single chain of steps that truly must be serial.
   Everything not on it is a parallelization candidate.
2. **What is downstream but not blocked?** Verification harnesses, acceptance scripts, docs,
   cosmetic/polish batches, tooling updates, report templates — these can almost always be
   built BEFORE the thing they will verify or describe exists. Pre-build them while the
   critical path runs.
3. **What am I about to read or analyse?** Two or more files, sheets, dimensions, or sites =
   one agent each, launched in a single fleet, never sequential reads in the main thread.
4. **What am I waiting on?** Waiting is a signal, not dead time: launch the next prep fleet,
   draft the deploy script, write the tie harness, update the task list.
5. **What did the user just add?** New data files, new requirements mid-flight — spin up
   dedicated analysts for them in parallel with the existing streams; do not queue them.

If the scan finds nothing to parallelize, say so in one line and continue — but the scan runs.

## Fleet design rules (learned the hard way, same day)

- **One writer per artifact.** Excel COM / OLE locks, git worktrees, any single-file artifact:
  exactly ONE process writes; agents get read-only copies. Parallel reads are free; parallel
  writes to one file are corruption.
- **Specs fan out, assembly funnels in.** Have agents author exact machine-readable specs in
  parallel; a single deterministic assembler consumes them. Never have multiple agents "just
  edit" the same deliverable.
- **Write output files EARLY and incrementally.** One agent died silently after 30 minutes of
  reading with its output unwritten — everything lost. Agents must create their output file
  first and update it as they go, so a death costs corrections, not the whole run.
- **Give every agent the traps.** Environment traps (python -P, Write tool not heredocs,
  read-only workbook access, column offsets) go in a COMMON preamble in every prompt. An agent
  that rediscovers a known trap wastes its whole runtime.
- **Independent verification is a fleet, not a step.** After a build, launch adversarial
  verifiers in parallel (error sweep, value diff, structure audit, label-aligned comparison) —
  each blind to the others. They finish in the time of the slowest one.
- **Name the merge point.** Every fleet's outputs converge somewhere (a merged map, a combined
  report, a deploy). State it when launching so nothing dangles.
- **Match agent count to real structure.** One agent per site / per file / per dimension / per
  verification lens. Do not split one coherent judgment across agents — that adds merge cost
  for nothing.

## Interplay with verification gates (the fearless skill)

Parallel boldness is funded the same way as ambitious boldness: the harness catches errors at
zero cost. A wrong mapping from a parallel agent is caught by the tie check; a bad parallel
draft is caught at review. So delegate liberally — the gates make agent mistakes cheap. The
one thing gates cannot fix is two writers on one artifact; that rule is absolute.

## What this never overrides

- Approval boundaries: number-moving changes, irreversible actions, and settled rulings still
  wait for the owner regardless of how fast the fleet could apply them.
- The single-writer rule above.
- Report faithfully: a dead or empty agent result is stated plainly and recovered, never
  papered over.
