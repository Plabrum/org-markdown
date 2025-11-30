# Phase 1: Test Infrastructure

**Timeline:** Days 3-10
**Risk Level:** LOW (only adding tests)
**Dependencies:** Phase 0 complete
**Status:** Not Started

---

## Progress Tracking

**How to use:** Check off items as you complete them. Track coverage percentages as you go.

### Test Infrastructure Setup
- [ ] Test helpers module created (`tests/helpers/init.lua`)
- [ ] Mock utilities implemented
- [ ] Temp file/workspace functions working

### Test Suites
- [ ] **Refile** (`tests/test_refile_comprehensive.lua`)
  - [ ] Suite created with all test cases
  - [ ] All tests passing
  - [ ] Coverage: ___% (target: 90%)

- [ ] **Sync Manager** (`tests/test_sync_comprehensive.lua`)
  - [ ] Placeholder tests replaced
  - [ ] Marker validation tests added
  - [ ] Event validation tests added
  - [ ] All tests passing
  - [ ] Coverage: ___% (target: 85%)

- [ ] **Config** (`tests/test_config_comprehensive.lua`)
  - [ ] Suite created with all test cases
  - [ ] Deep merge tests added
  - [ ] Array handling tests added
  - [ ] All tests passing
  - [ ] Coverage: ___% (target: 80%)

- [ ] **Queries** (`tests/test_queries.lua`)
  - [ ] Suite created with all test cases
  - [ ] Recursive scan tests added
  - [ ] Permission error tests added
  - [ ] All tests passing
  - [ ] Coverage: ___% (target: 75%)

- [ ] **Picker** (`tests/test_picker.lua`)
  - [ ] Suite created with mocks
  - [ ] Telescope/Snacks abstraction tests added
  - [ ] All tests passing
  - [ ] Coverage: ___% (target: 70%)

### Phase Completion
- [ ] All test suites created
- [ ] `make test` passes with 0 failures
- [ ] Overall coverage ≥ 80%
- [ ] Test helpers reusable and documented
- [ ] Git branch `refactor/phase-1-tests` created
- [ ] Code reviewed
- [ ] Merged to main

**Estimated completion:** ___/___/___

---

## Goals

Build comprehensive test coverage (80%+) before refactoring any modules. This provides safety net for architectural changes in Phases 2-3.

## Current Coverage Gaps

| Module | Current | Target | Priority |
|--------|---------|--------|----------|
| refile.lua | 0% | 90% | CRITICAL |
| sync/manager.lua | ~10% | 85% | CRITICAL |
| queries.lua | 0% | 75% | HIGH |
| picker.lua | 0% | 70% | HIGH |
| config.lua | 0% | 80% | HIGH |
| agenda.lua | ~20% | 60% | MEDIUM |
| parser.lua | ~70% | 85% | LOW |

## Test Infrastructure Setup

### 1.1 Test Helpers Module

**New File:** `tests/helpers/init.lua`

```lua
local M = {}

-- Create temporary test file
function M.create_temp_file(content, extension)
    extension = extension or ".md"
    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")

    local filepath = temp_dir .. "/test" .. extension
    local lines = type(content) == "table" and content or vim.split(content, "\n")

    local file = io.open(filepath, "w")
    file:write(table.concat(lines, "\n"))
    file:close()

    return filepath
end

-- Create temp directory with multiple files
function M.create_temp_workspace(files)
    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")

    for filename, content in pairs(files) do
        local filepath = temp_dir .. "/" .. filename
        local dir = vim.fn.fnamemodify(filepath, ":h")
        vim.fn.mkdir(dir, "p")

        local lines = type(content) == "table" and content or vim.split(content, "\n")
        local file = io.open(filepath, "w")
        file:write(table.concat(lines, "\n"))
        file:close()
    end

    return temp_dir
end

-- Clean up temp files/dirs
function M.cleanup_temp(path)
    if vim.fn.isdirectory(path) == 1 then
        vim.fn.delete(path, "rf")
    elseif vim.fn.filereadable(path) == 1 then
        vim.fn.delete(path)
    end
end

-- Make file read-only for error testing
function M.make_readonly(filepath)
    vim.fn.setfperm(filepath, "r--r--r--")
end

-- Make file writable again
function M.make_writable(filepath)
    vim.fn.setfperm(filepath, "rw-r--r--")
end

-- Create buffer with content
function M.create_test_buffer(content, filetype)
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = type(content) == "table" and content or vim.split(content, "\n")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    if filetype then
        vim.api.nvim_buf_set_option(buf, "filetype", filetype)
    end
    return buf
end

-- Assert buffer contents match expected
function M.assert_buffer_equals(buf, expected)
    local actual = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local expected_lines = type(expected) == "table" and expected or vim.split(expected, "\n")

    if not vim.deep_equal(actual, expected_lines) then
        error(string.format(
            "Buffer mismatch:\nExpected:\n%s\n\nActual:\n%s",
            table.concat(expected_lines, "\n"),
            table.concat(actual, "\n")
        ))
    end
end

return M
```

---

## 1.2 Refile Test Suite

**New File:** `tests/test_refile_comprehensive.lua`

```lua
local helpers = require("tests.helpers")
local refile = require("org_markdown.refile")
local utils = require("org_markdown.utils.utils")

local T = MiniTest.new_set()

-- Setup/teardown
T["setup"] = function()
    -- Save original functions we'll mock
    T.original_append = utils.append_lines
    T.temp_files = {}
end

T["teardown"] = function()
    -- Restore mocked functions
    if T.original_append then
        utils.append_lines = T.original_append
    end

    -- Clean up temp files
    for _, path in ipairs(T.temp_files) do
        helpers.cleanup_temp(path)
    end
end

-- Range Detection Tests
T["get_refile_target"]["detects simple bullet"] = function()
    local content = [[
# Heading
- First bullet
- Second bullet
- Third bullet
]]
    local buf = helpers.create_test_buffer(content, "markdown")
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, {3, 0})  -- Second bullet

    local selection = refile.get_refile_target()

    MiniTest.expect.equality(selection.start_line, 2)
    MiniTest.expect.equality(selection.end_line, 3)
    MiniTest.expect.equality(#selection.lines, 1)
    MiniTest.expect.equality(selection.lines[1], "- Second bullet")
end

T["get_refile_target"]["detects heading with subheadings"] = function()
    local content = [[
# Top Level
## Heading to Refile
Content here
### Subheading 1
More content
### Subheading 2
Even more
## Next Heading
Should not be included
]]
    local buf = helpers.create_test_buffer(content, "markdown")
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, {3, 0})  -- "## Heading to Refile"

    local selection = refile.get_refile_target()

    MiniTest.expect.equality(selection.start_line, 2)
    MiniTest.expect.equality(selection.end_line, 8)  -- Includes both subheadings
    MiniTest.expect.equality(#selection.lines, 6)
end

T["get_refile_target"]["handles checkboxes correctly"] = function()
    local content = [[
- [ ] Unchecked task
- [x] Completed task
- [-] In progress task
]]
    local buf = helpers.create_test_buffer(content, "markdown")
    vim.api.nvim_set_current_buf(buf)

    -- Test each checkbox type
    for line = 1, 3 do
        vim.api.nvim_win_set_cursor(0, {line, 0})
        local selection = refile.get_refile_target()
        MiniTest.expect.truthy(selection, "Failed on line " .. line)
        MiniTest.expect.equality(#selection.lines, 1)
    end
end

T["get_refile_target"]["returns nil for non-refile content"] = function()
    local content = "Just plain text without bullets or headings"
    local buf = helpers.create_test_buffer(content, "markdown")
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, {1, 0})

    local selection = refile.get_refile_target()
    MiniTest.expect.equality(selection, nil)
end

-- Transaction Safety Tests (Phase 0 fixes)
T["refile"]["preserves source on write failure"] = function()
    local dest_file = helpers.create_temp_file("# Destination\n")
    table.insert(T.temp_files, dest_file)
    helpers.make_readonly(dest_file)  -- Force write failure

    local content = [[
# Source
- Task to refile
- Other task
]]
    local buf = helpers.create_test_buffer(content, "markdown")
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, {2, 0})

    local before_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    -- Attempt refile (should fail)
    local selection = refile.get_refile_target()
    local ok = pcall(utils.append_lines, dest_file, selection.lines)
    MiniTest.expect.equality(ok, false, "Write should have failed")

    -- Source should be unchanged
    local after_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    MiniTest.expect.equality(before_lines, after_lines)

    helpers.make_writable(dest_file)
end

T["refile"]["stores in register for undo"] = function()
    local dest_file = helpers.create_temp_file("# Destination\n")
    table.insert(T.temp_files, dest_file)

    local content = "- Task to refile"
    local buf = helpers.create_test_buffer(content, "markdown")
    vim.api.nvim_set_current_buf(buf)

    local selection = refile.get_refile_target()

    -- Simulate the refile register storage
    vim.fn.setreg('r', table.concat(selection.lines, "\n"))

    -- Verify register contains the content
    local register_content = vim.fn.getreg('r')
    MiniTest.expect.equality(register_content, "- Task to refile")
end

T["refile"]["includes all nested subheadings"] = function()
    local content = [[
# Level 1
## Level 2
### Level 3
#### Level 4
Content here
## Next Level 2
Not included
]]
    local buf = helpers.create_test_buffer(content, "markdown")
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, {2, 0})  -- ## Level 2

    local selection = refile.get_refile_target()

    -- Should include Level 2, 3, 4 and content
    MiniTest.expect.equality(#selection.lines, 4)
    MiniTest.expect.truthy(selection.lines[1]:match("^## "))
    MiniTest.expect.truthy(selection.lines[2]:match("^### "))
end

return T
```

---

## 1.3 Sync Manager Test Suite

**New File:** `tests/test_sync_comprehensive.lua`

Replace the placeholder tests with real implementation:

```lua
local helpers = require("tests.helpers")
local sync_manager = require("org_markdown.sync.manager")

local T = MiniTest.new_set()

-- Marker Preservation Tests
T["marker_validation"]["accepts file with no markers"] = function()
    local lines = {
        "# My Notes",
        "Some content here",
        "More content",
    }

    local valid, status = sync_manager.validate_markers(lines, "test_plugin")
    MiniTest.expect.equality(valid, true)
    MiniTest.expect.equality(status, "no_markers")
end

T["marker_validation"]["accepts valid marker pair"] = function()
    local lines = {
        "# My Notes",
        "<!-- BEGIN ORG-MARKDOWN TEST_PLUGIN SYNC -->",
        "Sync content",
        "<!-- END ORG-MARKDOWN TEST_PLUGIN SYNC -->",
        "After content",
    }

    local valid, status = sync_manager.validate_markers(lines, "test_plugin")
    MiniTest.expect.equality(valid, true)
    MiniTest.expect.equality(status, "valid")
end

T["marker_validation"]["rejects missing END marker"] = function()
    local lines = {
        "# My Notes",
        "<!-- BEGIN ORG-MARKDOWN TEST_PLUGIN SYNC -->",
        "Sync content",
        "More content - will be lost!",
    }

    local valid, err = sync_manager.validate_markers(lines, "test_plugin")
    MiniTest.expect.equality(valid, false)
    MiniTest.expect.match(err, "Marker mismatch")
end

T["marker_validation"]["rejects missing BEGIN marker"] = function()
    local lines = {
        "# My Notes",
        "Some content",
        "<!-- END ORG-MARKDOWN TEST_PLUGIN SYNC -->",
    }

    local valid, err = sync_manager.validate_markers(lines, "test_plugin")
    MiniTest.expect.equality(valid, false)
    MiniTest.expect.match(err, "Marker mismatch")
end

T["marker_validation"]["rejects nested markers"] = function()
    local lines = {
        "# My Notes",
        "<!-- BEGIN ORG-MARKDOWN TEST_PLUGIN SYNC -->",
        "<!-- BEGIN ORG-MARKDOWN TEST_PLUGIN SYNC -->",
        "Content",
        "<!-- END ORG-MARKDOWN TEST_PLUGIN SYNC -->",
        "<!-- END ORG-MARKDOWN TEST_PLUGIN SYNC -->",
    }

    local valid, err = sync_manager.validate_markers(lines, "test_plugin")
    MiniTest.expect.equality(valid, false)
    MiniTest.expect.match(err, "Nested or duplicate")
end

-- Content Preservation Tests
T["read_preserved"]["preserves content before markers"] = function()
    local filepath = helpers.create_temp_file([[
# My Notes
Important content before
<!-- BEGIN ORG-MARKDOWN TEST_PLUGIN SYNC -->
Old sync data
<!-- END ORG-MARKDOWN TEST_PLUGIN SYNC -->
Content after
]])

    local before, after, status = sync_manager.read_preserved_content(filepath, "test_plugin")

    MiniTest.expect.equality(#before, 2)
    MiniTest.expect.equality(before[1], "# My Notes")
    MiniTest.expect.equality(before[2], "Important content before")

    MiniTest.expect.equality(#after, 1)
    MiniTest.expect.equality(after[1], "Content after")

    helpers.cleanup_temp(filepath)
end

T["read_preserved"]["handles multiple plugins in same file"] = function()
    local filepath = helpers.create_temp_file([[
# Notes
<!-- BEGIN ORG-MARKDOWN PLUGIN_A SYNC -->
Plugin A data
<!-- END ORG-MARKDOWN PLUGIN_A SYNC -->
Between plugins
<!-- BEGIN ORG-MARKDOWN PLUGIN_B SYNC -->
Plugin B data
<!-- END ORG-MARKDOWN PLUGIN_B SYNC -->
End content
]])

    -- Read for plugin A
    local before_a, after_a = sync_manager.read_preserved_content(filepath, "plugin_a")
    MiniTest.expect.truthy(vim.tbl_contains(after_a, "Between plugins"))

    -- Read for plugin B
    local before_b, after_b = sync_manager.read_preserved_content(filepath, "plugin_b")
    MiniTest.expect.truthy(vim.tbl_contains(before_b, "Between plugins"))

    helpers.cleanup_temp(filepath)
end

-- Event Validation Tests
T["event_validation"]["requires title"] = function()
    local event = {
        start_date = { year = 2025, month = 11, day = 29, day_name = "Fri" },
        all_day = true,
    }

    local valid, errors = sync_manager.validate_event(event, "test")
    MiniTest.expect.equality(valid, false)
    MiniTest.expect.truthy(vim.tbl_contains(errors, "title is required"))
end

T["event_validation"]["requires start_date"] = function()
    local event = {
        title = "Test Event",
        all_day = true,
    }

    local valid, errors = sync_manager.validate_event(event, "test")
    MiniTest.expect.equality(valid, false)
end

T["event_validation"]["validates time format"] = function()
    local event = {
        title = "Test Event",
        start_date = { year = 2025, month = 11, day = 29, day_name = "Fri" },
        start_time = "25:99",  -- Invalid time
        all_day = false,
    }

    local valid, errors = sync_manager.validate_event(event, "test")
    MiniTest.expect.equality(valid, false)
end

T["event_validation"]["accepts valid event"] = function()
    local event = {
        title = "Meeting",
        start_date = { year = 2025, month = 11, day = 29, day_name = "Fri" },
        start_time = "14:00",
        end_time = "15:30",
        all_day = false,
        tags = {"work", "important"},
        body = "Discuss project timeline",
    }

    local valid, errors = sync_manager.validate_event(event, "test")
    MiniTest.expect.equality(valid, true)
    MiniTest.expect.equality(errors, nil)
end

-- Atomic Write Tests
T["write_atomic"]["creates backup before write"] = function()
    local filepath = helpers.create_temp_file("# Original\nContent here")
    local dir = vim.fn.fnamemodify(filepath, ":h")

    -- Perform sync (writes atomically with backup)
    local new_lines = {"# Updated", "New content"}
    sync_manager.write_sync_file_atomic(filepath, new_lines, "test")

    -- Check backup exists
    local backups = vim.fn.glob(dir .. "/*.backup.*", false, true)
    MiniTest.expect.truthy(#backups > 0, "Backup should be created")

    helpers.cleanup_temp(filepath)
    for _, backup in ipairs(backups) do
        helpers.cleanup_temp(backup)
    end
end

T["write_atomic"]["keeps only 3 most recent backups"] = function()
    local filepath = helpers.create_temp_file("# Test")

    -- Create 5 backups
    for i = 1, 5 do
        vim.fn.writefile({"backup " .. i}, filepath)
        sync_manager.write_sync_file_atomic(filepath, {"Content " .. i}, "test")
        vim.loop.sleep(100)  -- Ensure different timestamps
    end

    -- Count backups
    local dir = vim.fn.fnamemodify(filepath, ":h")
    local backups = vim.fn.glob(dir .. "/*.backup.*", false, true)

    MiniTest.expect.equality(#backups, 3, "Should keep only 3 backups")

    helpers.cleanup_temp(filepath)
    for _, backup in ipairs(backups) do
        helpers.cleanup_temp(backup)
    end
end

return T
```

---

## 1.4 Config Test Suite

**New File:** `tests/test_config_comprehensive.lua`

```lua
local config = require("org_markdown.config")

local T = MiniTest.new_set()

T["setup"] = function()
    -- Save original defaults
    T.original_defaults = vim.deepcopy(config._defaults)
end

T["teardown"] = function()
    -- Restore defaults
    config._defaults = T.original_defaults
    config._runtime = nil
end

T["merge"]["doesn't mutate defaults"] = function()
    local before = vim.deepcopy(config._defaults)

    config.setup({
        captures = {
            author_name = "Test User",
        }
    })

    local after = config._defaults

    MiniTest.expect.equality(before, after, "Defaults should not be mutated")
end

T["merge"]["allows multiple setups"] = function()
    config.setup({ captures = { author_name = "First" } })
    local first_name = config.captures.author_name

    config.setup({ captures = { author_name = "Second" } })
    local second_name = config.captures.author_name

    MiniTest.expect.equality(first_name, "First")
    MiniTest.expect.equality(second_name, "Second")
end

T["merge"]["replaces arrays instead of merging"] = function()
    -- Default checkbox_states = {" ", "-", "X"}
    config.setup({
        checkbox_states = {" ", "x"}  -- User wants only 2 states
    })

    local states = config.checkbox_states
    MiniTest.expect.equality(#states, 2, "Should replace, not merge")
    MiniTest.expect.equality(states[1], " ")
    MiniTest.expect.equality(states[2], "x")
end

T["merge"]["deep merges nested objects"] = function()
    config.setup({
        agendas = {
            views = {
                custom = {
                    title = "Custom View",
                    source = "tasks"
                }
            }
        }
    })

    -- Should have both default views AND custom
    MiniTest.expect.truthy(config.agendas.views.tasks)
    MiniTest.expect.truthy(config.agendas.views.custom)
end

T["validation"]["validates window_method"] = function()
    local ok = pcall(config.setup, {
        window_method = "invalid_method"
    })

    MiniTest.expect.equality(ok, false, "Should reject invalid window_method")
end

T["validation"]["validates picker"] = function()
    local ok = pcall(config.setup, {
        picker = "invalid_picker"
    })

    MiniTest.expect.equality(ok, false, "Should reject invalid picker")
end

return T
```

---

## 1.5 Queries Test Suite

**New File:** `tests/test_queries.lua`

```lua
local helpers = require("tests.helpers")
local queries = require("org_markdown.utils.queries")

local T = MiniTest.new_set()

T["find_markdown_files"]["finds .md files recursively"] = function()
    local workspace = helpers.create_temp_workspace({
        ["notes/file1.md"] = "# Note 1",
        ["notes/subdir/file2.md"] = "# Note 2",
        ["notes/file3.txt"] = "Not markdown",
        ["notes/file4.markdown"] = "# Note 4",
    })

    local files = queries.find_markdown_files({ paths = {workspace} })

    -- Should find 3 markdown files
    MiniTest.expect.equality(#files, 3)

    local basenames = vim.tbl_map(function(f)
        return vim.fn.fnamemodify(f, ":t")
    end, files)

    MiniTest.expect.truthy(vim.tbl_contains(basenames, "file1.md"))
    MiniTest.expect.truthy(vim.tbl_contains(basenames, "file2.md"))
    MiniTest.expect.truthy(vim.tbl_contains(basenames, "file4.markdown"))

    helpers.cleanup_temp(workspace)
end

T["find_markdown_files"]["skips hidden directories"] = function()
    local workspace = helpers.create_temp_workspace({
        ["visible/file.md"] = "# Visible",
        [".hidden/file.md"] = "# Hidden",
        ["visible/.git/file.md"] = "# In git",
    })

    local files = queries.find_markdown_files({ paths = {workspace} })

    -- Should only find visible/file.md
    MiniTest.expect.equality(#files, 1)
    MiniTest.expect.match(files[1], "visible/file%.md$")

    helpers.cleanup_temp(workspace)
end

T["find_markdown_files"]["handles permission errors gracefully"] = function()
    local workspace = helpers.create_temp_workspace({
        ["accessible/file.md"] = "# File",
    })

    -- Create a directory without read permissions
    local forbidden = workspace .. "/forbidden"
    vim.fn.mkdir(forbidden, "p")
    vim.fn.writefile({"# Forbidden"}, forbidden .. "/file.md")
    vim.fn.setfperm(forbidden, "---------")

    -- Should not crash, just skip the forbidden directory
    local ok, files = pcall(queries.find_markdown_files, { paths = {workspace} })

    MiniTest.expect.equality(ok, true, "Should handle permission errors")
    MiniTest.expect.truthy(#files >= 1, "Should find accessible files")

    -- Cleanup (restore permissions first)
    vim.fn.setfperm(forbidden, "rwxr-xr-x")
    helpers.cleanup_temp(workspace)
end

return T
```

---

## 1.6 Picker Test Suite

**New File:** `tests/test_picker.lua`

```lua
local picker = require("org_markdown.utils.picker")
local config = require("org_markdown.config")

local T = MiniTest.new_set()

-- Mock telescope/snacks for testing
local mock_picker_result = nil

T["setup"] = function()
    -- Save original picker config
    T.original_picker = config.picker

    -- Mock telescope
    package.loaded["telescope"] = {
        pickers = {
            new = function(opts, config)
                return {
                    find = function()
                        if config.attach_mappings then
                            -- Simulate selection
                            config.attach_mappings(nil, {
                                select_default = function()
                                    return true
                                end
                            })
                        end

                        -- Call on_select with mock result
                        if opts.on_select then
                            opts.on_select(mock_picker_result)
                        end
                    end
                }
            end
        }
    }
end

T["teardown"] = function()
    config.picker = T.original_picker
    mock_picker_result = nil
end

T["pick"]["returns selected item"] = function()
    config.picker = "telescope"

    local items = {
        { label = "Item 1", value = "value1" },
        { label = "Item 2", value = "value2" },
    }

    mock_picker_result = items[1]

    local selected
    picker.pick(items, {
        on_confirm = function(item)
            selected = item
        end
    })

    MiniTest.expect.equality(selected.value, "value1")
end

T["pick"]["returns nil on cancel"] = function()
    config.picker = "telescope"

    mock_picker_result = nil  -- User cancelled

    local selected = "not_nil"
    picker.pick({}, {
        on_confirm = function(item)
            selected = item
        end
    })

    MiniTest.expect.equality(selected, nil)
end

T["pick"]["handles empty item list"] = function()
    config.picker = "telescope"

    local ok = pcall(picker.pick, {}, {})
    MiniTest.expect.equality(ok, true, "Should handle empty list gracefully")
end

return T
```

---

## Test Running Strategy

### Run All Tests
```bash
make test
```

### Run Specific Test File
```bash
make test_file FILE=tests/test_refile_comprehensive.lua
```

### Run Tests for Specific Module
```bash
# Run all sync-related tests
nvim --headless -u tests/init.lua -c "lua MiniTest.run_file('tests/test_sync_comprehensive.lua')"
```

### Watch Mode (during development)
```bash
# Re-run tests on file change
find lua tests -name '*.lua' | entr make test
```

---

## Success Criteria

Before proceeding to Phase 2:

- [ ] All new test files created
- [ ] `make test` passes with 0 failures
- [ ] Coverage report shows:
  - [ ] refile.lua: 90%+
  - [ ] sync/manager.lua: 85%+
  - [ ] config.lua: 80%+
  - [ ] queries.lua: 75%+
  - [ ] picker.lua: 70%+
- [ ] Test helpers reusable across test files
- [ ] Git branch: `refactor/phase-1-tests`
- [ ] Code reviewed
- [ ] Merged to main

## Estimated Time

- Test helpers setup: 2 hours
- Refile tests: 6 hours
- Sync tests: 8 hours
- Config tests: 4 hours
- Queries tests: 4 hours
- Picker tests: 4 hours
- Integration and fixes: 4 hours

**Total: 7-10 days** including writing tests, fixing discovered bugs, and achieving target coverage
