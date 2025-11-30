# Phase 2: Architecture Improvements

**Timeline:** Days 11-20
**Risk Level:** MEDIUM (refactoring core modules)
**Dependencies:** Phase 0 and Phase 1 complete
**Status:** Not Started

---

## Progress Tracking

**How to use:** Check off items as you complete them. Track line counts and performance metrics.

### 2.1 Agenda Formatter Deduplication
- [ ] `agenda_formatters.lua` module created
- [ ] `format_item()` unified function implemented
- [ ] Block formatter implemented
- [ ] Timeline formatter implemented
- [ ] `agenda.lua` updated to use new module
- [ ] Tests created (`tests/test_agenda_formatters.lua`)
- [ ] All tests passing
- [ ] Line count reduced: 772 → _____ (target: ~500)

### 2.2 Parser Single-Pass Optimization
- [ ] Pattern constants defined
- [ ] `parse_headline_unified()` implemented
- [ ] `extract_clean_text()` refactored
- [ ] `validate_time()` added
- [ ] Priority return format fixed (remove "#" prefix)
- [ ] All callers updated (agenda, sync)
- [ ] Tests updated and passing
- [ ] Performance benchmark: ___% improvement (target: 10-15%)

### 2.3 Config Deep Merge Fix
- [ ] `_defaults` immutable storage created
- [ ] `_runtime` mutable config created
- [ ] `merge_tables()` refactored (no mutation)
- [ ] Array handling fixed (replace not merge)
- [ ] Metatable `__index` implemented
- [ ] Tests passing (from Phase 1)
- [ ] Multiple `setup()` calls work correctly

### 2.4 DateTime Module
- [ ] `datetime.lua` module created
- [ ] `parse_org_date()` implemented
- [ ] `format_org_date()` implemented
- [ ] `compare_dates()` implemented
- [ ] `is_in_range()` implemented
- [ ] `validate_time()` implemented
- [ ] `today()` and `add_days()` implemented
- [ ] All modules updated to use datetime
- [ ] Tests created and passing

### Phase Completion
- [ ] All refactoring tasks completed
- [ ] All Phase 1 & 2 tests passing
- [ ] Performance benchmarks meet targets
- [ ] No regressions in functionality
- [ ] Git branch `refactor/phase-2-architecture` created
- [ ] Code reviewed
- [ ] Merged to main

**Estimated completion:** ___/___/___

---

## Goals

Reduce code duplication, improve abstractions, and make the codebase more maintainable. Test coverage from Phase 1 provides safety net for these changes.

## 2.1 Agenda Formatter Deduplication

### Problem

**Location:** `lua/org_markdown/agenda.lua:313-509`

90%+ code duplication between `flat` and `grouped` formatters. The only difference is indentation:

```lua
formatters = {
    blocks = {
        flat = function(item)
            if item.all_day then
                return "▓▓ " .. item.title .. " (all-day)" .. tags_str
            end
            -- 50 lines of box-drawing logic
        end,

        grouped = function(item)  -- NEARLY IDENTICAL!
            if item.all_day then
                return "    ▓▓ " .. item.title .. " (all-day)" .. tags_str  -- Just indented!
            end
            -- SAME 50 lines with "    " prefix
        end,
    }
}
```

**Impact:**
- 200+ lines duplicated
- Bug fixes must be applied twice
- Hard to add new formatters
- Difficult to maintain consistency

### Solution

Extract unified formatting with configuration options.

**Step 1: Create `agenda_formatters.lua` module**

**New File:** `lua/org_markdown/agenda_formatters.lua`

```lua
local M = {}

-- Main formatting entry point
function M.format_item(item, opts)
    opts = opts or {}

    local indent = opts.indent or ""
    local style = opts.style or "blocks"
    local box_width = opts.box_width or 50

    -- Build tags string
    local tags_str = ""
    if item.tags and #item.tags > 0 then
        tags_str = " :" .. table.concat(item.tags, ":") .. ":"
    end

    -- Route to appropriate formatter
    if item.all_day then
        return M.format_all_day(item, indent, style, tags_str)
    elseif item.start_time and item.end_time then
        return M.format_time_range(item, indent, style, tags_str, box_width)
    elseif item.start_time then
        return M.format_simple_time(item, indent, style, tags_str)
    else
        return M.format_simple(item, indent, style, tags_str)
    end
end

function M.format_all_day(item, indent, style, tags_str)
    if style == "blocks" then
        return indent .. "▓▓ " .. item.title .. " (all-day)" .. tags_str
    else -- timeline
        return indent .. "• " .. item.title .. " (all-day)" .. tags_str
    end
end

function M.format_time_range(item, indent, style, tags_str, box_width)
    if style == "blocks" then
        return M.format_time_range_blocks(item, indent, tags_str, box_width)
    else
        return M.format_time_range_timeline(item, indent, tags_str)
    end
end

function M.format_time_range_blocks(item, indent, tags_str, box_width)
    local lines = {}
    local time_str = item.start_time .. "-" .. item.end_time

    -- Top border
    table.insert(lines, indent .. "┌" .. string.rep("─", box_width - 2) .. "┐")

    -- Time line
    table.insert(lines, indent .. "│ " .. time_str .. string.rep(" ", box_width - #time_str - 4) .. "│")

    -- Title line
    local title_with_tags = item.title .. tags_str
    table.insert(lines, indent .. "│ " .. title_with_tags .. string.rep(" ", box_width - #title_with_tags - 4) .. "│")

    -- Bottom border
    table.insert(lines, indent .. "└" .. string.rep("─", box_width - 2) .. "┘")

    return table.concat(lines, "\n")
end

function M.format_time_range_timeline(item, indent, tags_str)
    return indent .. "⏰ " .. item.start_time .. "-" .. item.end_time .. " " .. item.title .. tags_str
end

function M.format_simple_time(item, indent, style, tags_str)
    if style == "blocks" then
        return indent .. "▶ " .. item.start_time .. " " .. item.title .. tags_str
    else
        return indent .. "⏰ " .. item.start_time .. " " .. item.title .. tags_str
    end
end

function M.format_simple(item, indent, style, tags_str)
    return indent .. "• " .. item.title .. tags_str
end

-- Export styles for registration
M.styles = {
    blocks = { box_width = 50 },
    timeline = {},
}

return M
```

**Step 2: Simplify agenda.lua formatters**

```lua
-- In agenda.lua
local agenda_formatters = require("org_markdown.agenda_formatters")

local formatters = {
    blocks = function(item, grouped)
        return agenda_formatters.format_item(item, {
            indent = grouped and "    " or "",
            style = "blocks",
            box_width = 50,
        })
    end,

    timeline = function(item, grouped)
        return agenda_formatters.format_item(item, {
            indent = grouped and "    " or "",
            style = "timeline",
        })
    end,
}
```

### Expected Results

- **Before:** 772 lines in agenda.lua
- **After:** ~500 lines in agenda.lua + 150 lines in agenda_formatters.lua
- **Net reduction:** ~120 lines
- **Maintainability:** Much easier to add new formatters
- **Testability:** Formatters can be unit tested independently

### Test Coverage

**New File:** `tests/test_agenda_formatters.lua`

```lua
T["format_item"]["formats all-day events in blocks style"] = function()
    local item = {
        title = "Birthday Party",
        all_day = true,
        tags = {"personal"}
    }

    local result = formatters.format_item(item, { style = "blocks" })
    MiniTest.expect.match(result, "▓▓ Birthday Party")
    MiniTest.expect.match(result, ":personal:")
end

T["format_item"]["formats time ranges in timeline style"] = function()
    local item = {
        title = "Meeting",
        start_time = "14:00",
        end_time = "15:30",
        tags = {}
    }

    local result = formatters.format_item(item, { style = "timeline" })
    MiniTest.expect.match(result, "⏰ 14:00%-15:30 Meeting")
end

T["format_item"]["applies indentation for grouped view"] = function()
    local item = { title = "Task", all_day = true, tags = {} }

    local result = formatters.format_item(item, {
        style = "blocks",
        indent = "    "
    })

    MiniTest.expect.match(result, "^    ")
end
```

### Files Modified
- `lua/org_markdown/agenda.lua` (reduced size)
- `lua/org_markdown/agenda_formatters.lua` (new)
- `tests/test_agenda_formatters.lua` (new)

---

## 2.2 Parser Single-Pass Optimization

### Problem

**Location:** `lua/org_markdown/utils/parser.lua`

Multiple issues:
1. Multiple regex passes over same string (inefficient)
2. Pattern order dependency (fragile)
3. `parse_text()` is a maintenance nightmare (10+ sequential gsub calls)
4. Inconsistent return formats (`priority` returns "#A", `state` returns "TODO")

### Solution

Create single-pass parser with pre-defined patterns and consistent output.

**Step 1: Define patterns once**

```lua
-- At top of parser.lua
local PATTERNS = {
    heading_prefix = "^(#+)%s+",
    state = "^([A-Z_]+)%s+",
    priority = "%[#([A-Z])%]",
    tracked_date = "<([^>]+)>",
    untracked_date = "%[([^%]]+)%]",
    time = "(%d%d):(%d%d)",
    tag_block = ":([%w_-]+):",
}

-- Pre-compile for vim.regex (if available)
local COMPILED = {}
if vim.regex then
    COMPILED.heading = vim.regex("^#\\+\\s\\+")
    -- etc...
end
```

**Step 2: Unified parse function**

```lua
function M.parse_headline_unified(line)
    -- Quick check: is it a heading?
    if not line:match(PATTERNS.heading_prefix) then
        return nil
    end

    local result = {
        state = nil,
        priority = nil,  -- Just letter, not "#A"
        tracked = nil,
        untracked = nil,
        start_time = nil,
        end_time = nil,
        all_day = true,
        tags = {},
        text = nil,
    }

    -- Extract state
    local state_match = line:match(PATTERNS.state)
    if state_match and valid_states[state_match] then
        result.state = state_match
    end

    -- Extract priority (just letter)
    result.priority = line:match(PATTERNS.priority)

    -- Extract dates
    for date_str in line:gmatch(PATTERNS.tracked_date) do
        if not result.tracked then
            result.tracked = M.parse_date_object(date_str)
        end
    end

    for date_str in line:gmatch(PATTERNS.untracked_date) do
        if not result.untracked then
            result.untracked = M.parse_date_object(date_str)
        end
    end

    -- Extract times
    local times = {}
    for hour, min in line:gmatch(PATTERNS.time) do
        local time_str = hour .. ":" .. min
        if M.validate_time(time_str) then
            table.insert(times, time_str)
        end
    end

    if #times > 0 then
        result.start_time = times[1]
        result.end_time = times[2] or times[1]
        result.all_day = false
    end

    -- Extract tags
    for tag in line:gmatch(PATTERNS.tag_block) do
        if tag ~= "" and not vim.tbl_contains(result.tags, tag) then
            table.insert(result.tags, tag)
        end
    end

    -- Extract clean text
    result.text = M.extract_clean_text(line, result)

    return result
end

function M.extract_clean_text(line, components)
    local text = line

    -- Remove components in order
    text = text:gsub(PATTERNS.heading_prefix, "")

    if components.state then
        text = text:gsub("^" .. vim.pesc(components.state) .. "%s+", "")
    end

    if components.priority then
        text = text:gsub("%[#" .. components.priority .. "%]%s*", "")
    end

    -- Remove all dates
    text = text:gsub(PATTERNS.tracked_date, "")
    text = text:gsub(PATTERNS.untracked_date, "")

    -- Remove tags
    text = text:gsub("%s+:" .. PATTERNS.tag_block .. "+:$", "")

    return vim.trim(text)
end

function M.validate_time(time_str)
    local h, m = time_str:match("(%d%d):(%d%d)")
    if not h then return false end

    local hour = tonumber(h)
    local min = tonumber(m)

    return hour >= 0 and hour < 24 and min >= 0 and min < 60
end
```

**Step 3: Update callers**

Anywhere that uses `parse_priority()` expecting "#A", change to expect just "A":

```lua
-- Before:
if item.priority == "#A" then ...

-- After:
if item.priority == "A" then ...

-- Or in display code:
local priority_str = item.priority and "[#" .. item.priority .. "]" or ""
```

### Expected Results

- **Performance:** 10-15% faster on large files
- **Maintainability:** Patterns defined once, easy to modify
- **Consistency:** All return values are raw data, not formatted
- **Testability:** Can test each extraction function independently

### Migration Strategy

1. Add `parse_headline_unified()` alongside existing `parse_headline()`
2. Add feature flag to switch between implementations
3. Test both paths with Phase 1 tests
4. Once validated, remove old implementation

### Test Coverage

```lua
T["parse_headline"]["extracts all components"] = function()
    local line = "## TODO [#A] <2025-11-29 Fri 14:00-15:30> Project Meeting :work:urgent:"

    local result = parser.parse_headline_unified(line)

    MiniTest.expect.equality(result.state, "TODO")
    MiniTest.expect.equality(result.priority, "A")  -- Not "#A"
    MiniTest.expect.truthy(result.tracked)
    MiniTest.expect.equality(result.start_time, "14:00")
    MiniTest.expect.equality(result.end_time, "15:30")
    MiniTest.expect.equality(result.all_day, false)
    MiniTest.expect.equality(#result.tags, 2)
    MiniTest.expect.equality(result.text, "Project Meeting")
end

T["validate_time"]["accepts valid times"] = function()
    MiniTest.expect.equality(parser.validate_time("00:00"), true)
    MiniTest.expect.equality(parser.validate_time("23:59"), true)
    MiniTest.expect.equality(parser.validate_time("12:30"), true)
end

T["validate_time"]["rejects invalid times"] = function()
    MiniTest.expect.equality(parser.validate_time("24:00"), false)
    MiniTest.expect.equality(parser.validate_time("12:60"), false)
    MiniTest.expect.equality(parser.validate_time("99:99"), false)
end
```

### Files Modified
- `lua/org_markdown/utils/parser.lua`
- `lua/org_markdown/agenda.lua` (update callers)
- `lua/org_markdown/sync/manager.lua` (update callers)

---

## 2.3 Config Deep Merge Fix

### Problem

**Location:** `lua/org_markdown/config.lua:111-119`

Deep merge mutates the default config table, causing issues:
- Multiple `setup()` calls accumulate changes
- Can't reset to defaults
- Tests interfere with each other
- Arrays merge as objects instead of replacing

### Solution

Store immutable defaults, create fresh runtime config on each setup.

```lua
-- Store defaults separately (never modified)
M._defaults = {
    captures = {
        author_name = nil,
        templates = {
            -- default templates
        }
    },
    agendas = {
        -- default agenda config
    },
    -- ... all other defaults
}

-- Runtime config (created fresh on each setup)
M._runtime = {}

local function merge_tables(default, user)
    local result = {}

    -- First, copy all from default
    for k, v in pairs(default) do
        if type(v) == "table" then
            if vim.tbl_islist(v) then
                -- Arrays: deep copy (will be replaced if user provides)
                result[k] = vim.deepcopy(v)
            else
                -- Objects: deep copy (will be merged if user provides)
                result[k] = vim.deepcopy(v)
            end
        else
            result[k] = v
        end
    end

    -- Then, apply user overrides
    for k, v in pairs(user) do
        if type(v) == "table" and type(result[k]) == "table" then
            if vim.tbl_islist(v) then
                -- Arrays: REPLACE entirely
                result[k] = vim.deepcopy(v)
            else
                -- Objects: MERGE recursively
                result[k] = merge_tables(result[k], v)
            end
        else
            result[k] = v
        end
    end

    return result
end

function M.setup(user_config)
    -- Create fresh runtime config
    M._runtime = merge_tables(M._defaults, user_config or {})

    -- Validate
    local ok, err = validate_config(M._runtime)
    if not ok then
        error("Invalid configuration: " .. err)
    end

    return M._runtime
end

-- Allow access via config.field (reads from runtime)
setmetatable(M, {
    __index = function(t, k)
        if k == "_defaults" or k == "_runtime" or k == "setup" then
            return rawget(t, k)
        end
        return t._runtime[k] or t._defaults[k]
    end
})
```

### Expected Results

- Multiple `setup()` calls work correctly
- Tests can call setup without interference
- Arrays replace instead of merge
- Defaults never mutate

### Test Coverage

Already covered in Phase 1 (`tests/test_config_comprehensive.lua`)

### Files Modified
- `lua/org_markdown/config.lua`

---

## 2.4 Extract DateTime Module

### Problem

Date/time handling is scattered across multiple files with duplicated logic:
- `parser.lua`: Date parsing
- `agenda.lua`: Date comparisons, ranges
- `sync/manager.lua`: Date formatting
- `sync/plugins/calendar.lua`: macOS date parsing

### Solution

Centralize all date/time operations in a dedicated module.

**New File:** `lua/org_markdown/utils/datetime.lua`

```lua
local M = {}

-- Parse org-mode date: <2025-11-29 Fri> or [2025-11-29 Fri]
function M.parse_org_date(str)
    local bracket = str:sub(1, 1)
    local y, m, d, day = str:match("(%d%d%d%d)-(%d%d)-(%d%d)%s+(%a%a%a)")

    if not y then
        return nil, "Invalid date format"
    end

    return {
        year = tonumber(y),
        month = tonumber(m),
        day = tonumber(d),
        day_name = day,
        tracked = bracket == "<",
    }
end

-- Format date object to org-mode string
function M.format_org_date(date, time)
    if not date then return "" end

    local bracket_open = date.tracked and "<" or "["
    local bracket_close = date.tracked and ">" or "]"

    local str = string.format("%s%04d-%02d-%02d %s",
        bracket_open,
        date.year,
        date.month,
        date.day,
        date.day_name or os.date("%a", os.time(date))
    )

    if time then
        str = str .. " " .. time
    end

    return str .. bracket_close
end

-- Compare two date objects (-1, 0, 1)
function M.compare_dates(a, b)
    if not a or not b then
        return a and 1 or -1  -- nil sorts to end
    end

    if a.year ~= b.year then
        return a.year < b.year and -1 or 1
    end
    if a.month ~= b.month then
        return a.month < b.month and -1 or 1
    end
    if a.day ~= b.day then
        return a.day < b.day and -1 or 1
    end
    return 0
end

-- Check if date is in range (inclusive)
function M.is_in_range(date, start_date, end_date)
    return M.compare_dates(date, start_date) >= 0
       and M.compare_dates(date, end_date) <= 0
end

-- Validate time string HH:MM
function M.validate_time(time_str)
    if not time_str or type(time_str) ~= "string" then
        return false
    end

    local h, m = time_str:match("^(%d%d):(%d%d)$")
    if not h then return false end

    local hour = tonumber(h)
    local min = tonumber(m)

    return hour >= 0 and hour < 24 and min >= 0 and min < 60
end

-- Get current date as org date object
function M.today()
    local now = os.date("*t")
    return {
        year = now.year,
        month = now.month,
        day = now.day,
        day_name = os.date("%a"),
        tracked = true,
    }
end

-- Add days to a date
function M.add_days(date, days)
    local timestamp = os.time({
        year = date.year,
        month = date.month,
        day = date.day,
    })

    timestamp = timestamp + (days * 24 * 60 * 60)

    local new_date = os.date("*t", timestamp)
    return {
        year = new_date.year,
        month = new_date.month,
        day = new_date.day,
        day_name = os.date("%a", timestamp),
        tracked = date.tracked,
    }
end

-- Get date range (for filtering)
function M.get_date_range(opts)
    opts = opts or {}

    local start_date
    local end_date

    if opts.from and opts.to then
        -- Explicit range
        start_date = M.parse_org_date(opts.from)
        end_date = M.parse_org_date(opts.to)
    elseif opts.days then
        -- Relative range (e.g., next 7 days)
        start_date = M.today()
        if opts.offset then
            start_date = M.add_days(start_date, opts.offset)
        end
        end_date = M.add_days(start_date, opts.days)
    else
        return nil, "Invalid date range specification"
    end

    return start_date, end_date
end

return M
```

### Usage Examples

```lua
-- In parser.lua
local datetime = require("org_markdown.utils.datetime")

function M.parse_headline(line)
    -- ...
    local tracked_str = line:match("<([^>]+)>")
    if tracked_str then
        result.tracked = datetime.parse_org_date("<" .. tracked_str .. ">")
    end
    -- ...
end

-- In agenda.lua
local datetime = require("org_markdown.utils.datetime")

function compare_items(a, b, sort_spec)
    if sort_spec.by == "date" then
        return datetime.compare_dates(a.date, b.date)
    end
end
```

### Expected Results

- All date logic in one place
- Consistent date handling across modules
- Easier to add date features (recurrence, timezones, etc.)
- Better testable

### Files Modified
- `lua/org_markdown/utils/datetime.lua` (new)
- `lua/org_markdown/utils/parser.lua`
- `lua/org_markdown/agenda.lua`
- `lua/org_markdown/sync/manager.lua`

---

## Success Criteria

Before proceeding to Phase 3:

- [ ] Agenda formatters deduplicated
- [ ] agenda.lua reduced from 772 → ~500 lines
- [ ] Parser uses single-pass approach
- [ ] Parser 10-15% faster on benchmarks
- [ ] Config setup doesn't mutate defaults
- [ ] Multiple config.setup() calls work correctly
- [ ] DateTime module handles all date operations
- [ ] All Phase 1 tests still pass
- [ ] New tests for formatters, parser, datetime pass
- [ ] Git branch: `refactor/phase-2-architecture`
- [ ] Code reviewed
- [ ] Merged to main

## Estimated Time

- Formatter deduplication: 6 hours
- Parser refactor: 8 hours
- Config fix: 4 hours
- DateTime module: 6 hours
- Testing and integration: 8 hours

**Total: 2 weeks** (10 working days)
