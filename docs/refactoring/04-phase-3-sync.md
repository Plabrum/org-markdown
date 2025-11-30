# Phase 3: Sync System Hardening

**Timeline:** Days 21-28
**Risk Level:** MEDIUM (event model changes, backwards compatibility needed)
**Dependencies:** Phases 0, 1, and 2 complete
**Status:** Completed ✅

**Note**: Section 3.3 (Plugin State Persistence) was removed as premature optimization. State persistence can be added later when there's an actual use case (e.g., API-based plugins with `since` support). Current calendar plugin doesn't benefit from it.

---

## Progress Tracking

**How to use:** Check off items as you complete them. Note any plugins updated with extended fields.

### 3.1 Event Validation Layer
- [ ] `EVENT_SCHEMA` defined in sync/manager.lua
- [ ] `validate_event()` function implemented
- [ ] Validation integrated into `sync_plugin()`
- [ ] Error messages clear and actionable
- [ ] Invalid event handling tested
- [ ] Tests passing (from Phase 1)

### 3.2 Expand Event Data Model
- [ ] Extended fields added to schema:
  - [ ] `id` field
  - [ ] `source_url` field
  - [ ] `location` field
  - [ ] `description` field
  - [ ] `status` field
  - [ ] `priority` field
- [ ] `format_event_as_markdown()` updated
- [ ] Calendar plugin updated to use extended fields
- [ ] Metadata section rendering correctly
- [ ] Tests updated and passing

### 3.3 Plugin State Persistence ~~(REMOVED - Premature Optimization)~~
- [x] ~~`sync/state.lua` module created~~ - Removed as unnecessary
- [x] ~~State directory creation implemented~~ - Not needed yet
- [x] ~~`load_plugin_state()` implemented~~ - Can add when needed
- [x] ~~`save_plugin_state()` implemented~~ - Can add when needed
- [x] ~~Atomic JSON writes working~~ - Not implemented
- [x] ~~`:MarkdownSyncDebugState` command added~~ - Removed
- [x] ~~Calendar plugin uses state for incremental sync~~ - Can't do incremental (AppleScript limitation)
- [x] ~~Tests created and passing~~ - N/A

### 3.4 Plugin Interface Documentation
- [ ] `PLUGIN_INTERFACE.md` created
- [ ] Required fields documented
- [ ] Optional fields documented
- [ ] Event schema documented
- [ ] State persistence documented
- [ ] Complete example plugin included
- [ ] Best practices section added
- [ ] Publishing instructions added

### Phase Completion
- [x] All sync hardening tasks completed (state persistence removed as premature)
- [x] Event validation catches all invalid events
- [x] ~~State persistence working across sessions~~ - Not implemented (YAGNI)
- [x] Documentation complete and accurate
- [x] All previous tests still passing
- [ ] Git branch `refactor/phase-3-sync` created
- [ ] Code reviewed
- [ ] Merged to main

**Plugins updated:** <!-- List plugins that now use extended fields -->

**Estimated completion:** ___/___/___

---

## Goals

Harden the sync plugin system for production use with multiple plugins. Add validation, expand event model, enable incremental sync, and provide complete documentation for plugin developers.

## 3.1 Event Validation Layer

### Problem

Currently, sync plugins can return malformed events that cause:
- Silent failures during formatting
- Cryptic errors shown to users
- Partial sync corruption
- No way to debug what went wrong

### Solution

Add comprehensive event validation before formatting.

**Step 1: Define Event Schema**

Add to `lua/org_markdown/sync/manager.lua`:

```lua
local EVENT_SCHEMA = {
    -- Required fields
    title = {
        type = "string",
        required = true,
        validate = function(v) return v and v ~= "" end,
        error_msg = "title must be non-empty string"
    },

    start_date = {
        type = "table",
        required = true,
        validate = function(v)
            return v and v.year and v.month and v.day and v.day_name
        end,
        error_msg = "start_date must have year, month, day, day_name"
    },

    all_day = {
        type = "boolean",
        required = true,
        error_msg = "all_day must be boolean"
    },

    -- Optional fields
    end_date = {
        type = "table",
        required = false,
        validate = function(v)
            return not v or (v.year and v.month and v.day)
        end,
        error_msg = "end_date must have year, month, day if provided"
    },

    start_time = {
        type = "string",
        required = false,
        validate = function(v)
            local datetime = require("org_markdown.utils.datetime")
            return not v or datetime.validate_time(v)
        end,
        error_msg = "start_time must be HH:MM format"
    },

    end_time = {
        type = "string",
        required = false,
        validate = function(v)
            local datetime = require("org_markdown.utils.datetime")
            return not v or datetime.validate_time(v)
        end,
        error_msg = "end_time must be HH:MM format"
    },

    tags = {
        type = "table",
        required = false,
        validate = function(v)
            return not v or vim.tbl_islist(v)
        end,
        error_msg = "tags must be array of strings"
    },

    body = {
        type = "string",
        required = false,
    },

    -- Extended fields (Phase 3)
    id = { type = "string", required = false },
    source_url = { type = "string", required = false },
    location = { type = "string", required = false },
    description = { type = "string", required = false },
    status = {
        type = "string",
        required = false,
        validate = function(v)
            local valid_states = {"TODO", "IN_PROGRESS", "WAITING", "DONE", "CANCELLED", "BLOCKED"}
            return not v or vim.tbl_contains(valid_states, v)
        end,
        error_msg = "status must be valid state"
    },
    priority = {
        type = "string",
        required = false,
        validate = function(v)
            return not v or v:match("^[A-Z]$")
        end,
        error_msg = "priority must be single uppercase letter"
    },
}
```

**Step 2: Implement Validation**

```lua
function validate_event(event, plugin_name)
    if not event or type(event) ~= "table" then
        return false, {"Event must be a table"}
    end

    local errors = {}

    for field_name, schema in pairs(EVENT_SCHEMA) do
        local value = event[field_name]

        -- Check required
        if schema.required and value == nil then
            table.insert(errors, field_name .. " is required")
            goto continue
        end

        -- Skip further validation if optional and not provided
        if not schema.required and value == nil then
            goto continue
        end

        -- Check type
        if type(value) ~= schema.type then
            table.insert(errors, string.format(
                "%s must be %s, got %s",
                field_name,
                schema.type,
                type(value)
            ))
            goto continue
        end

        -- Custom validation
        if schema.validate and not schema.validate(value) then
            table.insert(errors, schema.error_msg or field_name .. " is invalid")
        end

        ::continue::
    end

    if #errors > 0 then
        local err_msg = string.format(
            "[%s] Invalid event '%s':\n  - %s",
            plugin_name,
            event.title or "(no title)",
            table.concat(errors, "\n  - ")
        )
        return false, errors, err_msg
    end

    return true, nil, nil
end
```

**Step 3: Use in sync_plugin**

```lua
function M.sync_plugin(plugin_name)
    -- ... existing code to get plugin and call sync() ...

    if not result or not result.events then
        vim.notify("[" .. plugin_name .. "] No events returned", vim.log.levels.WARN)
        return
    end

    -- Validate each event
    local valid_events = {}
    local invalid_count = 0

    for i, event in ipairs(result.events) do
        local valid, errors, err_msg = validate_event(event, plugin_name)

        if valid then
            table.insert(valid_events, event)
        else
            invalid_count = invalid_count + 1

            -- Log first few errors in detail
            if invalid_count <= 3 then
                vim.notify(err_msg, vim.log.levels.WARN)
            end
        end
    end

    if invalid_count > 3 then
        vim.notify(string.format(
            "[%s] %d more events invalid (not shown)",
            plugin_name,
            invalid_count - 3
        ), vim.log.levels.WARN)
    end

    -- Continue with valid events only
    if #valid_events == 0 then
        vim.notify("[" .. plugin_name .. "] No valid events to sync", vim.log.levels.ERROR)
        return
    end

    local events_markdown = format_events_as_markdown(valid_events, config.sync.plugins[plugin_name])
    -- ... rest of sync logic ...
end
```

### Expected Results

- Invalid events caught early with clear error messages
- Plugin bugs easy to debug
- Partial sync possible (valid events still processed)
- Users understand what went wrong

### Test Coverage

Already covered in Phase 1 (`tests/test_sync_comprehensive.lua`)

### Files Modified
- `lua/org_markdown/sync/manager.lua`

---

## 3.2 Expand Event Data Model

### Problem

Current event model is minimal - only supports basic calendar events. Need to support:
- Event IDs (for tracking updates across syncs)
- Source URLs (link back to original)
- Location and attendees
- Status and priority (for task-style events)
- Rich descriptions separate from body

### Solution

Expand event schema (already done in 3.1) and update formatter.

**Update Formatter:**

```lua
function format_event_as_markdown(event, config)
    local lines = {}

    -- Build heading
    local heading_parts = {
        string.rep("#", config.heading_level or 3)
    }

    -- Add status if present
    if event.status then
        table.insert(heading_parts, event.status)
    end

    -- Add priority if present
    if event.priority then
        table.insert(heading_parts, "[#" .. event.priority .. "]")
    end

    -- Add title
    table.insert(heading_parts, event.title)

    local heading = table.concat(heading_parts, " ")

    -- Add tags
    if event.tags and #event.tags > 0 then
        heading = heading .. " :" .. table.concat(event.tags, ":") .. ":"
    end

    table.insert(lines, heading)

    -- Add date/time line
    if event.start_date then
        local date_line = format_date_range(event)
        table.insert(lines, date_line)
    end

    -- Add metadata section
    local metadata = {}

    if event.location then
        table.insert(metadata, "**Location:** " .. event.location)
    end

    if event.source_url then
        table.insert(metadata, "**Source:** " .. event.source_url)
    end

    if event.id then
        table.insert(metadata, "**ID:** `" .. event.id .. "`")
    end

    if #metadata > 0 then
        table.insert(lines, "")
        for _, line in ipairs(metadata) do
            table.insert(lines, line)
        end
    end

    -- Add description/body
    if event.description then
        table.insert(lines, "")
        table.insert(lines, event.description)
    elseif event.body then
        table.insert(lines, "")
        table.insert(lines, event.body)
    end

    return lines
end
```

### Usage in Calendar Plugin

Update `sync/plugins/calendar.lua`:

```lua
function M.sync()
    local events = fetch_calendar_events(...)

    local formatted_events = {}
    for _, raw_event in ipairs(events) do
        table.insert(formatted_events, {
            title = raw_event.summary,
            start_date = parse_date(raw_event.start_date),
            end_date = raw_event.end_date and parse_date(raw_event.end_date),
            start_time = raw_event.start_time,
            end_time = raw_event.end_time,
            all_day = raw_event.all_day,
            tags = {sanitize_tag(raw_event.calendar_name)},

            -- NEW: Extended fields
            id = raw_event.uid,  -- Calendar UID
            location = raw_event.location,
            source_url = raw_event.url,
            body = raw_event.notes,
        })
    end

    return {
        events = formatted_events,
        stats = {
            count = #formatted_events,
            date_range = ...,
        }
    }
end
```

### Expected Results

- Richer event representation
- Click URLs to go to original source
- Location information preserved
- Event IDs enable future update tracking

### Files Modified
- `lua/org_markdown/sync/manager.lua`
- `lua/org_markdown/sync/plugins/calendar.lua`

---

## 3.3 Plugin State Persistence

### Problem

Plugins cannot save state between syncs, preventing:
- Incremental sync (must fetch all events every time)
- Rate limiting tracking
- Last sync timestamp
- Cursor/pagination tokens

### Solution

Create state persistence layer with JSON storage.

**New File:** `lua/org_markdown/sync/state.lua`

```lua
local M = {}

-- State file location
local state_dir = vim.fn.stdpath("data") .. "/org-markdown"
local state_file = state_dir .. "/sync-state.json"

-- Ensure state directory exists
function M.ensure_state_dir()
    if vim.fn.isdirectory(state_dir) == 0 then
        vim.fn.mkdir(state_dir, "p")
    end
end

-- Load all state (internal)
local function load_all_state()
    M.ensure_state_dir()

    if vim.fn.filereadable(state_file) == 0 then
        return {}
    end

    local content = vim.fn.readfile(state_file)
    if #content == 0 then
        return {}
    end

    local ok, state = pcall(vim.json.decode, table.concat(content, "\n"))
    if not ok then
        vim.notify("Failed to parse sync state: " .. tostring(state), vim.log.levels.WARN)
        return {}
    end

    return state
end

-- Save all state (internal)
local function save_all_state(all_state)
    M.ensure_state_dir()

    local json = vim.json.encode(all_state)

    -- Atomic write
    local temp = state_file .. ".tmp"
    vim.fn.writefile(vim.split(json, "\n"), temp)
    vim.uv.fs_rename(temp, state_file)
end

-- Public API: Load state for specific plugin
function M.load_plugin_state(plugin_name)
    local all_state = load_all_state()
    return all_state[plugin_name] or {}
end

-- Public API: Save state for specific plugin
function M.save_plugin_state(plugin_name, state)
    local all_state = load_all_state()
    all_state[plugin_name] = state
    save_all_state(all_state)
end

-- Public API: Clear state for specific plugin
function M.clear_plugin_state(plugin_name)
    local all_state = load_all_state()
    all_state[plugin_name] = nil
    save_all_state(all_state)
end

-- Public API: Get all plugin states (for debugging)
function M.get_all_states()
    return load_all_state()
end

return M
```

### Usage in Plugins

```lua
-- In calendar.lua
function M.sync()
    local state = require("org_markdown.sync.state")

    -- Load last sync info
    local last_sync = state.load_plugin_state("calendar")
    local last_timestamp = last_sync.last_sync_timestamp or 0

    -- Fetch only events modified since last sync
    local events = fetch_events_since(last_timestamp)

    -- Save new state
    state.save_plugin_state("calendar", {
        last_sync_timestamp = os.time(),
        event_count = #events,
        last_calendar = config.sync.plugins.calendar.include_calendars[1],
    })

    return { events = events }
end
```

### Add Debug Command

Add to `commands.lua`:

```lua
vim.api.nvim_create_user_command("MarkdownSyncDebugState", function()
    local state = require("org_markdown.sync.state")
    local all_states = state.get_all_states()

    local lines = {"# Sync Plugin States", ""}
    for plugin_name, plugin_state in pairs(all_states) do
        table.insert(lines, "## " .. plugin_name)
        for k, v in pairs(plugin_state) do
            table.insert(lines, "- " .. k .. ": " .. vim.inspect(v))
        end
        table.insert(lines, "")
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
    vim.api.nvim_set_current_buf(buf)
end, {})
```

### Expected Results

- Plugins can do incremental sync
- State persists across Neovim sessions
- Easy to debug state with `:MarkdownSyncDebugState`

### Files Modified
- `lua/org_markdown/sync/state.lua` (new)
- `lua/org_markdown/sync/plugins/calendar.lua`
- `lua/org_markdown/commands.lua`

---

## 3.4 Plugin Interface Documentation

### Problem

No comprehensive documentation for external plugin developers. Current info is scattered in:
- CLAUDE.md (brief interface description)
- calendar.lua (example only)
- No API reference

### Solution

Create complete plugin development guide.

**New File:** `lua/org_markdown/sync/PLUGIN_INTERFACE.md`

```markdown
# Sync Plugin Interface Documentation

## Overview

The sync plugin system allows you to sync events from external sources (calendars, task managers, issue trackers) into your markdown files.

## Quick Start

### Minimal Plugin

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

## State Persistence

Save state between syncs for incremental updates.

```lua
function M.sync()
    local state = require("org_markdown.sync.state")

    -- Load previous state
    local last_sync = state.load_plugin_state(M.name)
    local since = last_sync.last_cursor or "beginning"

    -- Fetch incrementally
    local events, next_cursor = fetch_events_since(since)

    -- Save new state
    state.save_plugin_state(M.name, {
        last_cursor = next_cursor,
        last_sync_time = os.time(),
        event_count = #events,
    })

    return { events = events }
end
```

**Debug state:**
```vim
:MarkdownSyncDebugState
```

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

See `lua/org_markdown/sync/plugins/calendar.lua` for production reference.

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
3. **Incremental Sync**: Use state persistence for large data sets
4. **Rate Limiting**: Respect API rate limits, save tokens in state
5. **User Feedback**: Return meaningful stats
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
```

### Files Created
- `lua/org_markdown/sync/PLUGIN_INTERFACE.md` (new)

---

## Success Criteria

- [ ] Event validation catches all malformed events
- [ ] Extended event model supports id, source_url, location, status, priority
- [ ] Plugin state persistence working
- [ ] `:MarkdownSyncDebugState` command shows all plugin states
- [ ] Complete plugin interface documentation
- [ ] Calendar plugin uses extended fields
- [ ] All Phase 1 & 2 tests still pass
- [ ] Git branch: `refactor/phase-3-sync`
- [ ] Code reviewed
- [ ] Merged to main

## Estimated Time

- Event validation: 4 hours
- Event model expansion: 4 hours
- State persistence: 6 hours
- Documentation: 6 hours
- Testing and integration: 4 hours

**Total: 1 week** (5-7 working days)
