---
name: script-hot-loops
description: Cost-check every loop before running a script you just wrote or edited. Use whenever authoring or modifying a .py (or any) script that loops over cells, rows, files, records, or API objects - especially loops that cross a process boundary (Excel COM, HTTP, DB, subprocess) or re-open a resource. Trigger before the first run, on any edit that adds or widens a loop, and immediately whenever a run takes far longer than the work justifies.
---

# Script hot loops — count the crossings before you run it

## The incident this exists for

On 2026-08-04 a workbook build script took **15 minutes per run**. The owner asked, plainly,
"i dont get why it takes so long what is it doing......."

The answer was one line. A rewrite pass walked a range cell by cell:

```python
for c in cell_list(ws, o):        # ws.Range("A1:BZ400") expanded to individual cells
    f = c.Formula                 # <- one out-of-process COM round trip, ~1ms
    ...
```

`A1:BZ400` is 78,000 cells. Six such passes ≈ **470,000 round trips ≈ 8 minutes** — to change
about 3,400 cells. The fix was to read each range in ONE call:

```python
vals = rng.Formula                # entire block returned as nested tuples, 1 round trip
# ...match in Python, then write back only the cells that actually changed
```

**15 minutes → 42 seconds.** Same output, same gates, ~20x.

The real cost was not the minutes. It was that a 15-minute cycle made iteration feel expensive,
so debugging got batched into big risky runs instead of small cheap ones. Once a run cost 40
seconds, the remaining bugs fell in minutes. **Slow scripts distort judgement, not just clocks.**

## The rule

Before running a script you just wrote or edited, for every loop ask:

**How many times does this cross a boundary, and what does one crossing cost?**

A boundary is anything outside your process: COM/Interop, HTTP, a database, a subprocess, a
file open, an MCP tool. One crossing is ~0.1–10ms. Multiply it out. If the product is more than
a second or two, batch before you run — do not "just try it and see".

Cheap in-process work (regex over a string, dict lookups, arithmetic) is essentially free by
comparison. Move the loop there.

## The patterns, and what to do instead

**Per-item boundary call → bulk read, filter in memory, write back only changes.**
```python
# slow: N round trips
for cell in rng:  v = cell.Value
# fast: 1 round trip
block = rng.Value          # nested tuples
```
Writes usually can't be batched as easily — but you normally only write a handful, so read
in bulk and write individually.

**Resource opened inside the loop → open once outside it.**
`load_workbook`, `connect()`, `open()`, importing a model. Loading a workbook per row is the
same defect wearing different clothes.

**Whole-collection scan per item → build an index once.**
Two nested loops matching by label is O(n·m); a dict makes it O(n+m). Same for `in list`
(O(n)) versus `in set` (O(1)).

**Work repeated per iteration that never changes** — compiled regexes, parsed config, a sorted
key list, an alternation pattern built from a dict. Hoist it above the loop.

**Requesting more than you need.** Fetching every column when you use two; recursing the whole
tree when you need one folder; `SELECT *` for one field. Narrow at the source.

## Bound it before you run it

Put the arithmetic in a comment where the loop is:

```python
# 6 sheets x 1 bulk read each = 6 round trips (was 6 x 78,000 = 470k)
```

If you can't state the count, you don't know what the script will cost. Work it out first.

For anything that will run more than ~30 seconds, print progress with a running count and
elapsed time, so a slow run is diagnosable instead of merely mysterious. And time the run:

```python
t0 = time.time(); ...; print(f"elapsed {time.time()-t0:.1f}s")
```

## When a run is slower than the work justifies

Treat it as a defect, not a fact of life. Estimate what it *should* take (bytes touched, cells
changed, rows written). If actual is more than ~10x that, there is a hot loop — find it before
running again. Do not iterate on a slow script; fix the loop first, because every subsequent
debugging cycle pays the same tax.

## What this never justifies

- Don't trade correctness for speed. Batching must produce identical results — if a bulk read
  changes semantics (types, blanks, error values coming back differently), handle that
  explicitly rather than accepting drift.
- Don't disable safety to go faster. Turning off screen updating and recalculation is fine;
  skipping verification is not. Restore anything you disabled **before** the verification step,
  and never let a performance setting leak into a saved artifact — `calcMode="manual"` once
  leaked into a deployed workbook this way.
- Don't optimise a loop that runs twice. Only the ones whose count is large.
