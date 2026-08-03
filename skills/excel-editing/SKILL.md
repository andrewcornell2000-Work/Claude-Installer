---
name: excel-editing
description: Use this skill for any task involving reading, writing, or formatting an Excel workbook (.xlsx, .xlsm, .csv) via the excel MCP server.
---

# Excel Editing

Reading, writing and formatting Excel workbooks through the `excel` MCP server
(`@negokaz/excel-mcp-server`). Works on files on disk — the workbook does not
need to be open in Excel.

## When to use

- Read cells, ranges, or whole sheets
- Write values or formulas
- Create Excel Tables
- Apply formatting to a range
- Copy a sheet within a workbook
- Inspect workbook structure before touching anything

## Requirements

- MCP: `excel`. Absolute file paths only — relative paths fail.
- No Excel installation needed for read/write; `excel_screen_capture` is the
  exception and needs Excel on Windows.

## The seven tools

| Tool | What it does |
|---|---|
| `excel_describe_sheets` | Sheet names, used range, tables, pivot tables, paging ranges |
| `excel_read_sheet` | Read a range; supports `showFormula` and `showStyle` |
| `excel_write_to_sheet` | Write values or formulas to a range |
| `excel_create_table` | Convert a range into an Excel Table |
| `excel_format_range` | Font, fill, border, number format |
| `excel_copy_sheet` | Duplicate a sheet inside the workbook |
| `excel_screen_capture` | Screenshot a range (Windows + Excel only) |

## Approach

1. `excel_describe_sheets` first — never guess sheet names or extents.
2. Read the **narrowest range that answers the question**. Column count is the
   cost multiplier: `A1:F500` is cheap, `A1:AC1463` is not.
3. Write with `excel_write_to_sheet`; re-read only the cells you changed.

## Paging — the main failure mode

Responses are capped at `EXCEL_MCP_PAGING_CELLS_LIMIT` cells (default 5000).
Above that, `excel_describe_sheets` returns a `pagingRanges` array and reads
come back one page at a time.

A paged read looks like a complete read. **Walk every range in `pagingRanges`
before answering**, or say explicitly that the answer covers only part of the
sheet. Silently answering from page 1 of 9 is the most common way this goes
wrong.

Budget roughly **8 tokens per cell**: a full 5000-cell page is about 40k tokens
in a single tool result. Raising the limit is almost never the right fix for a
big workbook — narrow the range, or aggregate in Python and return the summary.

## What this server cannot do

Route these elsewhere rather than hunting for a tool that does not exist:

| Need | Use instead |
|---|---|
| Charts, pivot table **creation**, insert/delete rows or columns, sort, find-and-replace | `openpyxl` in a Python script |
| VBA macros, live manipulation of an already-open workbook | `xlwings` (requires Excel running) |
| Power Query / M step inspection | Open the file in Excel, or read `xl/queries/` from the unzipped xlsx |
| Aggregating a large sheet | `pandas`, or the `duckdb` MCP over an exported CSV/Parquet |

## Safety

- Never delete or overwrite a range without user confirmation.
- Never overwrite cells containing formulas unless explicitly asked — read with
  `showFormula: true` first to find out what is there.
- Writes are not transactional. There is no undo. On a file that matters, copy
  it first.
