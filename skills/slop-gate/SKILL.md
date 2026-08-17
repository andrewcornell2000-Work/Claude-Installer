---
name: slop-gate
description: >
  Refuse to write slop in the first place. Use before any write to a human-facing artifact -
  spreadsheet cells, report tables, generated docs - to lint the planned change rather than
  sweeping the result afterwards. Catches self-describing prose, labels that carry their own
  derivation, magic constants that should be inputs, missing units, and formulas pointing at
  empty rows. Sweeping is remediation; this is prevention.
---

# Slop gate — lint the spec, not the wreckage

## Why this exists

Across one workbook project the owner asked for a "slop sweep" three separate times. The sweeps
worked — one cleared **321 prose cells** in a single pass — but every cell removed was a cell
something had chosen to write. The banner reading

> `KPI UPLIFT (%) - OWNER INPUT: the shaded, boxed cells are the ones you type…`

survived three cleanup passes because each pass was looking somewhere else. Assumption rows sat
labelled `(not used - leftover from the pre-slim sheet; kept so row numbers hold)`. A billing line
was called `Pallets - standing charge (180,000 p.a. x $2...)` — a label carrying its own
arithmetic, truncated by the column width so it read as gibberish.

None of that needed detecting. It needed **refusing**.

## The gate

Run this over the planned change *before* spending a write. Reject or warn as marked. It is a
few dozen lines and it pays for itself the first time it fires.

**REJECT — self-describing prose.** Any written text matching, case-insensitive:

```
how to use | type only | the shaded | boxed cells | do not type | do not overwrite
owner input | note: | memo: | story | basis / source | leftover | not used
derived machinery | for reference | e.g. | i.e.
```

An artifact that has to explain itself is badly built. Fix the layout, do not caption it.

**REJECT — a label longer than 48 characters.** A real line item is short: `Management`,
`Inbound Putaway`, `Less: CI savings`. Anything longer is a sentence wearing a label's clothes,
and the column will truncate it anyway. If the derivation matters, the number it produces belongs
in a cell of its own where it can be audited and edited.

**REJECT — a formula referencing a row that is empty on the target sheet.** This is not
cosmetic. One model carried `=Volumes!U$36*(C$99*...)` where `C99` had been empty since an old
restructure. It was inert only because an unrelated assumption happened to be zero, and the flag
that would arm it is 1 in six months of the term. A reference into blankness is a bug with a
delayed fuse.

**WARN — a magic constant in a formula.** Anything that is not `0`, `1`, `-1`, `12` or `100`,
and is not already an assumption cell, should be challenged: *should a human be able to change
this?* On one register `$173/week` and a `10/20/30/40` headcount ramp were buried inside six
typed constants. Repricing them to the owner's `$170` meant a whole spec. After they were lifted
into two visible cells it became typing.

**WARN — a typed number in a row whose siblings are formulas.** That is exactly where the `$173`
hid. A constant among computed rows is either an input that deserves the input block, or a
hardcode that will go stale.

**WARN — a written row with no unit of measure** where its neighbours have one. `hours`,
`heads/day`, `units`, `$`, `%`, `FTE`, `index`. A column of bare numbers is unreadable and, worse,
invites the wrong comparison. Where a total genuinely spans mixed units, label it `mixed` rather
than letting it look like a quantity.

**WARN — a structural op that reaches beyond its block.** A column insert cuts *every row of the
sheet*. Two inserts meant for a register punched blank columns through a driver block thirty rows
below and needed seven repair moves. Before inserting, list what else occupies those columns
anywhere on the artifact.

## What the gate must not strip

Blunt rules destroy good work. These are **not** slop and a linter that removes them has made the
artifact worse:

- Short labels naming a live data block — `Truganina total`, `Rate year`, `MAR-JUN 2026 ACTUALS`.
  Remove them and you are left with an unlabelled grid of numbers.
- A `why` on an operation, a comment in code, a note in a commit. Slop is prose *inside the
  deliverable*, aimed at the reader of the numbers. Explaining a decision to the next engineer is
  the opposite of slop.
- A derived status column that tells the owner what still needs doing — `KPI % - activity not
  set`. That is the artifact doing work, not narrating itself.

The test is: **is this text load-bearing for someone reading the numbers, or is it the builder
talking?** Keep the first. Refuse the second.

## Prefer structure over commentary

Every piece of slop removed on that project was a failure to build the thing properly:

| the commentary | what it should have been |
|---|---|
| `OWNER INPUT: the shaded cells are the ones you type` | shade the cells |
| `(not used - leftover from the pre-slim sheet)` | delete the row |
| `Pallets - standing charge (180,000 p.a. x $2...)` | `Pallets - standing charge`, with 180,000 and the rate as inputs |
| `Basis / source` column, 26 cells of provenance | one assumption cell each consumer points at |
| `Heads (10/mo, cap 40) x $173/week x 52/12` | a rate cell, a heads row, and a formula |

When you catch yourself writing an explanation into an artifact, you have found a design defect.
Fix the design.
