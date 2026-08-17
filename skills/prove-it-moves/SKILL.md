---
name: prove-it-moves
description: >
  Catch writes that landed but do nothing. Use whenever a change is supposed to make a model
  RESPOND to input - a new driver, a lookup, a rewired formula, a toggle, a rate that should
  flow through - and especially when the expected result is "nothing moves yet". A static
  assertion cannot tell a working mechanism from a dead one when the expected value is 1.00,
  0.00, or unchanged. Poke the input and watch the output.
---

# Prove it moves — a green gate can be green over a corpse

## The incident this exists for

On 2026-08-05 two specs rebuilt a CI register and wired it into a cost model's KPI rows. The
apply run reported:

```
close -17,508,628.0779 -> -17,508,628.0779  delta +0.0000
error cells 0 | postflight failures 0
SAVED
```

Thirty-one postflight assertions, all green. Zero error cells. The close held to the cent. Every
gate the project had said this build was correct.

The mechanism was completely dead.

The new columns had been created by inserting columns next to a text column, so they inherited
its `@` (Text) number format. Assigning `Range.Formula = "=IFERROR(LN(1+F7),0)"` to a
Text-formatted cell stores **the string**. `HasFormula` came back `False`. Reading the cell
returned `'=IFERROR(LN(1+F7),0)'`. Every consumer treated it as zero.

It was found by typing one activity name into the sheet the way the owner would, and watching
the factor sit at 1.0000 when it should have gone to 1.3000.

## Why the gate could not see it

The build was correct *to assert* nothing had moved — no initiative had been assigned yet, so
every factor should read 1.00 and the close should hold. And the spec did assert a computed
cell, not just a written one:

```json
{"cell": "D20", "must_equal": 1.0, "why": "no activity named yet, so the factor is 1.00"}
```

That assertion passed. `EXP(SUMIFS(...))` over a range of text cells returns `EXP(0)` = **1.0**.
The right answer, produced by the wrong machine.

**This is the trap: when the expected state is "unchanged", every static assertion is degenerate.**
1.00, 0.00 and "the close held" are exactly what a dead mechanism also produces. You have not
tested anything. You have confirmed that nothing happened, which was never in doubt.

## The rule

Any change whose purpose is to make something **respond** gets a behavioural probe before deploy,
on a throwaway copy:

1. Copy the built artifact to a scratch name.
2. Set the input the way a user would — type into the cell, flip the flag, change the rate.
3. Recalculate.
4. Assert the output **changed**, and changed by the amount you can compute independently.
5. Throw the copy away. It never goes near the live file.

If you cannot describe an input that should move an output, you have not built a mechanism —
you have built a decoration, and should say so.

## Assert values only live arithmetic can produce

Where a probe is too heavy, at least choose assertion targets that a dead cell cannot fake:

```json
{"cell": "G3", "must_equal": 0.19312,  "why": "ln(1 + 21.3%) - only live arithmetic makes this"}
{"cell": "G7", "must_equal": 0.26236,  "why": "ln(1 + 30%)"}
```

An irrational-looking number is a fingerprint. `1.0`, `0.0` and `#,##0` round figures are not.
Prefer a cell whose correct value is *specific and derived* over one whose correct value is a
constant you would also get from silence.

## The probe is also the demo

The same script that proves the mechanism works produces the table the owner wants to see:

```
typed 'B2B Picking' into CI!E7 (INI-13, +30%, live Jul-26)
                              before        after       move
CI factor                     1.0000       1.3000     0.3000
productivity                  180.00       234.00      54.00
hours                       1,075.25       827.12    -248.13
```

Never write a probe that only prints PASS. Print the before, the after and the movement, so the
run doubles as the evidence you hand over.

## Companion checks worth stealing

- **Independent recomputation.** Compute the expected answer in the host language from first
  principles and compare, rather than reading it back from the artifact. A harmonic productivity
  blend was verified this way: sheet `1.670475`, Python `1.670475`, difference `0.00e+00`. The
  sheet agreeing with itself would have proved nothing.
- **A round trip that must reproduce.** When seeding a derived input (heads = hours ÷ hours-per-head)
  and then recomputing the original from it, the invariant is that the source value returns
  unchanged. Any drift is a defect, and adjusting the seed to hide it is tuning inputs to hit a
  target.
- **Ask what would have to be true for this check to pass while the feature is broken.** If you
  can answer that question, the check is not a check.
