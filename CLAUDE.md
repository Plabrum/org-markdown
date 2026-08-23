# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

org-markdown is a Neovim plugin that brings org-mode features to markdown files. It provides agenda views, task management, capture templates, and refiling capabilities for markdown documents.

## Development Commands

### Testing
```bash
# Run all tests
make test

# Run a specific test file
make test_file FILE=tests/test_parser.lua
```

### Linting
```bash
# Check Lua formatting (runs via pre-commit)
stylua --check lua/

# Format Lua files
stylua lua/
```

## Architecture

### Core Module Structure

The plugin follows a modular architecture with clear separation of concerns:

- **`init.lua`**: Entry point that calls `config.setup()` and `commands.register()`
- **`config.lua`**: Centralized configuration with deep merge support for user options
- **`commands.lua`**: Registers all Vim commands and keymaps, including auto-commands for FileType events

### Key Modules

**Agenda System** (`agenda.lua`)
- Scans markdown files for TODO/IN_PROGRESS headings and scheduled dates
- Parses tasks using `parser.parse_headline()` which extracts state, priority, dates, and tags
- Fully configurable view system with filter → sort → group → render pipeline
- Views are defined as an object in `config.agendas.views`, keyed by view ID (e.g., `tasks`, `calendar`, `inbox`)
- Custom views merge additively with defaults (like capture templates)
- Tab order controlled by `order` field in each view definition
- All views are automatically available for tabbed navigation using `[` and `]` keys
- Built-in formatters: "blocks", "timeline"
- Date formats: `<YYYY-MM-DD>` for tracked/scheduled items, `[YYYY-MM-DD]` for non-agenda timestamps

**Capture System** (`capture.lua`)
- Template-based capture with expansion markers (`%t`, `%u`, `%?`, etc.)
- Uses custom async/promise implementation for user prompts and buffer editing
- Key flow: expand template → open capture buffer → submit → insert under heading
- Template markers are escaped using `parser.escape_marker()` before pattern matching
- Default template includes `CREATED_AT: [YYYY-MM-DD Day]` using org-mode standard format
- Date formats follow org-mode conventions:
  - `%u` → `[2025-01-05 Sun]` (inactive timestamp with day-of-week)
  - `%t` → `<2025-01-05 Sun>` (active timestamp with day-of-week)
  - `%<%Y-%m-%d %a>` → custom format with day-of-week
- Both `CREATED_AT` and `COMPLETED_AT` use org-mode format: `[YYYY-MM-DD Day]`

**Refiling** (`refile.lua`)
- Detects content to refile: bullet lines or heading blocks (with all sub-headings)
- Uses picker abstraction to select destination file or heading
- Automatically cuts from source and appends to destination

**Parser** (`utils/parser.lua`)
- Central parsing logic for markdown org-style syntax
- `parse_headline()`: extracts state, priority, tracked/untracked dates, text, and tags
- Recognizes states: TODO, IN_PROGRESS, WAITING, CANCELLED, DONE, BLOCKED
- Priority format: `[#A]`, `[#B]`, `[#C]`
- Tag format: `:tag1:tag2:` at end of line

**Execution Log** (`execution/log.lua`)
- Append-only record of task state transitions; execution state is derived from the log, never stored on the heading
- One central file (`config.execution.log_file`, default `~/org/execution.log`), not per-task sections, so appends never rewrite user markdown
- Line format: `<ISO-8601 UTC>\t<from>\t<to>\t<task id>`, where the task id is `<file>::<heading text>` and `-` marks an absent `from` state
- `append_event(task, transition)` appends one event; `parse_event(line)` is its exact inverse
- Appends go through `platform.fs.append_file()` so the log works in-editor and under the CLI

**Execution State** (`execution/state.lua`)
- Reducer that folds the log into current state; every answer comes from log contents alone, never from the heading
- `snapshot()` reads and folds the log into `{ tasks = { [id] = { state, since, from } }, started = <id|nil> }`; a missing log is an empty log
- `state_of(task, snapshot?)` returns a task's current state (nil if the log has never mentioned it); `started_task(snapshot?)` returns the one STARTED task
- The STARTED slot is single-occupancy: entering STARTED claims it, leaving releases it only if that task still holds it, and the most recent start wins
- Pass a `snapshot` when answering for many tasks so the log is read once

**Execution State Machine** (`execution/machine.lua`)
- Layered over the log and the reducer: the only sanctioned way to write a transition, since `log.lua` appends anything it is handed and `state.lua` folds anything it finds
- Legal moves: `TODO → STARTED → PAUSED → DONE`, plus `PAUSED → STARTED` to resume and `STARTED → DONE` to finish without pausing; DONE is terminal
- A task the log has never mentioned is implicitly TODO, so a fresh heading can be started without seeding an event first
- `transition(task, target, opts?)` reads current state, rejects illegal moves with an error, and returns the appended events; `opts` carries `at` (fixed timestamp) and `snapshot` (state the caller already folded)
- Single-STARTED invariant: starting a task auto-pauses whatever was STARTED, and the pause/start pair is appended in one write via `log.append_events()` so the log never shows two started tasks or a pause that lost its start
- `can(from, to)` exposes the transition table for callers that need to know what is legal before asking

**Node IDs** (`node/id.lua`)
- A node is a file or a heading; both carry a stable UUID so links survive rename and refile
- A file keeps its id as `id` in frontmatter; a heading keeps it as an `ID: [uuid]` property under the heading line (written via `utils/document.lua`)
- Minted lazily: `get(target)` only reads, `ensure(target)` mints and writes exactly once and is a no-op on an already-identified node
- `target` is a file path (file node) or `{ file = ..., heading = ... }`; `title`/`text` are accepted as the heading text so agenda items and parsed headlines pass through unchanged
- All IO goes through the platform shim, so ids can be minted under the CLI as well as in-editor

**Node Index** (`node/index.lua`)
- Maps a node id to where that node lives now, so links resolve by UUID instead of by path and survive rename and refile
- Built by scanning: `utils/queries.lua` walks `refile_paths`, and each file contributes its frontmatter `id` plus the `ID` property of every heading in it
- `build(opts?)` returns `{ [id] = location }`; `lookup(id, index?)` returns one location, scanning when no index is passed
- A location is `{ id, file }` for a file node, plus `heading` and `line` for a heading node; on a duplicate id the first file scanned wins
- Scan-and-rebuild only — keeping the index fresh incrementally as buffers change is ORGMD-1

**By-ID Links** (`utils/patterns.lua`, `utils/parser.lua`)
- A link names its target by UUID, never by path, so it survives rename and refile
- Syntax is ordinary markdown: `[display text](id:<uuid>)`; the `id:` scheme is what marks it as ours
- Pattern lives in `patterns.LINK` (with `patterns.LINK_SCHEME` and `patterns.UUID`)
- `parser.parse_link(line, init?)` returns `{ id, text, from, to }` for the first link (`from`/`to` are its byte range, for cursor-aware callers); `parser.parse_links(line)` returns all of them
- `parser.serialize_link(link)` is its exact inverse

**Link Creation** (`node/link.lua`)
- Interactive counterpart to the by-ID link syntax: pick a target, get a durable link at point
- `targets(opts?)` lists every linkable node — each markdown file in scope, then every heading inside it
- `to_target(target)` mints the target's id via `node/id.ensure()` and renders the link with `parser.serialize_link()`; the display text is the heading text, or the file's display name for a file node
- `insert()` is the editor side: picks a target through `utils/picker.lua` and puts the link at the cursor (`:MarkdownInsertLink`, `keymaps.insert_link`)
- Linking to a node is what gives it an identity — a target that has never been linked to is identified on the spot

**Following Links** (`node/link.lua`)
- The reverse trip: the id under the cursor is resolved through `node/index.lua` to wherever that node lives now, so a link still lands after its target was renamed or refiled
- `link_at(line, col?)` returns the link the cursor sits on, falling back to the first link on the line
- `resolve(id, index?)` returns the location, or `nil, err` for an id no file in scope carries — an unresolved link is reported, never an error
- `follow()` is the editor side: jumps to the target file and, for a heading node, its line (`:MarkdownFollowLink`, `keymaps.follow_link`)

**Async Utilities** (`utils/async.lua`)
- Custom Promise implementation with `then_()`, `catch_()`, and `await()`
- `async.run()` wraps coroutines for async operations
- Used heavily in capture flow for user input and buffer interaction

**Queries** (`utils/queries.lua`)
- Synchronous file system scanning using `vim.uv.fs_scandir`
- Recursively finds markdown files in configured `refile_paths` or cwd
- Returns absolute paths to all `.md` and `.markdown` files

**Sync Plugin System** (`sync/manager.lua` and `sync/plugins/`)
- Extensible plugin architecture for syncing data from external sources
- **Manager** (`sync/manager.lua`): Plugin registry, sync orchestration, event formatting, auto-sync timers
- **Plugins** (`sync/plugins/`): Self-contained modules implementing standard interface
  - Simple plugins: single `.lua` file
  - Complex plugins: folder with `init.lua` and additional files (e.g., `calendar/`)
- Plugin interface: `{ name, description, default_config, setup(), sync(), supports_auto_sync, command_name, keymap }`
- Event format: Standard structure `{ title, start_date, end_date, start_time, end_time, all_day, tags, body }`
- Marker-based file preservation: User content outside `<!-- BEGIN/END SYNC -->` markers is preserved
- Concurrent sync protection: Per-plugin locks prevent simultaneous syncs
- Auto-sync: Optional periodic sync via `vim.loop.new_timer()`
- Built-in plugins:
  - **Calendar** (`sync/plugins/calendar/`): macOS Calendar.app sync via Swift/AppleScript
    - Fetches events using AppleScript date filtering
    - Parses macOS date format ("Saturday, November 22, 2025 at 2:00:00 PM")
    - Supports multi-day events with `<date>--<date>` format
    - Calendar filtering via include/exclude lists
    - Tags events by calendar name (sanitized for markdown)

### Configuration System

User config is deeply merged into defaults via `merge_tables()` in `config.lua`. Key configurable areas:
- `captures.templates`: capture template definitions with file/heading/template
- `refile_paths`: directories to scan for markdown files
- `picker`: "telescope" or "snacks"
- `window_method`: "float", "vertical", or "horizontal"
- `keymaps`: all command keybindings
- `checkbox_states` and `status_states`: cycling behavior
- `agendas.views`: array of agenda view definitions (see Agenda Views section below)
- `promotion`: where a promoted source entry lands (`file`, optional `heading`) and the status it takes
- `sync.plugins.*`: per-plugin configuration (calendar, external plugins, etc.)
- `sync.external_plugins`: array of external plugin module names to load

### Testing Infrastructure

Tests use `mini.test` framework:
- `tests/init.lua` bootstraps lazy.nvim with the plugin and mini.test
- Run headless with `nvim --headless -u tests/init.lua`
- Individual files can be run with `-c "luafile <file>"` pattern

## Important Patterns

### Picker Abstraction
The plugin supports both telescope.nvim and snacks.nvim via `utils/picker.lua`. When adding picker functionality, use the picker module rather than calling telescope/snacks directly.

### Window Management
All buffer/window creation goes through `utils.open_window()` which handles:
- Float, vertical, or horizontal splits
- Title, footer, and filetype setup
- Standard `q` to close keybinding
- Optional `on_close` callbacks

### Heading Manipulation
When inserting content under headings, use `utils.insert_under_heading(file, heading, lines)` which finds or creates the heading and inserts content below it.

### Async Operations
User prompts and capture buffers use the custom async system. Wrap async functions with `async.run()` and use `:await()` to wait for promises.

### Agenda Views
The agenda system uses a configurable view architecture that processes items through a filter → sort → group → render pipeline.

#### Agenda Configuration

**Global Agenda Settings:**
```lua
agendas = {
  window_method = "float",                    -- "float", "vertical", or "horizontal"
  ignore_patterns = { "*.archive.md", "sources/*" }, -- Patterns to exclude from all agenda views
                                              -- (ingestion logs under sources/ only reach the
                                              -- agenda once promoted out of the log)
  views = { ... }                             -- View definitions (see below)
}
```

The `ignore_patterns` setting applies globally to all agenda views and supports the same pattern syntax as `file_patterns` in filters:
- Exact filename: `"archive.md"`
- Wildcard: `"*.archive.md"` (matches all files ending in `.archive.md`)
- Directory: `"archive/*"` (matches all files in paths containing `archive/`)

#### View Configuration Structure
Views are defined as an object in `config.agendas.views`, keyed by view ID. Custom views merge additively with defaults (similar to capture templates). Each view has the following structure:
```lua
agendas = {
  views = {
    view_id = {                    -- Key is the view ID (e.g., "tasks", "urgent", "work")
      order = 1,                   -- Optional: Controls tab order (lower = earlier), defaults to 999
      title = "View Title",        -- Displayed at top of buffer
      source = "tasks",            -- "tasks", "calendar", or "all"
      filters = {                  -- Optional: filter items
        file_patterns = { "work/*", "refile" },  -- Flexible pattern matching (applied at query stage)
        states = { "TODO", "IN_PROGRESS" },
        priorities = { "A", "B" },
        tags = { "work", "urgent" },
        date_range = { days = 7, offset = 0 }  -- or { from = "2025-01-01", to = "2025-12-31" }
      },
      sort = {                     -- Optional: sort items
        by = "priority",           -- "priority", "date", "state", "title", "file"
        order = "asc",             -- "asc" or "desc"
        priority_rank = { A = 1, B = 2, C = 3, Z = 99 }  -- Custom priority ranking
      },
      group_by = "date",           -- Optional: "date", "priority", "state", "file", "tags"
      display = {                  -- Optional: formatting
        format = "blocks"          -- "blocks" or "timeline"
      }
    }
  }
}
```

#### View Source Types

The `source` field determines which headings to include in the view:

**`source = "tasks"`** - Shows headings with TODO states
- Includes: `## TODO Buy groceries`, `## IN_PROGRESS Write docs`
- Excludes: Plain headings without states

**`source = "calendar"`** - Shows headings with tracked dates (`<YYYY-MM-DD>`)
- Includes: `## Meeting <2025-12-05>`, `## TODO Review PR <2025-12-06>`
- Excludes: Headings without tracked dates (untracked dates `[YYYY-MM-DD]` are not shown)

**`source = "all"`** - Shows ALL headings regardless of state or date
- Includes: Every heading in the scanned files
- Use with `file_patterns` to scope to specific files
- Example: View all headings in inbox file

**Notes:**
- Headings can appear in multiple sources (e.g., `## TODO Meeting <2025-12-05>` is in both `tasks` and `calendar`)
- The `source` determines initial inclusion; filters (states, dates, tags, etc.) can further refine the results
- Use `source = "all"` when you want to see everything, then filter as needed

#### File Pattern Matching

The `file_patterns` filter provides flexible file matching at the query stage (before reading/parsing files) for optimal performance:

**Pattern Types:**
- **Exact filename**: `"refile.md"` - matches files named exactly "refile.md"
- **Substring match**: `"refile"` - matches any file containing "refile" (e.g., "refile.md", "my-refile.md")
- **Wildcard**: `"*.todo.md"` - matches files ending with ".todo.md"
- **Directory**: `"work/*"` - matches all files in the work directory
- **Nested paths**: `"archive/*"` - matches files in paths containing "archive/"

**Performance Note:** File filtering happens at the query stage, so only matching files are read and parsed. This is much faster than the deprecated `filters.files` which filtered after parsing all files.

**Migration:** The old `filters.files` field (exact filename matching only) is deprecated. Use `filters.file_patterns` for flexible pattern support.

#### Example Custom Views
```lua
-- Define custom views as an object (merges additively with defaults)
config.agendas.views = {
  urgent = {
    order = 1,  -- Tab order (appears first)
    title = "Urgent Work Items",
    source = "tasks",
    filters = {
      states = { "TODO", "IN_PROGRESS" },
      priorities = { "A" },
      tags = { "work" }
    },
    sort = { by = "date", order = "asc" },
    display = { format = "timeline" }
  },
  week = {
    order = 2,
    title = "This Week",
    source = "calendar",
    filters = {
      date_range = { days = 7, offset = 0 }
    },
    sort = { by = "date", order = "asc" },
    group_by = "date",
    display = { format = "blocks" }
  },
  by_file = {
    order = 10,  -- Appears after defaults (which have order 1, 2, 3)
    title = "Tasks by File",
    source = "all",
    sort = { by = "file", order = "asc" },
    group_by = "file",
    display = { format = "timeline" }
  },
  -- You can also override default views by using their key
  tasks = {
    order = 1,
    title = "My Custom Tasks View",  -- Override default tasks view
    source = "tasks",
    filters = { states = { "TODO" } }  -- Only TODO, not IN_PROGRESS
  }
}
```

**Note**: Views are defined as an object keyed by view ID. Custom views **merge** with default views (additive, like capture templates). Use the `order` field to control tab order when cycling with `[` and `]` keys. To override a default view, use its key (`tasks`, `calendar`, or `inbox`) and provide your custom definition.

### Sync Plugin Development

The sync plugin system supports importing different types of data sources (calendars, task trackers, etc.) into markdown files. Each plugin manages its own sync file, which is **AUTO-MANAGED** (completely replaced on each sync).

When creating a sync plugin:
1. **Implement standard interface**: Return a table with `name`, `sync_file`, `sync()`, `default_config`
2. **Return standard item format**: Manager handles markdown formatting
3. **Handle errors gracefully**: Return `nil, error_message` on failure
4. **Use plugin config**: Access via `config.sync.plugins[plugin_name]`
5. **Register in init.lua**: Add to `plugin_names` array or use `external_plugins` config
6. **Examples**: See `sync/plugins/calendar/` and `sync/plugins/linear.lua`

#### Sync Plugin Interface

```lua
{
  name = "plugin_name",                    -- Required: Plugin identifier
  sync_file = "~/org/plugin.md",           -- Required: File to sync to (AUTO-MANAGED)
  description = "Human-readable name",     -- Optional: For UI/notifications
  default_config = { ... },                -- Optional: Merged into config.sync.plugins.plugin_name
  setup = function(config) ... end,        -- Optional: Validation/initialization (return false to disable)
  sync = function() ... end,               -- Required: Main sync operation
  mode = "replace",                        -- Optional: "replace" (default) or "append" (ingestion)
  supports_auto_sync = true,               -- Optional: Enable auto-sync support
  command_name = "MarkdownSyncFoo",        -- Optional: Override default command name
  keymap = "<leader>osp",                  -- Optional: Default keymap
}
```

#### Item Data Structure

Items can represent calendar events, tasks, issues, or simple notes. All date/status fields are optional - items with no dates/status are valid "notes".

**Manager handles org-markdown fields only:**
- Headings (title, status, priority)
- Dates (for agenda filtering/display)
- Tags (for filtering/organization)
- Body (markdown content)

**Plugins format their own domain-specific metadata** (assignee, project, location, URLs, IDs) into the `body` field.

```lua
{
  items = {  -- Can also use "events" for backward compatibility
    {
      -- Required
      title = "Item Title",

      -- Dates (optional - for agenda filtering/display)
      start_date = { year = 2025, month = 11, day = 28 },  -- Optional
      due_date = { year = 2025, month = 12, day = 1 },      -- Optional (for tasks)
      end_date = { ... },                                    -- Optional

      -- Times (optional - for calendar events)
      start_time = "14:00",         -- Optional (24-hour)
      end_time = "15:00",           -- Optional
      all_day = false,              -- Optional

      -- Org-markdown fields (optional - for filtering/organization)
      status = "TODO",              -- Optional (TODO, IN_PROGRESS, DONE, CANCELLED)
      priority = "A",               -- Optional (A, B, C)
      tags = { "tag1", "tag2" },    -- Optional

      -- Content (plugin formats its own metadata here)
      body = "**Assignee:** Alice\n**Project:** Acme\n\nDescription text...",  -- Optional
      description = "...",          -- Optional (fallback if no body)
    }
  },
  stats = {
    count = 5,
    date_range = "2025-11-28 to 2025-12-28",  -- Optional
    source = "Linear",                        -- Optional
    calendars = { "Work", "Personal" },       -- Optional
  }
}
```

#### Built-in Plugins

**Calendar Plugin** (`sync/plugins/calendar/`)
- **Bidirectional sync** with macOS Calendar.app
- **Pull** (Calendar.app → `~/org/calendar.md`): Auto-managed file with events from Calendar.app
- **Push** (markdown → Calendar.app): Any markdown item with tracked date (`<YYYY-MM-DD>`) syncs to "org-markdown" calendar
- Config: `config.sync.plugins.calendar`
- Org-markdown fields: `start_date`, `end_date`, `all_day`, `start_time`, `end_time`, `tags`
- UID tracking: Items store Calendar.app UID in body as `**Calendar ID:** \`<uid>\`` for updates
- Formats into body: location, URL, calendar ID, notes

**Bidirectional Sync Architecture:**
- **Pull (existing)**: Calendar.app → calendar.md (one-way, auto-managed)
- **Push (new)**: User files (refile.md, etc.) → Calendar.app "org-markdown" calendar
- **Async execution**: Push runs asynchronously using custom async/promise system (doesn't block UI)
- Sync loop prevention: Pull excludes "org-markdown" calendar by default
- UID lifecycle: Create (no UID) → returns UID → Update (with UID) → modify event
- Conflict resolution: Markdown wins (push overwrites Calendar.app changes)
- Auto-sync: Disabled by default (enable after creating "org-markdown" calendar)

**Linear Plugin** (`sync/plugins/linear.lua`)
- Syncs assigned issues and cycles from Linear
- File: `~/org/linear.md`
- Config: `config.sync.plugins.linear`
- Requires: API key from https://linear.app/settings/api
- Org-markdown fields: `status`, `priority`, `due_date`, `tags`
- Formats into body: assignee, project, state, URL, issue ID
- State mapping:
  - `backlog`, `todo` → `TODO`
  - `in_progress`, `started` → `IN_PROGRESS`
  - `done`, `completed` → `DONE`
  - `canceled` → `CANCELLED`

#### Ingestion Mode (`sync/ingest.lua`)

- A plugin with `mode = "append"` ingests into a source log instead of mirroring a source: entries are only appended, and prior entries are never rewritten or reordered
- Each appended entry carries a marker on the line below its heading holding a stable key and a promotion status (`<!-- key: ... status: new -->`); a re-run skips keys already in the file, so an item lands exactly once no matter how often the source replays it
- The key is `item.key` when the plugin has a stable id of its own, otherwise it is derived from title + date + time (`ingest.entry_key()`)
- The status is the promotion sweep's record of what it has done with an entry: it lands as `new` and the sweep marks it `promoted` or `rejected`, which takes it out of what a later sweep proposes. Because the marker lives in the log rather than in the sweep, and the entry is never re-appended, the status survives re-sync
- `ingest.entries(path)` lists every entry with its status and marker line; `ingest.pending(path)` narrows that to what is still `new`, and `ingest.status_of(path, key)` answers for one key
- `ingest.set_status(path, key, status)` rewrites just that entry's marker line, leaving the rest of the log as written; a marker with no status reads as `new`, so logs written before statuses existed still work
- `ingest.append_entries(path, entries)` is the append primitive; it dedups against the file and within the batch, and writes once through the platform shim (so ingestion works under the CLI)
- Append-mode files get no auto-managed header — they are meant to be read and edited in place
- `ingest.append_entries()` creates the log's parent directory, since source logs live in one of their own (`~/org/sources/`)
- `ingest.find(path, key)` returns one entry, including the `heading` it was stamped under — found by looking back from the marker, since minting the entry's id puts a property line between the two

#### Promotion (`sync/promote.lua`)

- Promotion is how an ingested entry becomes work the user has accepted: the entry's text lands as a tracked TODO in a file the agenda scans, which a source log (under the ignored `sources/*`) is deliberately not
- `promote.entry(source, destination?, opts?)` is the whole operation — `source` is `{ file = <log>, key = <entry key> }`, `destination` is `{ file, heading? }` defaulting to `config.promotion`, and `opts` carries `status` and `date`
- The promoted heading keeps the entry's own text, priority and tags, takes the promoting status (`TODO`) and a tracked date (today unless `opts.date` says otherwise), and carries a `**Source:**` back-link under it
- The back-link is an Epic-B by-ID link (`node/link.to_target()`), so it still resolves after the entry or the heading is refiled; minting the id is what writes an `ID` property into the log entry
- The entry is stamped `promoted` (`ingest.set_status`) only once its TODO is on disk, so a failure part-way leaves the entry pending rather than losing it; an entry already `promoted` or `rejected` is refused, since promoting twice would duplicate the item in planning
- Trigger-agnostic: choosing entries and asking the user belongs to whatever drives it. Writing goes through `capture/core.insert_under_heading()` and the platform shim, so promotion runs under the CLI too

**Granola Plugin** (`sync/plugins/granola/`) — the first ingestion source
- Appends the action items of finished Granola meetings to `~/org/sources/granola.md` (`mode = "append"`)
- Reads Granola's local cache (`cache-v3.json`), whose `cache` key holds the real state as a nested JSON string; `cache.load()` unwraps both layers
- A meeting is finished once its calendar event's end time has passed (a meeting with no event falls back to when it was last written to) — notes are still being taken while it runs
- Notes arrive as ProseMirror trees (generated summary panels) or markdown (hand-written notes); `cache.flatten()` reduces both to markdown lines and `cache.action_items()` extracts from those
- An action item is an unchecked checkbox anywhere in the notes, or a bullet under a heading named by `action_item_headings`; an item already ticked off is skipped
- Item text is ingested verbatim; the origin (meeting title and date) goes in the body, so an entry still names its meeting after promotion
- Entry key is `granola:<meeting id>::<item text>`, so re-reading a meeting never re-ingests it while an item added later still lands
- `lookback_days` (default 30) bounds the first sync; set to 0 for no limit

#### Important Notes

- **AUTO-MANAGED FILES**: Sync files in the default `mode = "replace"` are completely replaced on each sync. Do not manually edit them.
- **Agenda Integration**: Items with `status` appear in task-based agenda views. Items with tracked dates (`<YYYY-MM-DD>`) appear in calendar-based views.
- **File Format**: All items are formatted as markdown headings with optional dates, tags, and metadata.

## File Type Support

The plugin activates editing keybinds on these file types via autocmd:
- markdown
- markdown.mdx
- quarto

Edit `commands.lua:79` to modify which file types activate org-markdown features.
