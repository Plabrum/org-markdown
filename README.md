# Org_markdown

Org markdown gives org mode features to markdown files in Neovim.

### Features
  * Agenda view for scheduled tasks using <YYYY-MM-DD>
  * Task management for TODO and IN_PROGRESS headings
  * Priority-aware task sorting ([#A], [#B], etc.)
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
:MarkdownAgenda	Combined agenda view
:MarkdownAgendaTasks	Task view sorted by priority
:MarkdownAgendaCalendar	Calendar view (7-day range)
:MarkdownRefileFile	Refile content to a file
:MarkdownRefileHeading	Refile content under a heading
:MarkdownSyncCalendar	Sync events from Apple Calendar (macOS)
:MarkdownSyncAll	Sync all enabled sync plugins



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
  keymaps = {
    capture = "<leader>on",
    agenda = "<leader>ov",
  },
  picker = "telescope", -- or "snacks"
  window_method = "float", -- or "horizontal"
  captures = {
    default_template = "inbox",
    templates = {
      inbox = {
        file = "~/notes/inbox.md",
        heading = "Inbox",
        template = "- [ ] %t %?",
      },
    },
  }
}
```


### TODO
  - Tag filtering in agenda views
  - Jump to line from agenda view
  - Multiple refiles at once
  - Archive support


