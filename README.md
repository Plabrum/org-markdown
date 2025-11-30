# Org_markdown

Org markdown gives org mode features to markdown files in Neovim.

### Features
  * Agenda view for scheduled tasks using <YYYY-MM-DD>
  * Task management for TODO and IN_PROGRESS headings
  * Priority-aware task sorting ([#A], [#B], etc.)
  * Quick notes - Timestamped markdown files with a single keypress
  * Refile entries to other headings or files
  * Flexible capture templates with floating editor support
  * Picker support via telescope.nvim or snacks.nvim
  * **Calendar sync** - Sync events from Apple Calendar (macOS)
  * **Extensible sync plugins** - Add custom data sources (GitHub, Todoist, etc.)
  * Fully configurable with lazy-loading and custom keymaps


### Getting Started

Installation (with Lazy.nvim)

```lua
return {
  "Plabrum/org-markdown",
  opts = {
 }
```


### Commands

Command	Description
:MarkdownCapture	Create a new capture
:MarkdownAgenda	Open agenda view (cycle views with `[` and `]`)
:MarkdownRefileFile	Refile content to a file
:MarkdownRefileHeading	Refile content under a heading
:MarkdownSyncCalendar	Sync events from Apple Calendar (macOS)
:MarkdownSyncAll	Sync all enabled sync plugins


### Quick Notes

Quickly create notes without opening a picker or capture template.

**Usage:**
1. Press `<leader>z` (or your configured keymap)
2. A new markdown file is created based on the recipe type
3. Start writing immediately - auto-saved on CursorHold/InsertLeave

**Built-in Note Types (Recipes):**
- **Git Branch Note** - Creates `folder-name__branch-name.md` (useful for project-specific notes)
- **Daily Journal** - Creates `journal_YYYY-MM-DD.md` (daily journaling)

**Navigation:**
- `[` / `]` - Cycle between note types (if multiple recipes are configured)
- `q` or `<Esc>` - Close the note

**Configuration:**
```lua
opts = {
  quick_note_file = "~/notes/quick_notes/",  -- Directory for quick notes
  keymaps = {
    open_quick_note = "<leader>z",
  }
}
```


### Using Capture

Capture templates let you quickly add content to specific files and headings.

**Workflow:**
1. Run `:MarkdownCapture` or press `<leader>oc`
2. Select a template from the picker
3. Fill in the capture buffer (cursor starts at `%?` marker position)
4. **Submit:** `<C-c><C-c>` or `<leader><CR>` to save
5. **Cancel:** `<C-c><C-k>` to abort

**Navigation:**
- `[` / `]` - Cycle between templates (if multiple templates are configured)
- `<Tab>` - Jump to next `%?` cursor marker in the template

**Template Markers:**
- `%t` - Active timestamp: `<2025-11-30 Sat>`
- `%T` - Active timestamp with time: `<2025-11-30 Sat 14:30>`
- `%u` - Inactive timestamp: `[2025-11-30 Sat]`
- `%U` - Inactive timestamp with time: `[2025-11-30 Sat 14:30]`
- `%H` - Time only: `14:30`
- `%n` - Author name (from git config or $USER)
- `%Y`, `%m`, `%d` - Year, month, day
- `%f` - Current file relative path
- `%F` - Current file absolute path
- `%a` - Link to current file and line: `[[file:/path/to/file.md +123]]`
- `%x` - Clipboard contents
- `%?` - Cursor position after template expansion
- `%^{prompt}` - Prompt user for input with label
- `%<fmt>` - Custom date format (e.g., `%<%Y-%m-%d %H:%M:%S>`)

**Example Template:**
```lua
opts = {
  captures = {
    templates = {
      todo = {
        filename = "~/notes/todo.md",
        heading = "TODO's",
        template = "# TODO %? \n %u",  -- Cursor at %?, adds inactive timestamp
      },
    },
  }
}
```


### Using Agenda

The agenda displays tasks and calendar events from your markdown files.

**Navigation:**
- `[` - Cycle to previous view
- `]` - Cycle to next view
- `q` - Close agenda buffer

**Default Views:**
1. **Tasks** - Shows TODO/IN_PROGRESS items grouped by file
2. **Calendar** - Shows scheduled events (10-day range)

**Customizing Views:**
You can define custom views in your config (see Configuration Options below). Views are processed through a filter → sort → group → render pipeline.


### Refiling
  - Call :MarkdownRefileFile or :MarkdownRefileHeading
  - Picker shows Markdown files or headings
  - Refile automatically cuts the content and pastes it to the destination
  - Operates on bullet lines or heading blocks based on cursor position


### Agenda Rules

Tasks Tracked
  - Lines with `TODO` or `IN_PROGRESS`
  - Example: `## TODO Implement capture buffer`

Scheduled Dates
  - Use `<2025-06-21>` for tracked items
  - Use `[2025-06-21]` for non-agenda timestamps

Priorities
  - Supported: [#A], [#B], [#C]
  - Tasks are ranked in AgendaTasks


### Calendar Sync

**macOS only** - Sync events from Apple Calendar into a dedicated markdown file.

#### Quick Start

1. Run `:MarkdownSyncCalendar` to manually sync
2. Events appear in your configured sync file (default: `~/notes/calendar.md`)
3. Synced events show up in Agenda Calendar view automatically

#### How It Works

- Fetches events from Calendar.app via AppleScript
- Formats events as markdown headings with dates and tags
- Writes to sync file between special HTML comment markers
- Content outside markers is preserved (add your own notes!)
- Re-sync overwrites the auto-managed section only

#### Example Output

```markdown
# Team Meeting                                                    :work:
<2025-11-30 Sat 14:00-15:00>

# Birthday Party                                                  :personal:
<2025-12-05 Thu>

# Conference Trip                                                 :travel:
<2025-12-10 Tue>--<2025-12-12 Thu>
```

#### Permissions Setup

On first sync, macOS may ask for permission:
1. Grant Terminal (or iTerm/WezTerm/etc.) permission to control Calendar
2. If denied, go to: **System Preferences > Privacy & Security > Automation**
3. Enable Terminal → Calendar

#### Integration with Agenda

- Synced events automatically appear in `:MarkdownAgenda` calendar view
- Events show up if they have tracked dates (`<YYYY-MM-DD>`)
- Events won't appear in tasks view (they have no TODO/DONE state)
- To create a task from an event, copy it outside the sync markers

#### Configuration

```lua
opts = {
  sync = {
    plugins = {
      calendar = {
        enabled = true,
        sync_file = "~/notes/calendar.md",
        days_ahead = 30,                    -- Sync next 30 days
        days_behind = 0,                    -- Include past events
        calendars = {},                     -- {} = all, or specify: { "Work", "Personal" }
        exclude_calendars = { "Birthdays", "US Holidays" }, -- Exclude specific calendars
        include_time = true,                -- Show event times
        include_end_time = true,            -- Show end times
        heading_level = 1,                  -- 1 = #, 2 = ##, etc.
        auto_sync = false,                  -- Enable periodic auto-sync
        auto_sync_interval = 3600,          -- Sync every hour (in seconds)
      }
    }
  },
  keymaps = {
    sync_calendar = "<leader>os",          -- Manual sync keymap
    sync_all = "<leader>oS",               -- Sync all plugins
  }
}
```

#### Limitations

- **macOS only** (requires Calendar.app and AppleScript)
- **Read-only sync** (markdown → calendar not supported)
- **Manual edits in sync section are overwritten** (edit outside markers instead)

#### Adding Custom Sync Sources

The sync system is extensible! You can add plugins for GitHub issues, Todoist, Notion, etc.

**Plugin Interface:**
```lua
-- lua/my_sync_plugin.lua
return {
  name = "plugin_id",                     -- Required: unique identifier
  sync = function()                       -- Required: main sync function
    return { events = {...}, stats = {...} }
  end,

  -- Optional fields:
  description = "Human-readable name",    -- For UI/notifications
  default_config = {},                    -- Merged into config.sync.plugins[name]
  setup = function(config) end,           -- Validation/init (return false to disable)
  supports_auto_sync = true,              -- Enable auto-sync support
  command_name = "MarkdownSyncPlugin",    -- Override default command
  keymap = "<leader>osp",                 -- Default keymap
}
```

**Event Format:**
```lua
{
  events = {
    {
      title = "Event Title",                                         -- Required
      start_date = { year = 2025, month = 11, day = 28, day_name = "Thu" },
      end_date = { ... },       -- Optional (multi-day)
      start_time = "14:00",     -- Optional (24hr)
      end_time = "15:00",       -- Optional
      all_day = false,          -- Boolean
      tags = { "tag1" },        -- Array
      body = "Description",     -- Optional
    }
  },
  stats = { count = 5, source = "GitHub" }  -- Optional
}
```

**Usage:**
```lua
opts = {
  sync = {
    external_plugins = { "my_sync_plugin" },
    plugins = {
      my_sync_plugin = {
        -- Plugin-specific config here
      }
    }
  }
}
```


### Configuration Options

```lua
opts = {
  -- Default keymaps
  keymaps = {
    capture = "<leader>oc",
    agenda = "<leader>oa",
    find_file = "<leader>off",
    find_heading = "<leader>ofh",
    refile_to_file = "<leader>orf",
    refile_to_heading = "<leader>orh",
    open_quick_note = "<leader>z",
    sync_all = "<leader>oS",
  },

  picker = "snacks",  -- or "telescope"
  window_method = "vertical",  -- or "float" or "horizontal"

  -- Capture templates
  captures = {
    default_template = "todo",
    templates = {
      todo = {
        filename = "~/notes/todo.md",
        heading = "TODO's",
        template = "# TODO %? \n %u",
      },
    },
  },

  -- Paths for refile operations
  refile_paths = { "~/notes" },

  -- Quick note directory
  quick_note_file = "~/notes/quick_notes/",
}
```


### TODO
  - Tag filtering in agenda views
  - Jump to line from agenda view
  - Multiple refiles at once
  - Archive support


