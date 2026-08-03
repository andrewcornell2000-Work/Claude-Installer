---
name: design-inspo
description: "Pull visual references from Andrew's design-inspo-library before designing or restyling a web UI. 114 curated plates from Awwwards, Dribbble and Land-book, tagged on three axes (category, art style, traits) plus a motion flag. Use when choosing a visual direction, matching a brief to precedent, or answering what should this look like."
---

# Design Inspo Library

A local, curated gallery of 114 web design plates (37 animated), each tagged on three
independent axes. Use it to ground a visual direction in real precedent instead of
inventing one.

## Where it lives

Cloned by Claude-Installer to `%USERPROFILE%\design-inspo-library`, or wherever
`CLAUDE_INSPO_DIR` points. If it is not there:

```bash
gh repo clone andrewcornell2000-Work/design-inspo-library "$env:USERPROFILE\design-inspo-library"
```

| Path | What it is |
|---|---|
| `library/data.json` | The catalogue. One entry per plate. Query this — it is the source of truth |
| `library/images/` | The plates (`.png` / `.jpg` / `.webp` / `.mp4`) |
| `library/index.html` | Generated gallery for human browsing. Never edit by hand |
| `TAXONOMY.md` | Full vocabulary. Read before tagging anything new |

## Querying

`data.json` is a flat array. Filter it with Python rather than reading the whole file —
it is ~43 KB and most of it is irrelevant to any one question.

```python
import json, collections
plates = json.load(open("library/data.json", encoding="utf-8"))

# Everything matching a style, in dark mode
[p["title"] for p in plates
 if "Swiss" in p["styles"] and "Dark Mode" in p["traits"]]

# What is actually available on an axis
collections.Counter(s for p in plates for s in p["styles"]).most_common()

# Dashboards specifically -- the closest category to internal tooling
[(p["title"], p["styles"], p["source"]) for p in plates if p["category"] == "Dashboard"]
```

Each entry: `id`, `filename`, `title`, `category`, `styles[]`, `traits[]`, `source`,
and `motion: true` on video plates.

To look at a plate, Read `library/images/<filename>` — stills render directly. `.mp4`
entries do not; open the gallery for those.

## Browsing visually

```bash
python -m http.server 4790
```

Then `http://localhost:4790/library/index.html`. A bare `file://` open blocks video
loading, so use the server when motion plates matter.

## The vocabulary

Filter values must come from this list. Inventing a term silently creates a permanent
bogus category, because the gallery's dropdowns are generated from the data.

**Category** (one per plate — *what the thing is*)
`Landing Page` · `Portfolio` · `Agency & Studio` · `E-commerce` · `Dashboard` ·
`SaaS Product` · `Brand Campaign` · `Type Specimen` · `Template`

**Art Style** (1–3 — *the visual language*)
`Minimalist` · `Swiss` · `Editorial` · `Brutalist` · `Maximalist` · `Collage` · `Kinetic Type` ·
`Vintage` · `Art Deco` · `Bauhaus` · `Memphis` · `Psychedelic` · `Retro-Futurism` · `Y2K` ·
`Vaporwave` · `Cyberpunk` · `Zine` · `Grunge` · `Glassmorphism` · `Claymorphism` ·
`Neumorphism` · `Skeuomorphic` · `Gradient` · `Neon` · `Duotone` · `Organic` ·
`3D Render` · `Low-Poly` · `Isometric` · `Flat Vector` · `Hand-Drawn` · `Painterly` ·
`Pixel Art` · `Dithered` · `Glitch` · `Terminal` · `Technical` · `Luxury` · `Cinematic` · `Botanical`

**Traits** (1–4 — *mode, medium, palette*)
`Light Mode` · `Dark Mode` · `Photography-Led` · `Illustration-Led` · `Type-Led` ·
`Product-Led` · `Data-Viz` · `3D` · `High Contrast` · `Monochrome` · `Colorful` ·
`Muted` · `Warm Tones` · `Cool Tones` · `Textured`

Category is *what it is*; Art Style is *how it looks*. A dark cyberpunk dashboard is
`Dashboard` + `Cyberpunk` — never `Cyberpunk` as a category.

## Using it in a design conversation

1. Translate the brief into axis terms first. "Clean internal tool" is
   `Dashboard` + `Minimalist`/`Swiss` + `Data-Viz`, not a vibe.
2. Pull 3–5 matching plates. Fewer, well-chosen references beat a wall of thumbnails.
3. Read the images. Do not describe a plate from its title — the tags are reliable,
   the titles are not descriptive.
4. Name what you are borrowing: grid, type scale, density, palette. "Like this one"
   is not a design decision.
5. Cite the `source` URL so the original is findable.

Coverage is honest but not total: `Vaporwave` and `Low-Poly` have no plates. If a brief
needs those, say so rather than forcing a weak match.

## Adding plates

Full loop is in the repo's `README.md`. Short version: write a batch JSON, run
`python library/fetch_batch.py batch.json`, **look at every image before tagging it**
(author labels are unreliable — Dribbble shots tagged "brutalism" are frequently clean
Swiss minimalism), add entries to `data.json` using only taxonomy terms, then
`python library/build.py` to regenerate the gallery.

## Provenance

Every plate is someone else's work, captured for private study, each with a `source`
back to the original. Reference and learn from it — composition, hierarchy, type scale.
Do not reproduce a plate as a deliverable or pass it off as new work.
