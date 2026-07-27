---
target: / (splash page, index.mdx)
total_score: 29
p0_count: 0
p1_count: 3
timestamp: 2026-07-20T05-45-50Z
slug: website-src-content-docs-index-mdx
---
Method: dual-agent (A: design-review fork · B: detector-evidence fork)

Provenance note: assessments ran in parallel isolated agents against `astro preview` of the current build (new typography included). One cross-contamination incident: Assessment B's overlay banner appeared in one of Assessment A's dark-mode screenshots (shared browser instance); A's findings were established from source + computed styles before the banner appeared and its report disregarded the overlay content.

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Active nav/search states fine; hover prefetch on |
| 2 | Match System / Real World | 3 | Double parenthetical jargon in hero tagline |
| 3 | User Control and Freedom | 3 | Standard Starlight nav/search/theme toggle; nothing traps |
| 4 | Consistency and Standards | 2 | Pink chalk logo/hero art vs blue system; multicolor icon chips break the One Stone Rule |
| 5 | Error Prevention | 3 | Links validated at build |
| 6 | Recognition Rather Than Recall | 3 | No code preview — evaluators must click through to learn the API's shape |
| 7 | Flexibility and Efficiency | 3 | Ctrl+K search, prefetch, llms.txt |
| 8 | Aesthetic and Minimalist Design | 2 | Generic four-card Features grid, meaningless icons, tagline duplicates meta description |
| 9 | Error Recovery | 3 | n/a for content; console 404s invisible to users |
| 10 | Help and Documentation | 4 | The site is docs; clear routes to quick-start/guides |
| **Total** | | **29/40** | **Good — solid foundation, address weak areas** |

## Anti-Patterns Verdict

Borderline — the tells are present but half-dead. The composition is Starlight-default grammar: hero + tagline + "Features" + four identical icon/heading/text cards with semantically arbitrary icons (rocket = Set Tables, gear = Persistent Storage).

Where the two assessments converge with a twist: the in-page detector flagged `gradient-text` on the splash heading (`#_top`) as the page's one true anti-pattern hit, and the design review independently found the same block — but proved it is **dead code**. The inline `<style>` at `index.mdx:23-32` opens with a `//` comment, which is invalid CSS, so the browser drops the whole rule and renders the heading solid. The banned pattern exists in source intent only.

Deterministic scan: CLI `detect.mjs` on `index.mdx` returned clean (exit 0) — a parser blind spot, since the CSS lives inside an MDX/JSX template literal. The in-page detector (injected via live-server on :8400, since stopped) reported: 1 anti-pattern — `gradient-text`; plus informational `single-font` (false positive: one family in weights is the deliberate Two Voices strategy). Detector evidence beat the CLI here; both agents' evidence agreed on the location.

Incidental browser evidence: two real 404s fire on every page load — the favicon (`/src/assets/favicon%20small.png`, the space-named unprocessed asset from `astro.config.mjs:30`) and the tinylytics embed (`tinylytics.app/embed/2kPzGJW6u9gfLugBcmUE/min.js`), meaning analytics is silently dead if that embed ID is wrong in production.

## Overall Impression

A disciplined tonal system wearing a template's clothes. The ramp, contrast, and new typography are genuinely strong — but the splash answers none of an evaluator's three questions (how does it look in code, when should I use DETS, what are the limits), all of which the README already answers. The single biggest opportunity: put a typed code sample and `gleam add slate` on the front door.

## What's Working

1. **Contrast discipline is measured, not aspirational.** Tagline `#244a63` on white ≈ 9.4:1; dark tagline `#a0bdd0` on `#0a1520` ≈ 9.3:1; primary button ≈ 5.6:1. AA passes everywhere sampled, both themes.
2. **The ramp holds.** Every computed surface/text color maps to a DESIGN.md token; light and dark read as two lighting conditions on one material.
3. **The new typography is live.** Schibsted Grotesk on headings/body, Spline Sans Mono confirmed on code blocks; the site already feels less generic.

## Priority Issues

1. **[P1] No code, no install command, on the splash of a code library.** PRODUCT.md principle #1 is "fastest path to a working table — code first, prose second"; the splash has zero code and never says `gleam add slate`. Fix: compact typed example (open → insert → lookup) plus the install one-liner. Command: /impeccable polish.
2. **[P1] Favicon 404.** `astro.config.mjs:30` points at `./src/assets/favicon small.png`, emitted as a literal unprocessed path that 404s. Fix: serve a properly processed/renamed favicon and verify the link resolves. Command: /impeccable polish.
3. **[P1] The identical four-card grid with arbitrary icons.** Banned scaffold; muddled IA — three cards are a real taxonomy (table types), "Persistent Storage" is a property of all three, not a peer. Fix: one deliberate "three table types" group plus a distinct positioning strip — ideally the README's JSON/DETS/SQLite/Mnesia comparison table. Command: /impeccable polish or /impeccable layout.
4. **[P2] Dead gradient-text CSS block.** `index.mdx:23-32` — invalid `//` comment kills the rule; also the banned pattern DESIGN.md prohibits. Fix: delete the block. Command: /impeccable polish.
5. **[P2] Identity clash: pink chalk art vs blue system.** Header logo illegible at 48px; hero art has baked-in text with empty alt. Fix short-term: meaningful alt, accept the art as deliberate contrast; long-term: decide whether pink joins the palette or the mark moves toward the ramp. Command: design decision, then /impeccable polish.

## Persona Red Flags

**Jordan (first-timer):** "Duplicate Bag Tables" is undefined jargon at first contact; the tagline's two parentheticals demand translation; icons carry zero meaning. The "What is slate?" secondary CTA rescues them.

**Riley (stress tester):** two 404s on every page load (favicon, tinylytics); authored-but-inert CSS is exactly the promise-vs-reality gap Riley documents; theme toggle held up under forced switching.

**Priya (evaluating BEAM developer, project persona):** lands with three questions — code shape, when to use DETS, limits — and the splash answers none; the README answers all three. The site's front door is weaker than the repo's README, inverting "docs are the product."

## Minor Observations

- Hero image fixed 320×320 even at 1280px; "Features" pushed below the fold.
- Tagline is identical to the meta description; the positioning line ("the gap between a file and a database") appears nowhere on the page.
- "Features" is filler; the section is really "Table types."
- `Last updated` + "Edit page" footer is docs chrome leaking onto a landing surface; Starlight can disable both per-page.
- Buttons ~40px tall on mobile, just under the 44px touch target.

## Questions to Consider

1. What if the chalkboard art moved to a smaller "about the project" moment and the hero's right column became the typed code sample — the artifact that proves "type-safe" instead of asserting it?
2. The README's comparison table is the sharpest positioning device the project owns. Why isn't it the splash's second section?
3. If the page ended with a copyable `gleam add slate` — the peak at the end — would anything else need to persuade?
