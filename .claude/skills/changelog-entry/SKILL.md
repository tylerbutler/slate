---
name: changelog-entry
description: Use after completing user-facing changes to create a Trellis TOML changelog entry in .changes/unreleased/. Skip contributor-only changes; otherwise infer the kind and body, confirm with the user, then run trellis changelog new.
---

# Changelog entry

1. Review this session's changes with `git --no-pager diff` and the conversation.
   Keep unrelated work out of the entry. Stop without creating an entry if
   the change only affects contributor tooling, CI, or internal documentation.
2. Choose a kind and draft the body.
3. Use `ask_user` to confirm the kind and body. Revise if requested.
4. Create the entry with `trellis changelog new --kind <kind> --body <body>`,
   or `just change <kind> <body>`. Quote the body as one shell argument.
5. Read the generated TOML file and run `trellis version plan` to confirm
   that the entry parses and gives the expected bump.

## Kind

Use the kinds configured in `[tools.trellis.changelog]` in `gleam.toml`:

| Kind | When to use | Version bump |
| --- | --- | --- |
| Breaking | Incompatible public API changes | major |
| Added | New features or public API | minor |
| Changed | Non-breaking user-facing behavior changes | patch |
| Deprecated | Features marked for future removal | patch |
| Fixed | Bug fixes | patch |
| Performance | Performance improvements | patch |
| Removed | Removals that do not break the public API | patch |
| Reverted | Reverted changes | patch |
| Dependencies | Dependency updates | patch |
| Security | Security fixes | patch |

## Body

Use a summary sentence as the first line. Add a blank line before details,
migration notes, or examples. Use past tense or present-effect tense:
"Added batch insert support" or "`with_table` now closes on exception."
For Breaking entries, include before/after Gleam examples.

## Format

Trellis writes `.changes/unreleased/slate-<body-slug>.toml`. It selects the
package because `slate` is the only releasable member. There is no timestamp.

```toml
package = "slate"
kind = "Fixed"
body = """
`with_table` now closes the table when the callback raises.

Previously, a callback exception could leave the table open."""
```

Keep one entry per logical user-facing change. Missing-entry reminders in CI
are advisory; they do not make contributor-only changes need release notes.
Do not edit `CHANGELOG.md` to add entries:
Trellis generates it from the version sections in `.changes/slate/` when
it updates the release PR.
