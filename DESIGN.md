---
name: slate
description: Documentation site for slate, a type-safe Gleam wrapper for Erlang DETS.
colors:
  quarry-blue: "#4a8eb8"
  quarry-deep: "#2a6d96"
  sky-etch: "#a8cde0"
  chalk-pink: "#ff6ea2"
  deep-chalk: "#aa0e44"
  ink-slate: "#0a1520"
  strata: "#152d40"
  bedrock: "#244a63"
  seam: "#3d6b8a"
  weathered: "#6a93ad"
  haze: "#a0bdd0"
  mist: "#dce8f0"
  frost: "#eef4f8"
  paper-white: "#ffffff"
typography:
  headline:
    fontFamily: "Schibsted Grotesk, sans-serif"
    fontSize: "2.25rem"
    fontWeight: 600
    lineHeight: 1.2
  title:
    fontFamily: "Schibsted Grotesk, sans-serif"
    fontSize: "1.5rem"
    fontWeight: 600
    lineHeight: 1.3
  body:
    fontFamily: "Schibsted Grotesk, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.75
  label:
    fontFamily: "Schibsted Grotesk, sans-serif"
    fontSize: "0.875rem"
    fontWeight: 600
    lineHeight: 1.4
  code:
    fontFamily: "Spline Sans Mono, ui-monospace, monospace"
    fontSize: "0.9375rem"
    fontWeight: 400
    lineHeight: 1.65
components:
  button-primary:
    backgroundColor: "{colors.quarry-blue}"
    textColor: "{colors.ink-slate}"
    typography: "{typography.label}"
  button-secondary:
    backgroundColor: "{colors.strata}"
    textColor: "{colors.mist}"
    typography: "{typography.label}"
---

# Design System: slate

## 1. Overview

**Creative North Star: "The Slate Ledger"**

Durable records on stone. The site treats documentation the way DETS treats data: written down plainly, safe to depend on, still there after a restart. The mineral blue-gray palette is literal slate — every neutral in the system is a tonal step quarried from the same blue hue, so light and dark modes read as two lighting conditions on the same material rather than two themes. Nothing glows, nothing floats; content is inscribed on flat tonal surfaces.

This is a product-register system built on Astro Starlight: the framework's reading conventions (sidebar navigation, content column, table of contents) are kept, and identity is carried entirely by the palette, the type voice, and restraint. The system explicitly rejects SaaS marketing gloss — gradient heroes, metric cards, testimonial walls — and equally rejects the dry auto-generated-docs look: the guidance layer, honest warnings, and comparison tables are the warmth.

**Key Characteristics:**
- One blue-gray mineral ramp supplies every neutral; no true grays exist in the system.
- Flat and tonal: depth comes from lightness steps, never from shadows.
- One typeface (Schibsted Grotesk) does all prose and UI work; Spline Sans Mono does all code.
- Starlight conventions are load-bearing; custom styling is confined to tokens.
- One deliberate second hue — chalk pink, drawn from the logo itself — marks the brand's own signature (the mark, the splash title) and nowhere else; blue remains the only interactive accent.

## 2. Colors: The Slate Ledger Palette

A single blue-gray hue family stepped from near-black ink to frost, with one saturated blue accent — the whole palette is cut from one stone.

### Primary
- **Quarried Blue** (#4a8eb8): the accent in dark mode — links, primary actions, current-selection markers. Saturated enough to read as "interactive" against the ink surfaces, never used decoratively.
- **Deep Quarry** (#2a6d96): the same accent cut deeper for light mode, keeping link and action contrast at AA on white.
- **Sky Etch** (#a8cde0): high-accent tint; hover/emphasis states on dark surfaces and the light-mode accent wash's counterpart.

### Signature Accent
- **Chalk Pink** (#ff6ea2): the exact pink pulled from the hand-drawn "slate" wordmark in the logo. Dark-mode value; marks the brand's own signature and nothing else — the logo, the header wordmark, and the splash page's `<h1>`.
- **Deep Chalk** (#aa0e44): the same chalk hue cut deeper for light mode, keeping the splash title at AA contrast on Paper White — the same relationship Deep Quarry has to Quarried Blue.

Chalk is not a second interactive accent and not a neutral; it is a one-hue signature, used in exactly the two places named above and nowhere in the reading surface, UI chrome, or semantic states. See the Chalk Signature Rule below.

### Neutral
- **Slate Ink** (#0a1520): page background in dark mode; body text color in light mode. The system's true black.
- **Strata** (#152d40) and **Bedrock** (#244a63): raised tonal panels, code-block backgrounds, borders on dark surfaces.
- **Seam** (#3d6b8a) and **Weathered** (#6a93ad): mid-tones for dividers and de-emphasized UI; never used for body text on tinted backgrounds.
- **Haze** (#a0bdd0) and **Mist** (#dce8f0): secondary and primary text on dark surfaces; panel tints in light mode.
- **Frost** (#eef4f8) and **Paper White** (#ffffff): light-mode panel and page backgrounds.

### Named Rules (optional, powerful)
**The One Stone Rule.** Every neutral is a lightness step of the same blue-gray hue. Introducing a warm gray, a pure gray, or an interactive accent hue beyond Quarried Blue is forbidden — if a new neutral is needed, quarry it from the existing ramp. Chalk Pink is the one named exception to "second accent hue," and it is bounded by the Chalk Signature Rule below, not a loophole for others.

**The Working Accent Rule.** Quarried Blue appears only where something is interactive or current (links, actions, active nav). It is never a decoration, a background wash for emphasis, or a heading color — chalk fills the "signature heading" role instead, precisely because chalk is never interactive.

**The Chalk Signature Rule.** Chalk Pink/Deep Chalk appears in exactly two places: the brand mark itself (logo and header wordmark) and the splash page's own `<h1>`. It never appears on links, buttons, active states, semantic status, body prose, or any other heading — those stay inside the blue-gray ramp. One signature, spent deliberately, is worth more than a tint scattered for warmth.

## 3. Typography

**Body/UI Font:** Schibsted Grotesk (with sans-serif fallback)
**Code Font:** Spline Sans Mono (with ui-monospace fallback)

**Character:** Editorial precision with warmth — Schibsted Grotesk's angled terminals and open counters give the prose a distinct voice without display flourish, and Spline Sans Mono shares its humanist skeleton so code blocks feel like part of the same document, not an embedded terminal.

### Hierarchy
- **Headline** (600, 2.25rem, 1.2): page titles. One per page.
- **Title** (600, 1.5rem–1.875rem, 1.3): section headings within docs pages.
- **Body** (400, 1rem, 1.75): all prose, capped by Starlight's content column (~65–75ch).
- **Label** (600, 0.875rem, 1.4): sidebar navigation, buttons, table headers.
- **Code** (400, 0.9375rem, 1.65): code blocks and inline code, always Spline Sans Mono.

### Named Rules (optional)
**The Two Voices Rule.** Schibsted Grotesk speaks; Spline Sans Mono quotes code. No third family, no display font, no weight above 700.

## 4. Elevation

Flat and tonal, with no shadow vocabulary. Depth is conveyed exclusively by stepping through the mineral ramp: the page sits on Slate Ink (dark) or Paper White (light), panels and code blocks sit one tonal step away (Strata / Frost), and borders use the adjacent step. If a surface needs to feel raised, move it one step lighter (dark mode) or add a 1px ramp-tone border — never a box-shadow.

### Named Rules (optional)
**The Inscription Rule.** Nothing floats above the stone. Dropdowns and dialogs may use Starlight's defaults, but authored surfaces never add shadows, glows, or blurs.

## 5. Components

The component vocabulary is Starlight's, themed by tokens. Custom components are the exception and must adopt these assignments.

### Buttons
- **Shape:** Starlight's large-radius action pill (999px).
- **Primary:** Quarried Blue background with Slate Ink text (dark mode); Deep Quarry with white text (light mode). Label typography, 600 weight.
- **Hover / Focus:** tonal shift within the accent (toward Sky Etch), visible focus ring from Starlight defaults; no transform, no shadow.
- **Secondary:** minimal — Strata/Mist tonal treatment, same shape as primary.

### Cards / Containers
- **Corner Style:** Starlight card default (subtle radius).
- **Background:** one tonal step off the page (Strata on dark, Frost on light).
- **Shadow Strategy:** none — see Elevation; a 1px border in the adjacent ramp step defines the edge.
- **Internal Padding:** Starlight defaults (~1rem–1.5rem).

### Inputs / Fields
- **Style:** the search field is Starlight/Pagefind default, themed by the ramp: Strata background, Mist text, Bedrock border.
- **Focus:** accent border shift to Quarried Blue.

### Navigation
- **Sidebar:** Label typography; current page marked with accent text plus tonal background (accent-low wash), not a stripe. Hover is a tonal step, not a color change.
- **Header:** the Chalk Pink "slate" wordmark (cropped from the logo's own hand-drawn script, transparent background) replaces the plain-text site title — the one place the signature accent lives in persistent chrome. GitHub icon and theme toggle only, both in the blue-gray ramp. Mobile collapses to Starlight's drawer.

### Code Blocks (signature component)
Spline Sans Mono on a Strata surface (dark) with the ramp supplying UI chrome; Expressive Code's frame kept minimal. Code is the site's most-read content: it gets the same contrast care as prose.

## 6. Do's and Don'ts

### Do:
- **Do** keep every neutral inside the blue-gray ramp (#0a1520 → #ffffff family); quarry new values from it rather than inventing grays.
- **Do** hold body text at AA contrast or better: Mist (#dce8f0) on Slate Ink, Slate Ink on white — never Weathered (#6a93ad) for body copy.
- **Do** let Starlight's reading conventions stand; identity lives in tokens, type, and copy, not layout invention.
- **Do** treat code blocks as first-class content — Spline Sans Mono, ramp-toned surfaces, AA contrast for syntax colors.
- **Do** keep Chalk Pink confined to the brand mark and the splash `<h1>` — see the Chalk Signature Rule. Its rarity is what makes it read as a signature instead of decoration.

### Don't:
- **Don't** ship SaaS marketing gloss — gradient heroes, metric cards, testimonial walls (PRODUCT.md's own words). This includes gradient text via `background-clip: text`; the splash heading must be a single solid color (chalk pink counts as one solid color).
- **Don't** regress to dry auto-generated docs: every reference page keeps a guidance layer (when to use, honest limits), not just API listings.
- **Don't** add shadows, glows, glassmorphism, or any accent hue beyond Quarried Blue and the bounded Chalk exception above.
- **Don't** use colored side-stripe borders (border-left > 1px) for callouts; Starlight asides are themed tonally instead.
- **Don't** introduce a third font family or display type; two voices only.
