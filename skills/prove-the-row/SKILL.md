---
name: prove-the-row
description: >
  Positional discipline for structural edits. Use whenever a change inserts, deletes or moves
  rows, columns or sheets in a spreadsheet, a fixed-width file, a migration, or anything else
  addressed by position. Covers deriving post-edit addresses mechanically instead of by hand,
  pairing every value assertion with an identity assertion, printing the address plan before
  spending a run, and the ordering rules that stop one edit invalidating the next.
---

# Prove the row — never hand-derive an address

## The incident this exists for

On 2026-08-05, sixteen apply runs went into one workbook. **Six aborted.** Not one was a
modelling error. Three were the same bookkeeping mistake:

```
POST Variable Costs!C224: want 499.8250977126824  got 717.4285714285714
POST Variable Costs!C225: want 345.747619         got None
POST Variable Costs!C109: want 800637.1596040616  got None
```

A block had moved by four rows from an insert further up, then by six more from a second insert
above that. I had counted one of the two. `C224` was a Costco hours line; the row I wanted was
`C228`. In another spec nine rows starting at r11 ended at r19, and I wrote the assertions
against r19 and r20.

Each cost a full COM run. Roughly a third of every run spent on the project went on arithmetic a
machine should have done.

## The run that did not fail

One spec inserted six total rows and printed its plan first:

```
inserts at [248, 197, 181, 90, 55, 39]
   trug  prod  total row 40    expect 1.0000
   trug  kpi   total row 57    expect 0.0000
```

I expected 39 and 56. The printed 40 and 57 exposed the bug immediately: the shift function
counted the insert at a row's own position, which is right for an *existing* row being pushed
down and wrong for the *new* row itself. Cost: zero runs.

**Printing the address plan is the cheapest gate in this entire discipline.** It costs one line
of output and catches the most common failure before anything is spent.

## The rules

**1. Emit a map, do not remember one.** Before a structural stage, write the artifact's layout to
a machine-readable sidecar — band boundaries resolved by label, not by memory — and have the
generators read it. Regenerate it after every applied stage. Two consecutive stages built this
way aborted zero times; the two built with hand-written addresses aborted once each.

**2. Two shift functions, never one.** They are not the same and conflating them is the bug above.

```python
def existing_row(r):
    """Where a row that already exists ends up. An insert AT r pushes it down."""
    return r + sum(1 for i in INSERTS if i <= r)

def inserted_row(p):
    """Where the row created at p ends up. Only inserts strictly ABOVE it push it."""
    return p + sum(1 for i in INSERTS if i < p)
```

**3. Never type an expected value.** Read it from the artifact or compute it in the generator. One
run aborted on a preflight of `2,332,045.90` against a cell holding `2,332,046.34` — a figure I
had carried from an earlier note. If a literal appears in a spec, it must be a decision (a rate,
a headcount, an owner ruling), never an observation.

**4. Pair every value assertion with an identity assertion.**

```json
{"cell": "C121", "must_equal": 800637.16, "why": "site total unchanged"},
{"cell": "A121", "must_equal": "SITE TOTAL - TRUGANINA", "why": "and it really is that row"}
```

A value check catches a wrong row only when the wrong row happens to hold a different number.
`717.43` differed loudly. A neighbouring month, or a similar activity, would not have. The label
check makes the failure mode impossible rather than unlikely.

**5. Order edits bottom-up, and say so in the op.** Edit the lowest region first so higher
addresses stay valid. Where an op must run before another for correctness rather than
convenience — repointing a consumer before deleting what it reads — state the dependency in the
op's own `why`, because that is the only place the next reader will look.

**6. Do all inserts first, then all writes.** Interleaving means every write needs a different
offset. One insert op carrying every position, followed by writes computed from the final
addresses, is both shorter and checkable.

**7. Postflight belongs to the state it was written for.** Two specs run in one batch have their
postflight evaluated at the end, after the later spec has moved the earlier one's rows. Five
assertions failed this way for no reason other than batching. Run specs separately when one moves
rows the other asserts on.

Splitting is not always possible — the specs may have to share one recalc. Then the rule is:
**every postflight address must be written in the coordinates that exist at the END of the run.**
Put the assertion in the spec that knows the shift, not the spec that made the change. An earlier
spec asserting `Variable Costs!C332` when a later one inserts six rows above it does not fail
loudly; it checks a different cell, and on a bad day that cell agrees.

**8. Never point a generator at the file the run overwrites.** A generator that derives its
addresses and its violation list from `build_REJECTED.xlsx` reads, on its second run, a workbook
that already has its own spec applied: the decimal scan found zero violations because it had
already fixed them, and every Volumes address came back shifted by its own row inserts. Both
failures looked like bugs in the spec. Pin the generator to a snapshot written once — a file whose
name says it is a snapshot — and regenerate the snapshot deliberately, never as a side effect.

## Structural edits have side effects beyond position

Things that cost runs on this project and are worth checking before spending one:

- **A column insert cuts every row of the sheet**, not just the block you are looking at. Two
  inserts intended for a register punched blank columns through a driver block thirty rows below
  it, which then needed seven single-column moves to repair. Check what else occupies those
  columns *anywhere* on the sheet first.
- **Merged cells refuse Cut and Insert.** `We can't do that to a merged cell.` Banner rows are
  usually merged. Unmerge the band first.
- **Move, do not copy, when references must follow.** Excel's Cut repoints every formula that
  read the moved cells; Copy leaves them pointing at the old address. A block moved by Cut had
  its three consumer formulas verified unchanged to the cent afterwards — that check is what
  proves the repoint happened.
- **Deleting a row that an explicit reference points at yields `#REF!`**, while a range reference
  silently narrows. Rewrite `=A1+A2+A3` into a range before deleting inside it.

## When not to parallelise

Four stages of this project all restructured the same sheet, and each one shifted the next one's
addresses. Farming them to concurrent agents would have produced four sets of specs written
against four different layouts, none of which composed. Serial was correct, and saying so is
better than silently not parallelising.

Parallelise across *independent artifacts* — different sheets, different files, different
services. Serialise anything that shares an address space.
