---
name: changelog-entry
description: Use after completing code changes to create a changie changelog entry in .changes/unreleased/. Infers the change kind and body from the current session's work, confirms with the user, then writes the YAML file directly.
---

<required>
*CRITICAL* Add the following steps to your Todo list using TodoWrite:

1. Review changes made in this session
2. Infer changelog kind and draft body
3. Confirm kind and body with the user
4. Write the changelog YAML file to `.changes/unreleased/`
5. Verify the file was created correctly
</required>

# Overview

This skill creates changelog entries for the slate project using the [changie](https://changie.dev/) format. Instead of running the interactive `changie new` command, you write the YAML file directly to `.changes/unreleased/`.

# Step-by-Step Process

## 1. Review changes made in this session

Run `git --no-pager diff --stat` and `git --no-pager diff` (or `git --no-pager diff --cached` for staged changes) to understand what changed. Also review any context from the current conversation about what was implemented.

## 2. Infer the changelog kind and draft the body

Pick exactly **one** kind from this list:

| Kind           | When to use                                | Version bump |
|----------------|--------------------------------------------|--------------|
| **Breaking**   | Public API changed in incompatible ways    | minor        |
| **Added**      | New features or public API surface         | minor        |
| **Changed**    | Non-breaking changes to existing behavior  | patch        |
| **Deprecated** | Features marked for future removal         | patch        |
| **Fixed**      | Bug fixes                                  | patch        |
| **Performance**| Performance improvements                   | patch        |
| **Removed**    | Removed features or API surface            | patch        |
| **Reverted**   | Reverted a previous change                 | patch        |
| **Dependencies** | Dependency updates                       | patch        |
| **Security**   | Security-related fixes                     | patch        |

Draft the body following these conventions:

- **First line**: A concise summary sentence describing the change. This becomes the entry title.
- **Remaining lines** (optional): A longer explanation, migration notes, or before/after code examples.
- Use Gleam fenced code blocks (` ```gleam `) for code examples when showing API changes.
- For **Breaking** changes, always include before/after code examples showing the migration path.
- Write in past tense or present-effect tense (e.g., "Added batch insert support" or "`with_table` now closes on exception").

## 3. Confirm with the user

Use the `ask_user` tool to present the inferred kind and drafted body. Ask the user to confirm or adjust. Example:

> I'd like to create this changelog entry:
>
> **Kind:** Fixed
>
> **Body:**
> ```
> `with_table/3` now closes the table handle when the callback throws an exception.
>
> Previously, if the user-supplied callback raised an exception, the DETS table
> handle would be left open. The table is now closed in all cases.
> ```
>
> Does this look correct?

If the user wants changes, revise and confirm again.

## 4. Write the changelog YAML file

Generate a timestamp and write the file to `.changes/unreleased/`.

**Filename format:** `{Kind}-{YYYYMMDD}-{HHMMSS}.yaml`

Generate the timestamp by running:

```bash
date -u +"%Y%m%d-%H%M%S"
```

Use the output to construct the filename. For example, if the kind is `Fixed` and the timestamp is `20260328-041500`, the file is:

```
.changes/unreleased/Fixed-20260328-041500.yaml
```

**File format:**

```yaml
kind: {Kind}
body: |-
    {first line of body}

    {remaining lines of body, preserving blank lines and indentation}
time: {ISO 8601 timestamp with timezone}
```

Generate the ISO 8601 timestamp by running:

```bash
date -u +"%Y-%m-%dT%H:%M:%S.000000+00:00"
```

**Important YAML rules:**
- Use `body: |-` (literal block scalar, strip final newline)
- Indent every line of the body by exactly 4 spaces
- Preserve blank lines within the body (they become empty lines in the block scalar)
- The `time` field uses full ISO 8601 with microsecond precision and timezone offset

## 5. Verify the file

After writing, run:

```bash
cat .changes/unreleased/{filename}
```

Confirm the YAML is valid and the content matches what the user approved.

# Example Entry

```yaml
kind: Fixed
body: |-
    `with_table/3` now closes the table handle when the callback throws an exception.

    Previously, if the user-supplied callback raised an exception, the DETS table
    handle would be left open. The table is now closed in all cases, including
    when the callback throws.
time: 2026-03-22T00:00:00.000000+00:00
```

# Notes

- Only create **one** changelog entry per logical change. If a session includes multiple unrelated changes, create separate entries for each.
- The `.changes/unreleased/` directory must already exist. If it doesn't, create it.
- CI checks for changelog entries on PRs, so every user-facing change needs one.
- Do **not** modify `CHANGELOG.md` directly — it is generated by `changie merge`.
