---
target: / (splash page, index.mdx) — post-restructure
total_score: 33
p0_count: 0
p1_count: 1
timestamp: 2026-07-20T06-21-55Z
slug: website-src-content-docs-index-mdx
---
Method: dual-agent (A: design-review fork · B: detector-evidence fork), round 2 after splash restructure

Provenance: isolated parallel agents against `astro preview` of the current build. A's tab was closed mid-run by the other assessment's browser activity; it recreated the tab and re-measured, and no overlay content influenced judgment.

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Unchanged; nav/search states fine |
| 2 | Match System / Real World | 4 | Tagline is plain-language positioning; LinkCards define jargon inline |
| 3 | User Control and Freedom | 3 | Standard Starlight controls |
| 4 | Consistency and Standards | 3 | Pink art clash (open decision); dark LinkCard descriptions use Weathered #6a93ad against DESIGN.md's rule |
| 5 | Error Prevention | 3 | Links build-validated |
| 6 | Recognition Rather Than Recall | 4 | The API's shape is visible on arrival |
| 7 | Flexibility and Efficiency | 3 | Ctrl+K, prefetch, llms.txt |
| 8 | Aesthetic and Minimalist Design | 3 | Grid scaffold gone; held back by line length, table dead-space, orphan card |
| 9 | Error Recovery | 3 | n/a for content |
| 10 | Help and Documentation | 4 | Limitations + Quick Start surfaced from the splash |
| **Total** | | **33/40** | **Good — up from 29/40** |

## Anti-Patterns Verdict

Passes. The composition is no longer guessable from "docs site template": code → comparison table → typed navigation cards → install is content-driven structure. Round 1's banned patterns are verified gone in both assessments: CLI scan clean AND the in-page detector reports no gradient-text (the file no longer contains any style block), no icon-card grid, h1 renders solid.

The one convergent new finding: **line length**. The in-page detector flagged all 5 prose paragraphs at ~135 chars/line (~1080px column at 1280px viewport); Assessment A independently identified the same root cause — `template: splash` sets `.sl-markdown-content` to `max-width: none`. Perfect agreement, one fix.

Browser evidence: favicon now 200; the only failing request is the tinylytics embed 404 (kept by user decision). The pink chalk art vs blue system reads as human quirk, not AI grammar.

## Overall Impression

The page now earns its structure: arrival proves the API with real typed Gleam, the comparison table answers "when," LinkCards define the taxonomy, and the exit hands over `gleam add slate`. What remains is one systemic width problem (the splash template's unconstrained column) that causes three of the five findings, plus two one-line token nits.

## What's Working

1. The code-first section: correct idiomatic Gleam in 14 lines, Expressive Code highlighting on ramp surfaces, claim demonstrated not asserted.
2. Peak-end structure: proof on arrival, install command at exit.
3. Ramp discipline extends to the new components — all AA (body 9.4:1 both themes, card descriptions 5.6–5.7:1).

## Priority Issues

1. **[P1] Unconstrained line length.** `template: splash` gives `.sl-markdown-content` `max-width: none`; prose runs ~135ch (cap is 65–75ch). All five paragraphs affected (detector + review agree). Fix: cap prose width on the splash in `custom.css`.
2. **[P2] Comparison-table dead space at desktop.** ~480px table in a 1080px column; falls out of the width fix or `width: 100%` on the table.
3. **[P2] Orphan third LinkCard.** CardGrid is 2-up, so "Duplicate bag tables" dangles. Fix: 3-across ≥72rem, or stack all three full-width.
4. **[P2] Dark-mode LinkCard descriptions use Weathered (#6a93ad).** Passes AA (5.6:1) but violates DESIGN.md's "never Weathered for body copy" rule. Fix: bump to gray-2.
5. **[P3] Install terminal frame vacancy** — full-width frame for a 15-char command; largely resolved by the column fix.

## Persona Red Flags

**Jordan (first-timer):** table types now define themselves; remaining gap is the unexplained `let assert Ok(...)` idiom — one inline comment would close it.
**Riley (stress tester):** no broken promises found this round; only the deliberate tinylytics 404 remains.
**Priya (evaluating BEAM dev):** all three arrival questions answered on the splash; last trust gap is no stability/versioning signal on the front door.

## Minor Observations

- Mobile h1 (29px) whispers under the 251px wordmark art; borderline acceptable.
- All four h2s identical 35px; rhythm carried by content variety.
- Hero art now 381px at desktop and balanced against the text column.

## Questions to Consider

1. If the whole splash column were capped at ~72ch and centered, the four sections would read as one stream — is full-bleed width doing anything for anyone here?
2. Should the code sample teach `let assert` in one comment, given the audience knows OTP but maybe not Gleam?
3. The Stability & Versioning page is the evaluator's final trust gate — why isn't it one line on the splash?
