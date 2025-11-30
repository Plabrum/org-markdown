# Sync Plugin Interface Documentation

## Overview

The sync plugin system allows you to sync events from external sources (calendars, task managers, issue trackers) into your markdown files.

## Quick Start

### Minimal Plugin

**Option 1: Single file**
```lua
-- lua/org_markdown/sync/plugins/myplugin.lua
local M = {}

M.name = "myplugin"

function M.sync()
    return {
        events = {
            {
                title = "My Event",
                start_date = { year = 2025, month = 11, day = 29, day_name = "Fri" },
                all_day = true,
            }
        }
    }
end

return M
```

**Option 2: Multi-file plugin (recommended for complex plugins)**
```
lua/org_markdown/sync/plugins/myplugin/
├── init.lua          -- Main plugin file
└── helper_script.sh  -- Additional files
```

### Register Plugin

**Built-in plugin:**
Add to `init.lua`:
```lua
local plugin_names = { "calendar", "myplugin" }
```

**External plugin:**
User adds to their config:
```lua
require("org_markdown").setup({
    sync = {
        external_plugins = { "my_username.myplugin" }
    }
})
```

## Plugin Interface

### Required Fields

#### name (string)
Unique identifier. Used in:
- Commands: `MarkdownSync<Name>`
- Markers: `<!-- BEGIN ORG-MARKDOWN <NAME> SYNC -->`
- State storage key
- Config namespace: `config.sync.plugins[name]`

**Example:**
```lua
M.name = "github_issues"
```

#### sync() → table
Main sync function. Called when user runs sync command.

**Returns:**
```lua
{
    events = { ... },  -- Required: array of event objects
    stats = {          -- Optional: shown in notification
        count = 42,
        date_range = "2025-11-01 to 2025-11-30",
        source = "GitHub",
    }
}
```

**Error handling:**
```lua
function M.sync()
    local ok, events = pcall(fetch_events)
    if not ok then
        return nil, "Failed to fetch: " .. tostring(events)
    end
    return { events = events }
end
```

### Optional Fields

#### description (string)
Human-readable name shown in notifications.

```lua
M.description = "GitHub Issues"
-- Shown as: "[GitHub Issues] Synced 10 events"
```

#### default_config (table)
Default configuration merged into `config.sync.plugins[name]`.

```lua
M.default_config = {
    sync_file = "~/notes/github.md",
    heading_level = 3,
    repo = "owner/repo",
    include_labels = {"bug", "feature"},
}
```

#### setup(config) → boolean
Called once at plugin initialization. Use for:
- Validation
- Platform checks
- Dependency checks
- Initial setup

```lua
function M.setup(config)
    -- Validate required config
    if not config.api_token then
        vim.notify("GitHub sync requires api_token in config", vim.log.levels.ERROR)
        return false  -- Disable plugin
    end

    -- Check dependencies
    if vim.fn.executable("gh") == 0 then
        vim.notify("GitHub CLI not found", vim.log.levels.WARN)
        return false
    end

    return true  -- Enable plugin
end
```

#### supports_auto_sync (boolean)
Enable automatic periodic sync.

```lua
M.supports_auto_sync = true

-- User configures interval:
-- config.sync.auto_sync_interval_ms = 300000  -- 5 minutes
```

#### command_name (string)
Override default command name (`MarkdownSync<Name>`).

```lua
M.command_name = "GithubIssuesSync"
```

#### keymap (string)
Default keymap for sync command.

```lua
M.keymap = "<leader>osg"
```

## Event Schema

### Required Fields

```lua
{
    title = "Event Title",  -- Must be non-empty string

    start_date = {
        year = 2025,
        month = 11,
        day = 29,
        day_name = "Fri"
    },

    all_day = true,  -- Boolean: true for all-day, false for timed
}
```

### Optional Fields

```lua
{
    -- Multi-day events
    end_date = {
        year = 2025,
        month = 11,
        day = 30,
        day_name = "Sat"
    },

    -- Timed events (requires all_day = false)
    start_time = "14:00",  -- HH:MM format
    end_time = "15:30",

    -- Categorization
    tags = {"work", "urgent"},  -- Array of strings

    -- Content
    body = "Full description of the event",
    description = "Brief summary (preferred over body)",

    -- Metadata (helps with sync tracking)
    id = "event-12345",  -- Unique identifier from source
    source_url = "https://github.com/owner/repo/issues/42",

    -- Location
    location = "Conference Room A",

    -- Task-style events
    status = "TODO",  -- TODO, IN_PROGRESS, DONE, etc.
    priority = "A",   -- Single letter: A, B, C
}
```

### Validation

All events are automatically validated before formatting. Invalid events are logged with detailed error messages:

```
[github_issues] Invalid event 'Fix bug #42':
  - start_time must be HH:MM format
  - priority must be single uppercase letter
```

## State Persistence (Future)

**Note**: State persistence is not currently implemented. If your plugin needs to track state between syncs (e.g., API cursors, rate limits, last sync timestamps), you can:

1. Store state in plugin-specific files (e.g., `vim.fn.stdpath("data") .. "/myplugin-state.json"`)
2. Use in-memory caching for session-based state
3. Propose a state persistence API if there's demand from multiple plugins

For most use cases, stateless syncs work well. Only add complexity when you have a proven need.

## Configuration

### Plugin-Specific Config

```lua
-- In user's config
require("org_markdown").setup({
    sync = {
        plugins = {
            myplugin = {
                sync_file = "~/notes/myplugin.md",
                heading_level = 2,
                custom_option = "value",
            }
        }
    }
})
```

### Access in Plugin

```lua
function M.sync()
    local config = require("org_markdown.config")
    local my_config = config.sync.plugins[M.name]

    local api_key = my_config.api_key
    -- ...
end
```

## Complete Example

See `lua/org_markdown/sync/plugins/calendar/` for a production reference of a multi-file plugin with external scripts.

### Simple GitHub Issues Plugin

```lua
local M = {}

M.name = "github_issues"
M.description = "GitHub Issues"
M.supports_auto_sync = true

M.default_config = {
    sync_file = "~/notes/github-issues.md",
    heading_level = 3,
    repo = nil,  -- Required
    include_labels = {},
    exclude_labels = {"wontfix"},
}

function M.setup(config)
    if not config.repo then
        vim.notify("GitHub sync requires 'repo' in config", vim.log.levels.ERROR)
        return false
    end

    if vim.fn.executable("gh") == 0 then
        vim.notify("GitHub CLI (gh) not installed", vim.log.levels.ERROR)
        return false
    end

    return true
end

function M.sync()
    local config = require("org_markdown.config").sync.plugins[M.name]
    local state = require("org_markdown.sync.state")

    -- Build query
    local query = "repo:" .. config.repo .. " is:issue is:open"

    -- Fetch issues
    local cmd = string.format("gh issue list --repo %s --json number,title,createdAt,labels,url --limit 100", config.repo)
    local output = vim.fn.system(cmd)

    if vim.v.shell_error ~= 0 then
        return nil, "Failed to fetch issues: " .. output
    end

    local issues = vim.json.decode(output)

    -- Convert to events
    local events = {}
    for _, issue in ipairs(issues) do
        -- Parse date
        local y, m, d = issue.createdAt:match("(%d%d%d%d)-(%d%d)-(%d%d)")
        local date = {
            year = tonumber(y),
            month = tonumber(m),
            day = tonumber(d),
            day_name = os.date("%a", os.time({year=y, month=m, day=d}))
        }

        -- Extract labels
        local tags = {}
        for _, label in ipairs(issue.labels) do
            table.insert(tags, label.name)
        end

        table.insert(events, {
            title = "#" .. issue.number .. " " .. issue.title,
            start_date = date,
            all_day = true,
            tags = tags,
            source_url = issue.url,
            id = "gh-" .. issue.number,
            status = "TODO",
        })
    end

    -- Save state
    state.save_plugin_state(M.name, {
        last_sync = os.time(),
        issue_count = #events,
    })

    return {
        events = events,
        stats = {
            count = #events,
            source = "GitHub " .. config.repo,
        }
    }
end

return M
```

## Testing

Test your plugin:

```lua
-- tests/test_myplugin.lua
local plugin = require("org_markdown.sync.plugins.myplugin")

T["sync"]["returns valid events"] = function()
    local result = plugin.sync()

    MiniTest.expect.truthy(result)
    MiniTest.expect.truthy(result.events)
    MiniTest.expect.truthy(#result.events > 0)

    -- Validate first event
    local event = result.events[1]
    MiniTest.expect.truthy(event.title)
    MiniTest.expect.truthy(event.start_date)
    MiniTest.expect.equality(type(event.all_day), "boolean")
end
```

## Best Practices

1. **Error Handling**: Always wrap API calls in pcall
2. **Validation**: Let the manager validate events (don't duplicate)
3. **Simplicity First**: Start with stateless syncs - add complexity only when needed
4. **Rate Limiting**: Respect API rate limits, handle 429 responses gracefully
5. **User Feedback**: Return meaningful stats in the stats table
6. **Testing**: Write tests for your sync function

## Publishing

Share your plugin:

1. Create Neovim plugin: `my-username/org-markdown-plugin-name`
2. Document installation in your README
3. Users install and configure:

```lua
{
    "my-username/org-markdown-plugin-name",
    dependencies = { "your-name/org-markdown" }
}

require("org_markdown").setup({
    sync = {
        external_plugins = { "org_markdown_plugin_name" }
    }
})
```
