---
name: org-agenda
description: >-
  Read the user's org-markdown agenda (tasks, calendar, inbox) by shelling out to
  the standalone `org` CLI and interpreting its JSON. Use whenever the user asks
  what's on their agenda, what tasks/TODOs they have, what's scheduled, what's in
  their inbox/refile, or wants their org-markdown items summarized or filtered.
allowed-tools:
  - Bash(org agenda*)
  - Bash(org version)
  - Bash(./bin/org agenda*)
---

# Reading the org-markdown agenda

The `org` CLI is the single backend for org-markdown. It reads the user's markdown
files and emits a structured agenda as JSON on stdout — no Neovim required. This
skill is a thin instruction layer: run the CLI, parse the JSON, answer in prose.

## The command

```bash
org agenda --view <view_id>
```

If `org` is not on `PATH`, use the repo-local launcher `./bin/org` (requires
`luajit`). Known view ids:

- `tasks` — every heading with a TODO state (`TODO`, `IN_PROGRESS`, `WAITING`,
  `BLOCKED`, `CANCELLED`, `DONE`), grouped by source file/project.
- `calendar` — headings with a tracked date `<YYYY-MM-DD>` in the next ~10 days.
- `inbox` — open items in the refile inbox.

Exit code is non-zero with a message on **stderr** for an unknown view or a missing
`--view` flag. Surface that message to the user rather than guessing.

## The JSON shape

```jsonc
{
  "view_id": "tasks",
  "title": "Tasks",
  "groups": [
    {
      "key": "Org Markdown Project",          // group heading (source/date/etc.)
      "items": [
        {
          "title": "Convert all .org files into markdown",
          "state": "TODO",                      // may be absent for plain headings
          "priority": "A",                      // optional: A/B/C
          "date": "2026-08-20",                 // optional tracked date
          "start_time": "14:00", "end_time": "15:00", "all_day": false, // optional
          "tags": ["bug"],                       // always an array
          "source": "Org Markdown Project",
          "file": "/Users/.../index.md", "line": 35, "depth": 1,
          "children": [ /* nested items, same shape */ ]
        }
      ]
    }
  ]
}
```

`groups`, `items`, `children`, and `tags` are **always arrays** (never `{}`), so you
can iterate without null-guarding those.

## How to answer

1. Run the command for the view the user's request implies (default to `tasks`).
2. Parse stdout as JSON. Walk `groups[].items[]` (recurse into `children`).
3. Answer in the user's terms — summarize, count, filter by state/priority/tag, or
   group by file — using the fields above. Cite `file`/`line` when the user will
   want to jump to an item.
4. Do **not** hand-parse the markdown files yourself; the CLI already did the
   parsing and the JSON is the contract.

## Examples

- "What's on my plate?" → `org agenda --view tasks`, then summarize each group with
  its open-item count and call out anything `IN_PROGRESS` or priority `A`.
- "Anything scheduled this week?" → `org agenda --view calendar`, list items with
  their `date` (and `start_time` if present).
- "Clear my inbox" → `org agenda --view inbox`, enumerate items so the user can act.

This skill is **read-only**. There is no CLI command yet to create, complete, or
refile items — if the user asks to change something, tell them it isn't wired up.
