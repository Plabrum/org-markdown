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
- Views are defined in `config.agendas.views` with default "tasks", "calendar_blocks", and "calendar_compact" views
- Supports tabbed navigation between multiple views via `config.agendas.tabbed_view`
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
- `agendas.views`: custom agenda view definitions (see Agenda Views section below)
- `agendas.tabbed_view`: tabbed navigation configuration
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

#### View Configuration Structure
Each view in `config.agendas.views` has the following structure:
```lua
{
  title = "View Title",           -- Displayed at top of buffer
  source = "tasks",                -- "tasks", "calendar", or "all"
  filters = {                      -- Optional: filter items
    states = { "TODO", "IN_PROGRESS" },
    priorities = { "A", "B" },
    tags = { "work", "urgent" },
    date_range = { days = 7, offset = 0 }  -- or { from = "2025-01-01", to = "2025-12-31" }
  },
  sort = {                         -- Optional: sort items
    by = "priority",               -- "priority", "date", "state", "title", "file"
    order = "asc",                 -- "asc" or "desc"
    priority_rank = { A = 1, B = 2, C = 3, Z = 99 }  -- Custom priority ranking
  },
  group_by = "date",               -- Optional: "date", "priority", "state", "file", "tags"
  display = {                      -- Optional: formatting
    format = "blocks"              -- "blocks" or "timeline"
  }
}
```

#### Example Custom Views
```lua
-- High-priority work items
config.agendas.views.urgent = {
  title = "Urgent Work Items",
  source = "tasks",
  filters = {
    states = { "TODO", "IN_PROGRESS" },
    priorities = { "A" },
    tags = { "work" }
  },
  sort = { by = "date", order = "asc" },
  display = { format = "timeline" }
}

-- This week's calendar grouped by date
config.agendas.views.week = {
  title = "This Week",
  source = "calendar",
  filters = {
    date_range = { days = 7, offset = 0 }
  },
  sort = { by = "date", order = "asc" },
  group_by = "date",
  display = { format = "blocks" }
}

-- All items grouped by file
config.agendas.views.by_file = {
  title = "Tasks by File",
  source = "all",
  sort = { by = "file", order = "asc" },
  group_by = "file",
  display = { format = "timeline" }
}
```

To use custom views in the tabbed interface:
```lua
config.agendas.tabbed_view = {
  enabled = true,
  views = { "urgent", "week", "tasks", "calendar" }
}
```

### Sync Plugin Development
When creating a sync plugin:
1. **Implement standard interface**: Return a table with `name`, `sync()`, `default_config`
2. **Return standard event format**: Manager handles markdown formatting
3. **Handle errors gracefully**: Return `nil, error_message` on failure
4. **Use plugin config**: Access via `config.sync.plugins[plugin_name]`
5. **Register in init.lua**: Add to `plugin_names` array or use `external_plugins` config
6. **Example**: See `sync/plugins/calendar/` for reference implementation

Sync plugin interface:
```lua
{
  name = "plugin_name",                    -- Required: Plugin identifier
  description = "Human-readable name",     -- Optional: For UI/notifications
  default_config = { ... },                -- Optional: Merged into config.sync.plugins.plugin_name
  setup = function(config) ... end,        -- Optional: Validation/initialization (return false to disable)
  sync = function() ... end,               -- Required: Main sync operation
  supports_auto_sync = true,               -- Optional: Enable auto-sync support
  command_name = "MarkdownSyncFoo",        -- Optional: Override default command name
  keymap = "<leader>osp",                  -- Optional: Default keymap
}
```

Event data structure (returned by plugin sync()):
```lua
{
  events = {
    {
      title = "Event Title",
      start_date = { year = 2025, month = 11, day = 28, day_name = "Thu" },
      end_date = { ... },          -- Optional for multi-day events
      start_time = "14:00",         -- Optional for timed events (24-hour)
      end_time = "15:00",           -- Optional
      all_day = false,              -- Boolean
      tags = { "tag1", "tag2" },    -- Array of strings
      body = "Description...",      -- Optional event body
    }
  },
  stats = {
    count = 5,
    date_range = "2025-11-28 to 2025-12-28",  -- Optional
    source = "GitHub",                        -- Optional
  }
}
```

## File Type Support

The plugin activates editing keybinds on these file types via autocmd:
- markdown
- markdown.mdx
- quarto

Edit `commands.lua:79` to modify which file types activate org-markdown features.
