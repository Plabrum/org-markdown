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
  ignore_patterns = { "*.archive.md" },      -- Patterns to exclude from all agenda views
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

#### Important Notes

- **AUTO-MANAGED FILES**: Sync files are completely replaced on each sync. Do not manually edit them.
- **Agenda Integration**: Items with `status` appear in task-based agenda views. Items with tracked dates (`<YYYY-MM-DD>`) appear in calendar-based views.
- **File Format**: All items are formatted as markdown headings with optional dates, tags, and metadata.

## File Type Support

The plugin activates editing keybinds on these file types via autocmd:
- markdown
- markdown.mdx
- quarto

Edit `commands.lua:79` to modify which file types activate org-markdown features.
