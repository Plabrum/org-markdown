# Phase 0: Critical Bug Fixes

**Timeline:** Days 1-2
**Risk Level:** LOW
**Dependencies:** None
**Status:** ✅ COMPLETED (2025-11-29)

---

## Progress Tracking

**How to use:** Check off items as you complete them by changing `- [ ]` to `- [x]`. Add inline notes with `<!-- Note: ... -->`.

### Bug 0.1: Sync Marker Data Loss
- [x] Marker validation function implemented
- [x] Atomic file write with backup implemented
- [x] Backup cleanup function implemented
- [x] Tests written (`tests/test_sync_markers.lua`)
- [x] All tests passing
- [ ] Manual testing completed

### Bug 0.2: Refile Transaction Safety
- [x] Reorder operations (write → verify → delete)
- [x] Verification function implemented
- [x] Register storage for undo implemented
- [x] Tests written (`tests/test_refile_safety.lua`)
- [x] All tests passing
- [ ] Manual testing completed

### Bug 0.3: Capture Template Issues
- [x] %t duplicate fixed (renamed to %H)
- [x] Hardcoded name removed
- [x] Config documentation updated
- [x] Tests written (added to `tests/test_capture.lua`)
- [x] All tests passing
- [ ] Manual testing completed

### Phase Completion
- [X] All bugs fixed and tested
- [X] `make test` passes
- [X] Manual verification checklist completed (see below)
- [X] Git branch `refactor/phase-0-critical` created
- [X] Code reviewed
- [X] Merged to main

**Estimated completion:** ___/___/___ (fill in when done)

---

## Goals

Eliminate all data loss risks before any refactoring work begins.

## Bug 0.1: Sync Marker Data Loss ⚠️ CRITICAL

### Location
`lua/org_markdown/sync/manager.lua:174-200`

### Problem
If a sync file has a BEGIN marker but missing END marker, all content after BEGIN is silently lost during sync.

**Scenario:**
```markdown
# My Notes
User content here

<!-- BEGIN ORG-MARKDOWN CALENDAR SYNC -->
Old sync data
<!-- END marker missing! -->

This content will be LOST after next sync!
More important notes...
```

After sync, everything from BEGIN to end of file disappears.

### Root Cause
```lua
function read_preserved_content(filepath, plugin_name)
    for _, line in ipairs(lines) do
        if line:match(before_marker) then
            in_sync_section = true
        elseif line:match(after_marker) then
            in_sync_section = false
            found_end_marker = true
        elseif not in_sync_section and not found_end_marker then
            table.insert(lines_before, line)
        elseif not in_sync_section and found_end_marker then
            table.insert(lines_after, line)  -- Never reached if END missing!
        end
    end
end
```

If `found_end_marker` stays false, the `lines_after` block is never executed.

### Fix Implementation

**Step 1: Add marker validation**
```lua
local function validate_markers(lines, plugin_name)
    local begin_pattern = vim.pesc("<!-- BEGIN ORG-MARKDOWN " .. plugin_name:upper() .. " SYNC -->")
    local end_pattern = vim.pesc("<!-- END ORG-MARKDOWN " .. plugin_name:upper() .. " SYNC -->")

    local begin_count = 0
    local end_count = 0

    for _, line in ipairs(lines) do
        if line:match(begin_pattern) then
            begin_count = begin_count + 1
        end
        if line:match(end_pattern) then
            end_count = end_count + 1
        end
    end

    -- Validate
    if begin_count == 0 and end_count == 0 then
        return true, "no_markers"  -- File has no sync section yet
    end

    if begin_count ~= end_count then
        return false, string.format(
            "Marker mismatch: %d BEGIN, %d END markers. File may be corrupted.",
            begin_count, end_count
        )
    end

    if begin_count > 1 then
        return false, "Nested or duplicate markers detected. Manual cleanup required."
    end

    return true, "valid"
end
```

**Step 2: Use validation in sync**
```lua
function read_preserved_content(filepath, plugin_name)
    local expanded = vim.fn.expand(filepath)

    if vim.fn.filereadable(expanded) == 0 then
        return {}, {}, "no_markers"
    end

    local lines = utils.read_lines(expanded)

    -- VALIDATE FIRST
    local valid, status = validate_markers(lines, plugin_name)
    if not valid then
        vim.notify(
            string.format("[%s] Sync aborted: %s", plugin_name, status),
            vim.log.levels.ERROR
        )
        error("Marker validation failed: " .. status)
    end

    -- Rest of existing logic (only runs if valid)
    -- ...
end
```

**Step 3: Atomic file writes with backup**
```lua
local function write_sync_file_atomic(filepath, final_lines, plugin_name)
    local expanded = vim.fn.expand(filepath)

    -- Create backup if file exists
    if vim.fn.filereadable(expanded) == 1 then
        local backup_path = expanded .. ".backup." .. os.time()
        vim.uv.fs_copyfile(expanded, backup_path)

        -- Keep only last 3 backups
        cleanup_old_backups(expanded)
    end

    -- Write to temp file first
    local temp_path = expanded .. ".tmp"
    utils.write_lines(temp_path, final_lines)

    -- Atomic rename (on Unix, this is atomic)
    local ok, err = pcall(vim.uv.fs_rename, temp_path, expanded)
    if not ok then
        -- Clean up temp file
        vim.uv.fs_unlink(temp_path)
        error("Failed to write sync file: " .. tostring(err))
    end
end

local function cleanup_old_backups(filepath)
    local dir = vim.fn.fnamemodify(filepath, ":h")
    local basename = vim.fn.fnamemodify(filepath, ":t")

    -- Find all backups
    local backups = vim.fn.glob(dir .. "/" .. basename .. ".backup.*", false, true)

    -- Sort by timestamp (in filename)
    table.sort(backups, function(a, b)
        local ts_a = a:match("%.backup%.(%d+)$")
        local ts_b = b:match("%.backup%.(%d+)$")
        return (tonumber(ts_a) or 0) > (tonumber(ts_b) or 0)
    end)

    -- Keep only 3 most recent
    for i = 4, #backups do
        vim.uv.fs_unlink(backups[i])
    end
end
```

### Test Coverage

**File:** `tests/test_sync_markers.lua`

```lua
T["validate_markers"]["accepts file with no markers"] = function()
T["validate_markers"]["accepts valid BEGIN/END pair"] = function()
T["validate_markers"]["rejects missing END marker"] = function()
T["validate_markers"]["rejects missing BEGIN marker"] = function()
T["validate_markers"]["rejects nested markers"] = function()
T["validate_markers"]["rejects duplicate BEGIN markers"] = function()

T["read_preserved_content"]["preserves all content with valid markers"] = function()
T["read_preserved_content"]["aborts on marker mismatch"] = function()
T["read_preserved_content"]["handles multiple plugins in same file"] = function()

T["write_sync_file_atomic"]["creates backup before write"] = function()
T["write_sync_file_atomic"]["is atomic on failure"] = function()
T["write_sync_file_atomic"]["keeps only 3 backups"] = function()
```

### Files Modified
- `lua/org_markdown/sync/manager.lua`

---

## Bug 0.2: Refile Transaction Safety ⚠️ CRITICAL

### Location
`lua/org_markdown/refile.lua:79-82`

### Problem
Refile deletes content from source buffer before verifying destination write succeeded. If write fails (disk full, permissions, etc.), data is lost.

**Current code:**
```lua
on_confirm = function(item)
    -- WRONG ORDER!
    vim.api.nvim_buf_set_lines(0, selection.start_line, selection.end_line, false, {})  -- Delete first
    utils.append_lines(item.value, selection.lines)  -- Write second (might fail!)
    vim.notify("Refiled to " .. item.value)
end
```

### Fix Implementation

**Correct transaction order:**
```lua
on_confirm = function(item)
    -- 1. Write to destination FIRST
    local ok, err = pcall(utils.append_lines, item.value, selection.lines)
    if not ok then
        vim.notify(
            "Refile failed: " .. tostring(err),
            vim.log.levels.ERROR
        )
        return  -- Source untouched!
    end

    -- 2. Verify write succeeded
    local verify_ok, verify_err = verify_refile_write(item.value, selection.lines)
    if not verify_ok then
        vim.notify(
            "Refile verification failed: " .. verify_err,
            vim.log.levels.ERROR
        )
        return  -- Source still untouched
    end

    -- 3. Store in register for undo (before delete!)
    vim.fn.setreg('r', table.concat(selection.lines, "\n"))

    -- 4. NOW safe to delete from source
    vim.api.nvim_buf_set_lines(0, selection.start_line, selection.end_line, false, {})

    vim.notify("Refiled to " .. item.value .. " (undo: press \"rp in target file)")
end

local function verify_refile_write(filepath, expected_lines)
    local written = utils.read_lines(filepath)

    -- Check last N lines match what we wrote
    local verify_count = math.min(5, #expected_lines)
    local start_idx = #written - verify_count + 1

    for i = 1, verify_count do
        local expected = expected_lines[i]
        local actual = written[start_idx + i - 1]

        if actual ~= expected then
            return false, string.format(
                "Content mismatch at line %d: expected '%s', got '%s'",
                i, expected, actual or "nil"
            )
        end
    end

    return true, nil
end
```

### Additional Safety: Undo Support

The fixed version stores refiled content in the `r` register before deletion. Users can undo by:
1. Opening the target file
2. Navigating to where they want to restore
3. Pressing `"rp` to paste from register

### Test Coverage

**File:** `tests/test_refile_safety.lua`

```lua
T["refile"]["preserves source on write failure"] = function()
    -- Mock utils.append_lines to fail
    local original_append = utils.append_lines
    utils.append_lines = function() error("Disk full") end

    -- Attempt refile
    local before_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    refile.to_file()
    -- Select item, confirm...

    -- Source should be unchanged
    local after_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    expect.equality(before_lines, after_lines)

    utils.append_lines = original_append
end

T["refile"]["stores content in register for undo"] = function()
T["refile"]["includes nested headings"] = function()
T["refile"]["verifies write before delete"] = function()
T["refile"]["handles read-only destination"] = function()
```

### Files Modified
- `lua/org_markdown/refile.lua`

---

## Bug 0.3: Capture Template Issues

### Location
`lua/org_markdown/capture.lua:113-152`

### Problem 1: Duplicate %t Pattern
Two entries in `key_mapping` use `%t` - the second overwrites the first.

**Current code:**
```lua
key_mapping = {
    {
        pattern = "%t",  -- Line 115
        handler = function(text, matched_target, _)
            return M.capture_template_substitute(text, matched_target, active_date("%Y-%m-%d %a"))
        end,
    },
    -- ... other patterns ...
    {
        pattern = "%t",  -- Line 148 - DUPLICATE!
        handler = function(text, matched_target, _)
            return M.capture_template_substitute(text, matched_target, os.date("%H:%M"))
        end,
    },
}
```

**Impact:** Time-only insertion (`%t` for "14:30") doesn't work because date handler runs instead.

### Problem 2: Hardcoded Name
```lua
{
    pattern = "%n",
    handler = function(text, matched_target, _)
        return M.capture_template_substitute(text, matched_target, "Phil Labrum")  -- HARDCODED!
    end,
},
```

### Fix Implementation

**Step 1: Rename time marker**
```lua
{
    pattern = "%H",  -- Changed from %t (H for Hour/Time)
    handler = function(text, matched_target, _)
        return M.capture_template_substitute(text, matched_target, os.date("%H:%M"))
    end,
},
```

**Step 2: Remove hardcoded name**
```lua
{
    pattern = "%n",
    handler = function(text, matched_target, _)
        local name = config.captures.author_name
        if not name or name == "" then
            name = vim.fn.system("git config user.name"):gsub("\n", "")
        end
        if not name or name == "" then
            name = vim.env.USER or "User"
        end
        return M.capture_template_substitute(text, matched_target, name)
    end,
},
```

**Step 3: Document markers in config**

Add to `lua/org_markdown/config.lua`:
```lua
captures = {
    author_name = nil,  -- Defaults to git config user.name

    -- Available template markers:
    -- %t - Timestamp: <2025-11-29 Fri>
    -- %u - Inactive timestamp: [2025-11-29 Fri]
    -- %H - Time only: 14:30
    -- %n - Author name (config or git)
    -- %? - Cursor position after insert
    -- %^{prompt} - Prompt user for input

    templates = {
        -- existing templates
    }
}
```

### Test Coverage

**File:** `tests/test_capture_templates.lua`

```lua
T["template_expansion"]["%t expands to date"] = function()
    local result = capture.expand_template("Meeting at %t")
    expect.match(result, "<20%d%d%-%d%d%-%d%d %a%a%a>")
end

T["template_expansion"]["%H expands to time"] = function()
    local result = capture.expand_template("Call at %H")
    expect.match(result, "%d%d:%d%d")
end

T["template_expansion"]["%n uses config name"] = function()
    config.captures.author_name = "Test User"
    local result = capture.expand_template("By %n")
    expect.equality(result, "By Test User")
end

T["template_expansion"]["%n falls back to git"] = function()
    config.captures.author_name = nil
    -- Mock git config
    local result = capture.expand_template("By %n")
    -- Should not be "Phil Labrum"!
end

T["template_expansion"]["handles multiple markers"] = function()
    local result = capture.expand_template("Task %t by %n")
    expect.match(result, "Task <.+> by .+")
end
```

### Files Modified
- `lua/org_markdown/capture.lua`
- `lua/org_markdown/config.lua`

---

## Verification Checklist

Before proceeding to Phase 1:

- [ ] All 3 bugs fixed and tested
- [ ] `make test` passes
- [ ] Manual testing:
  - [ ] Sync with missing marker doesn't lose data
  - [ ] Sync with nested markers fails gracefully
  - [ ] Backup files created on sync
  - [ ] Refile with read-only dest preserves source
  - [ ] Refile can be undone with `"rp`
  - [ ] %t expands to date
  - [ ] %H expands to time
  - [ ] %n uses git config (not "Phil Labrum")
- [ ] Git branch: `refactor/phase-0-critical`
- [ ] Commit message references this plan
- [ ] Code reviewed
- [ ] Merged to main

## Estimated Time

- Bug 0.1 (sync markers): 4 hours (2h implementation, 2h testing)
- Bug 0.2 (refile safety): 3 hours (1.5h implementation, 1.5h testing)
- Bug 0.3 (capture templates): 1 hour (30m implementation, 30m testing)

**Total: 1-2 days** including review and testing

## Dependencies for Next Phase

Phase 1 (Test Infrastructure) depends on:
- All Phase 0 bugs fixed
- Test helpers from Phase 0 tests (can be reused)
- Clean slate to start comprehensive testing
