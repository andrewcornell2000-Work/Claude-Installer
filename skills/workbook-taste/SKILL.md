---
name: workbook-taste
description: >
  The owner's workbook design rules plus the verification gates that catch presentation errors
  numbers-gates cannot. Use whenever building, restructuring, styling, or reviewing an Excel
  workbook or any human-facing spreadsheet deliverable - BEFORE writing layout specs, when
  briefing agents to design sheets, and ALWAYS before declaring presentation work done. Trigger
  on: sheet redesign, assumptions/inputs sheets, formatting passes, "make it readable",
  "too cluttered", label sweeps, or any moment output is about to ship without having been
  looked at.
---

# Workbook taste — rules learned from shipped mistakes (2026-08-04)

## The one meta-rule: LOOK AT THE OUTPUT

Every numeric gate passed while the owner opened the file and found six visual failures in
minutes. Numbers-gates (close ties, recalc identity, error sweeps) verify arithmetic; they say
NOTHING about what a human sees. Before calling any presentation work done:

1. Render it: export the sheet region to an image (Excel COM `Range.CopyPicture` + paste to a
   chart export, or open + screenshot) and actually inspect it, or dump a faithful text grid and
   read every row like a reviewer would.
2. Walk it as the owner: top to bottom of every changed sheet asking "would a finance director
   know what this row is, where this section starts, and why this cell is coloured?"
3. A fresh-eyes register sweep on the FINAL state - not a list built from an earlier state.
   Slop reappears: memos, owner-ruling citations, build vocabulary, bracketed system tags.

## Placement rules (the Test Variable principle)

- **Inputs live on the sheet that uses them.** Rates on the revenue sheet (year-stepped as
  columns per rate line if needed). KPIs/productivity as visible rows in the cost calc itself -
  the reader should see volume / rate / hours / cost in one place.
- **An assumptions sheet holds ONLY what would clutter the working sheets**: shared volume
  forecasts (one row per channel, months across columns), month/calendar machinery, wage
  build-ups, cross-sheet boundaries. Target size: small enough to scan in one screen-scroll.
  If a scalar is consumed by exactly one formula on one sheet, it belongs near that formula or
  hard-coded with a label - two rows for a start month and end month of one adjustment is
  clutter, not structure.
- **No channel/system splits the owner didn't ask for.** One task list per site. Provenance
  tags (DLP rows, engine names, channel brackets) go to a far-right basis column or die.

## Decimal places — by what the number IS (owner's rule, 2026-08-06)

> "i never want a number to go deeper than 1 decimal unless its a rate"

| type | decimals | format |
|---|---|---|
| FTE, headcount | 0 | `#,##0` |
| cost, revenue | 0 | `#,##0_);[Red](#,##0)` |
| hours, volumes, counts | 0 | `#,##0` |
| percentages | 1 | `0.0%` |
| dollar rates ($/hr, $/unit) | 2 | `0.00` or `"$"#,##0.00` |
| factors, indices, ratios | 2 | `0.00` |
| productivity rates (units/hr) | 0 | `#,##0` — a labour plan says 170, not 170.40 |

Applying this by scanning is the only sane way, but **a label-based classifier is dangerous**.
"Truganina | B2B Picking" is a productivity *factor* on one sheet and a *volume* on another; a
generic rule rounded the factor grid to `1` and the revenue rate card to whole dollars, and both
would have shipped. Two guards that make the scan safe:

- **Only rewrite formats with three or more decimals outright.** A `0.00` is already compliant if
  the number is a rate, and you usually cannot tell from the label whether it is.
- **Touch 2-decimal formats only on an explicit, hand-verified allow-list of money rows.**
- **Skip sheets whose formats were set deliberately** by an earlier spec, and any sheet the owner
  maintains.

## Total rows — the gap-and-fill contract (owner's rule, 2026-08-06)

Measured off the owner's own hand-fix, not invented:

- A gap row directly above the total: **row height 5.1**, no fill, no borders.
- The total row: fill **theme3 tint 0.75 = `#A6CAEC`**, **bold**, indent 1 in column A.
  Apply the *theme* fill, not the literal hex, so it tracks the workbook theme.
- **The label stops at the word TOTAL.** "TOTAL - fixed heads per day" becomes "TOTAL" — the
  section header above and the UoM column beside it already say what it is.
- Exception, and ask rather than assume: a line that names a **site** or that shares a block with
  a second total keeps its name (`SITE TOTAL - DERRIMUT`, `TOTAL - returns received`). Stripping
  those makes two rows in one block both read "TOTAL", which is the opposite of the point.
- `#83B5E4` is the **headline** fill (a sheet's grand total, a two-site summary). `#A6CAEC` is the
  **section subtotal**. Using the headline colour for a section total is the usual mistake.

`clear` removes CONTENTS, not FORMATTING. After emptying a block, explicitly reset borders, fill,
font colour, bold, italic and indent before restyling — otherwise the old grey box, the old bold
and brown label text all survive on cells you believe are blank.

## Styling rules

- **Read the theme, never invent colours.** Pull the workbook's theme palette (dk2/accent
  colours) or copy formats from an existing well-styled sheet. Foreign hex values look wrong
  immediately.
- **ALL-CAPS is not a banner test.** GL account names, acronyms, and code-bearing labels are
  ALL-CAPS. Banners are identified by role (section starts, known list) - never by casing.
- **Sections read as sections**: header row with fill + border, blank row after the section's
  last data row, indent hierarchy in the label column, subtotals bordered. Uniform column-A
  text with no spacing is the failure mode.
- **Outline groups must be re-derived after any row restructure.** A subtotal must sit at its
  group boundary with every feeding row inside the group - stale groups mislead expand/collapse
  users into thinking totals are wrong.

## Briefing agents

- Include the placement rules verbatim in any sheet-design brief. An agent briefed to
  "catalogue every input" builds a hoarder sheet; brief it to MINIMISE the assumptions surface
  and justify every row's existence ("what breaks if this moves onto the consuming sheet?").
- Ban memo/meta rows in the brief: no owner-ruling citations, no dropped-items memos, no
  session vocabulary anywhere in a cell.
- After any agent-produced layout lands, run the LOOK AT THE OUTPUT gate personally.

## Working style

- Fix root causes, not instances: a bad heuristic (ALL-CAPS banners) fixed at one row will
  misfire elsewhere - fix the classifier.
- When the owner supplies an example sheet, treat it as the styling and placement CONTRACT,
  re-read it before each design decision, and diff your output against it before shipping.
