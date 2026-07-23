# Product

## Platform

web

## Users

Broader BEAM developers: Erlang and Elixir engineers curious about Gleam, alongside Gleam developers, who need persistent key-value storage without adding a database dependency. They arrive evaluating whether slate fits their project or mid-task looking up a table type, an error, or a limitation. The site should read well for people who know OTP but may be new to Gleam idioms.

## Product Purpose

The documentation site for slate, a type-safe Gleam wrapper for Erlang DETS, at slate.tylerbutler.com. It exists to get visitors from "I need persistence" to a working table as quickly as possible. Success is adoption: visitors run `gleam add slate` and reach first success fast — Hex downloads and GitHub stars are the signal.

## Positioning

Persistence in the gap between "serialize to a file" and "add a database" — key lookup and folds, built into OTP, zero external dependencies.

## Brand Personality

Calm, precise, trustworthy. Quiet confidence, like well-maintained infrastructure: the site's job is comprehension, not persuasion. The reference feel is the Gleam ecosystem's own documentation — it should sit naturally in that community.

## Anti-references

- SaaS marketing gloss: gradient heroes, metric cards, testimonial walls — startup landing-page grammar on a library site.
- Dry auto-generated docs: bare hexdocs/javadoc energy — technically complete but unwelcoming, with no guidance layer.

## Design Principles

- **Fastest path to a working table.** Every page should shorten the distance from arrival to `gleam add slate` and a first successful lookup. Code first, prose second.
- **Assume BEAM, teach Gleam.** Readers know OTP; they may not know Gleam. Lean on DETS/OTP familiarity, explain Gleam idioms where they appear.
- **Docs are the product.** Design serves reading and comprehension. The splash page is a doorway into the docs, not a pitch.
- **Honest about limits.** Surfacing DETS's constraints (2 GB cap, no ordered_set, disk I/O) plainly is what makes the library feel safe to depend on.

## Accessibility & Inclusion

WCAG AA baseline: ≥4.5:1 body text contrast in both light and dark themes, full keyboard navigation, and reduced-motion alternatives for any animation.
