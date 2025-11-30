# Phase 4: Performance & Caching

**Timeline:** Days 29-35
**Risk Level:** LOW (mostly additive optimizations)
**Dependencies:** Phases 0, 1, 2, and 3 complete
**Status:** Not Started

---

## Progress Tracking

**How to use:** Check off items and record actual performance measurements.

### 4.1 Query Result Caching
- [ ] Cache structure added to queries.lua
- [ ] File watcher setup implemented
- [ ] TTL-based caching working
- [ ] Invalidation on file changes working
- [ ] `:MarkdownRefreshCache` command added
- [ ] Tests created and passing
- [ ] Performance measured:
  - First scan: ___ms
  - Cached scan: ___ms (target: <10ms)
  - Speedup: ___x (target: 20x+)

### 4.2 Agenda Item Caching
- [ ] Agenda cache structure added
- [ ] File mtime tracking implemented
- [ ] Incremental scanning working (only changed files)
- [ ] Cache invalidation on BufWritePost working
- [ ] `clear_agenda_cache()` function added
- [ ] Tests created and passing
- [ ] Performance measured (100 files):
  - First scan: ___ms
  - Cached scan: ___ms (target: <50ms)
  - After 1 file change: ___ms (target: <100ms)

### 4.3 Parser Pattern Compilation
- [ ] `COMPILED_PATTERNS` structure added
- [ ] Patterns compiled on module load
- [ ] `is_heading()` uses compiled patterns
- [ ] `parse_headline_unified()` uses compiled patterns
- [ ] vim.regex availability check added
- [ ] Performance measured:
  - Before: ___ms (1000 lines)
  - After: ___ms (target: 10-15% improvement)

### 4.4 Async File Scanning (Stretch Goal)
- [ ] `find_markdown_files_async()` implemented
- [ ] Progress callback working
- [ ] Directory chunking prevents blocking
- [ ] Tests created and passing
- [ ] OR: Deferred to future phase <!-- Check if skipped -->

### 4.5 Performance Monitoring (Optional)
- [ ] `utils/perf.lua` module created
- [ ] `time_operation()` function working
- [ ] `get_metrics()` and `print_metrics()` implemented
- [ ] Used in key operations (scan_files, queries)
- [ ] OR: Skipped (not essential) <!-- Check if skipped -->

### Benchmarking
- [ ] `tests/benchmark.lua` created
- [ ] Large workspace generator working
- [ ] File query benchmarks passing targets
- [ ] Agenda scan benchmarks passing targets
- [ ] Benchmark results documented below:

```
<!-- Paste benchmark results here
File queries: cold=___ms, cached=___ms, speedup=___x
Agenda scan: first=___ms, cached=___ms, speedup=___x
-->
```

### Phase Completion
- [ ] All performance optimizations completed
- [ ] All benchmarks meet targets
- [ ] No UI blocking on large collections
- [ ] All previous tests still passing
- [ ] Git branch `refactor/phase-4-performance` created
- [ ] Code reviewed
- [ ] Merged to main

**Estimated completion:** ___/___/___

---

## Goals

Eliminate UI blocking, improve responsiveness on large note collections, and add intelligent caching throughout the system.

## 4.1 Query Result Caching

### Problem

**Location:** `lua/org_markdown/utils/queries.lua`

Every operation that needs file lists (agenda, refile, find) scans the entire directory tree synchronously:
- Blocks UI thread
- 1000 files = 200-500ms scan
- Repeated for every agenda refresh
- No change detection

### Solution

Add simple TTL-based caching with file watching invalidation.

```lua
-- At top of queries.lua
local cache = {
    files = {},           -- Cached file list
    timestamp = 0,        -- When cache was last populated
    ttl_ms = 5000,        -- Time-to-live: 5 seconds
    invalidated = false,  -- Manual invalidation flag
}

-- Watch for file changes
local function setup_file_watcher()
    local paths = vim.g.org_markdown_refile_paths or {vim.fn.getcwd()}

    vim.api.nvim_create_autocmd({"BufWritePost", "BufDelete"}, {
        pattern = {"*.md", "*.markdown"},
        callback = function()
            cache.invalidated = true
        end,
        desc = "Invalidate org-markdown file cache on changes"
    })
end

-- Initialize watcher on first call
local watcher_initialized = false

function M.find_markdown_files(opts)
    opts = opts or {}

    -- Initialize watcher once
    if not watcher_initialized then
        setup_file_watcher()
        watcher_initialized = true
    end

    -- Check cache validity
    local now = vim.loop.now()
    local cache_valid = not opts.force_refresh
                    and not cache.invalidated
                    and (now - cache.timestamp) < cache.ttl_ms

    if cache_valid and #cache.files > 0 then
        return vim.deepcopy(cache.files)  -- Return copy to prevent mutation
    end

    -- Scan filesystem
    local paths = opts.paths or config.refile_paths or {vim.fn.getcwd()}
    local files = {}

    for _, path in ipairs(paths) do
        local expanded = vim.fn.expand(path)
        scan_dir_sync(expanded, files)
    end

    -- Update cache
    cache.files = files
    cache.timestamp = now
    cache.invalidated = false

    return files
end

-- Public API: Force refresh
function M.refresh_file_cache()
    cache.invalidated = true
    return M.find_markdown_files({ force_refresh = true })
end

-- Public API: Clear cache
function M.clear_file_cache()
    cache.files = {}
    cache.timestamp = 0
    cache.invalidated = false
end
```

### Add User Command

```lua
-- In commands.lua
vim.api.nvim_create_user_command("MarkdownRefreshCache", function()
    local queries = require("org_markdown.utils.queries")
    local files = queries.refresh_file_cache()
    vim.notify("Refreshed file cache: " .. #files .. " files found", vim.log.levels.INFO)
end, {})
```

### Expected Results

**Before:**
- First agenda open: 200ms (scan)
- Second agenda open: 200ms (scan again)
- Third agenda open: 200ms (scan again)

**After:**
- First agenda open: 200ms (scan)
- Second agenda open: 10ms (cached)
- Third agenda open: 10ms (cached)
- After file save: ~200ms (invalidated, rescan)

### Test Coverage

```lua
T["file_cache"]["caches results for TTL duration"] = function()
    local workspace = helpers.create_temp_workspace({
        ["file1.md"] = "# Note",
        ["file2.md"] = "# Note",
    })

    -- First call: scan
    local start = vim.loop.now()
    local files1 = queries.find_markdown_files({ paths = {workspace} })
    local first_duration = vim.loop.now() - start

    -- Second call: cached (should be much faster)
    start = vim.loop.now()
    local files2 = queries.find_markdown_files({ paths = {workspace} })
    local second_duration = vim.loop.now() - start

    MiniTest.expect.equality(#files1, #files2)
    MiniTest.expect.truthy(second_duration < first_duration / 5, "Cache should be 5x+ faster")

    helpers.cleanup_temp(workspace)
end

T["file_cache"]["invalidates on file changes"] = function()
    -- Create workspace and cache
    -- Write to a file (triggers BufWritePost)
    -- Verify next call rescans
end

T["file_cache"]["respects force_refresh option"] = function()
    queries.find_markdown_files()  -- Populate cache
    queries.find_markdown_files({ force_refresh = true })  -- Should bypass cache
end
```

### Files Modified
- `lua/org_markdown/utils/queries.lua`
- `lua/org_markdown/commands.lua`

---

## 4.2 Agenda Item Caching

### Problem

**Location:** `lua/org_markdown/agenda.lua:57-99`

The `scan_files()` function:
- Reads and parses every markdown file on every call
- 100 files × 10ms parsing = 1 second
- Runs on every agenda refresh
- Doesn't detect if files haven't changed

### Solution

Cache parsed agenda items with file modification time tracking.

```lua
-- At top of agenda.lua
local agenda_cache = {
    items = { tasks = {}, calendar = {} },
    file_mtimes = {},  -- Track file modification times
    last_scan = 0,
}

function scan_files()
    local files = queries.find_markdown_files()

    -- Check which files have changed
    local needs_rescan = false
    local changed_files = {}

    for _, file in ipairs(files) do
        local stat = vim.loop.fs_stat(file)
        if not stat then
            goto continue
        end

        local current_mtime = stat.mtime.sec
        local cached_mtime = agenda_cache.file_mtimes[file] or 0

        if current_mtime > cached_mtime then
            needs_rescan = true
            table.insert(changed_files, file)
            agenda_cache.file_mtimes[file] = current_mtime
        end

        ::continue::
    end

    -- Return cached if nothing changed
    if not needs_rescan and agenda_cache.last_scan > 0 then
        return {
            tasks = vim.deepcopy(agenda_cache.items.tasks),
            calendar = vim.deepcopy(agenda_cache.items.calendar),
        }
    end

    -- Scan only changed files (or all if first scan)
    local agenda_items = { tasks = {}, calendar = {} }

    if agenda_cache.last_scan == 0 then
        -- First scan: parse all files
        for _, file in ipairs(files) do
            parse_file_into_agenda(file, agenda_items)
        end
    else
        -- Incremental: start with cached items
        agenda_items.tasks = vim.deepcopy(agenda_cache.items.tasks)
        agenda_items.calendar = vim.deepcopy(agenda_cache.items.calendar)

        -- Update only changed files
        for _, file in ipairs(changed_files) do
            -- Remove old items from this file
            remove_items_from_file(agenda_items.tasks, file)
            remove_items_from_file(agenda_items.calendar, file)

            -- Parse and add new items
            parse_file_into_agenda(file, agenda_items)
        end
    end

    -- Update cache
    agenda_cache.items.tasks = vim.deepcopy(agenda_items.tasks)
    agenda_cache.items.calendar = vim.deepcopy(agenda_items.calendar)
    agenda_cache.last_scan = os.time()

    return agenda_items
end

-- Helper: Parse file and add to agenda items
function parse_file_into_agenda(file, agenda_items)
    local lines = utils.read_lines(file)
    if not lines then return end

    for line_num, line in ipairs(lines) do
        local heading = parser.parse_headline(line)
        if not heading then goto continue end

        local item = {
            file = file,
            line = line_num,
            title = heading.text,
            state = heading.state,
            priority = heading.priority,
            date = heading.tracked,
            tags = heading.tags,
            start_time = heading.start_time,
            end_time = heading.end_time,
            all_day = heading.all_day,
            source = vim.fn.fnamemodify(file, ":t:r"),
        }

        if heading.state then
            table.insert(agenda_items.tasks, item)
        end

        if heading.tracked then
            table.insert(agenda_items.calendar, item)
        end

        ::continue::
    end
end

-- Helper: Remove items from specific file
function remove_items_from_file(items, file)
    for i = #items, 1, -1 do
        if items[i].file == file then
            table.remove(items, i)
        end
    end
end

-- Public: Clear cache (useful for testing)
function M.clear_agenda_cache()
    agenda_cache = {
        items = { tasks = {}, calendar = {} },
        file_mtimes = {},
        last_scan = 0,
    }
end
```

### Invalidate Cache on File Changes

```lua
-- In commands.lua FileType autocmd
vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = {"*.md", "*.markdown"},
    callback = function()
        -- Clear agenda cache when markdown files are saved
        local agenda = require("org_markdown.agenda")
        if agenda.clear_agenda_cache then
            agenda.clear_agenda_cache()
        end
    end,
    desc = "Invalidate agenda cache on markdown file save"
})
```

### Expected Results

**Scenario: 100 files, 500 agenda items**

**Before:**
- First agenda view: 1000ms (scan all files)
- Second agenda view: 1000ms (scan all files again)
- After editing 1 file: 1000ms (scan all files)

**After:**
- First agenda view: 1000ms (scan all files, cache)
- Second agenda view: 20ms (return cached)
- After editing 1 file: 30ms (only parse changed file)

### Test Coverage

```lua
T["agenda_cache"]["caches parsed items"] = function()
    local workspace = helpers.create_temp_workspace({
        ["tasks.md"] = "# TODO Task 1\n# TODO Task 2",
        ["calendar.md"] = "# Event <2025-11-29 Fri>",
    })

    -- First scan
    local items1 = agenda.scan_files()
    -- Second scan (should be cached)
    local items2 = agenda.scan_files()

    MiniTest.expect.equality(#items1.tasks, #items2.tasks)
    -- Verify it's actually from cache (e.g., modify a file's mtime and verify rescan)

    helpers.cleanup_temp(workspace)
end

T["agenda_cache"]["detects file changes"] = function()
    local file = helpers.create_temp_file("# TODO Original")
    agenda.scan_files()  -- Cache

    -- Modify file
    vim.fn.writefile({"# TODO Modified"}, file)

    local items = agenda.scan_files()
    MiniTest.expect.match(items.tasks[1].title, "Modified")

    helpers.cleanup_temp(file)
end
```

### Files Modified
- `lua/org_markdown/agenda.lua`
- `lua/org_markdown/commands.lua`

---

## 4.3 Parser Pattern Compilation

### Problem

**Location:** `lua/org_markdown/utils/parser.lua`

Lua regex patterns are compiled on every match:
- `line:match("^#+%s+")` compiles pattern every time
- Called hundreds of times per file
- Unnecessary overhead

### Solution

Pre-compile patterns that are used frequently.

```lua
-- At top of parser.lua
local COMPILED_PATTERNS = {}

-- Compile on module load
local function compile_patterns()
    if not vim.regex then
        return  -- vim.regex not available in all versions
    end

    COMPILED_PATTERNS.heading = vim.regex("^#\\+\\s\\+")
    COMPILED_PATTERNS.state = vim.regex("^[A-Z_]\\+\\s\\+")
    COMPILED_PATTERNS.priority = vim.regex("\\[#[A-Z]\\]")
    COMPILED_PATTERNS.tracked_date = vim.regex("<[^>]\\+>")
    COMPILED_PATTERNS.untracked_date = vim.regex("\\[[^\\]]\\+\\]")
    COMPILED_PATTERNS.tags = vim.regex(":[[:alnum:]_-]\\+:")
end

-- Call on module load
compile_patterns()

-- Use compiled patterns when available
function M.is_heading(line)
    if COMPILED_PATTERNS.heading then
        return COMPILED_PATTERNS.heading:match_str(line) ~= nil
    else
        return line:match("^#+%s+") ~= nil
    end
end

-- Or in parse_headline_unified
function M.parse_headline_unified(line)
    -- Quick check with compiled pattern
    if COMPILED_PATTERNS.heading then
        if not COMPILED_PATTERNS.heading:match_str(line) then
            return nil
        end
    else
        if not line:match(PATTERNS.heading_prefix) then
            return nil
        end
    end

    -- Rest of parsing...
end
```

### Expected Results

**Benchmark on 1000 lines:**
- Before: ~100ms parsing
- After: ~85ms parsing (10-15% improvement)

Not a huge gain, but every bit helps for large files.

### Alternative: Treesitter

For future consideration (Phase 5+):
- Use nvim-treesitter with markdown parser
- Much faster than regex for large files
- But adds dependency and complexity

### Files Modified
- `lua/org_markdown/utils/parser.lua`

---

## 4.4 Async File Scanning (Stretch Goal)

### Problem

Even with caching, first scan still blocks UI for large directories.

### Solution

Make file scanning async with progress reporting.

**Note:** This is a stretch goal. If time permits, implement this. Otherwise, defer to future phase.

```lua
-- In queries.lua
function M.find_markdown_files_async(opts, on_progress)
    return async.promise(function(resolve, reject)
        local files = {}
        local paths = opts.paths or config.refile_paths or {vim.fn.getcwd()}
        local total_dirs = #paths
        local processed_dirs = 0

        local function scan_next_dir(idx)
            if idx > #paths then
                resolve(files)
                return
            end

            local path = vim.fn.expand(paths[idx])

            -- Scan directory in chunks to avoid blocking
            vim.loop.fs_scandir(path, function(err, handle)
                if err then
                    vim.schedule(function()
                        scan_next_dir(idx + 1)
                    end)
                    return
                end

                local function read_next()
                    vim.loop.fs_scandir_next(handle, function(err, name, type)
                        if err or not name then
                            -- Done with this directory
                            processed_dirs = processed_dirs + 1
                            if on_progress then
                                on_progress(processed_dirs, total_dirs, #files)
                            end

                            vim.schedule(function()
                                scan_next_dir(idx + 1)
                            end)
                            return
                        end

                        local full_path = path .. "/" .. name

                        if type == "directory" and not name:match("^%.") then
                            table.insert(paths, full_path)  -- Add to scan queue
                            total_dirs = total_dirs + 1
                        elseif type == "file" and name:match("%.markdown?$") then
                            table.insert(files, full_path)
                        end

                        -- Continue reading
                        read_next()
                    end)
                end

                read_next()
            end)
        end

        scan_next_dir(1)
    end)
end
```

**Usage:**
```lua
-- Show progress notification
queries.find_markdown_files_async({}, function(processed, total, count)
    vim.notify(string.format("Scanning... %d/%d dirs, %d files", processed, total, count))
end):then_(function(files)
    vim.notify("Scan complete: " .. #files .. " files")
end)
```

### Files Modified (if implemented)
- `lua/org_markdown/utils/queries.lua`

---

## 4.5 Performance Monitoring

### Add Performance Metrics

Useful for understanding where time is spent.

```lua
-- In utils.lua or new utils/perf.lua
local M = {}

local metrics = {}

function M.time_operation(name, fn)
    local start = vim.loop.hrtime()
    local result = fn()
    local duration = (vim.loop.hrtime() - start) / 1e6  -- Convert to ms

    if not metrics[name] then
        metrics[name] = { count = 0, total_ms = 0, min_ms = math.huge, max_ms = 0 }
    end

    local m = metrics[name]
    m.count = m.count + 1
    m.total_ms = m.total_ms + duration
    m.min_ms = math.min(m.min_ms, duration)
    m.max_ms = math.max(m.max_ms, duration)

    return result
end

function M.get_metrics()
    local result = {}
    for name, m in pairs(metrics) do
        table.insert(result, {
            name = name,
            count = m.count,
            avg_ms = m.total_ms / m.count,
            min_ms = m.min_ms,
            max_ms = m.max_ms,
            total_ms = m.total_ms,
        })
    end
    table.sort(result, function(a, b) return a.total_ms > b.total_ms end)
    return result
end

function M.print_metrics()
    local metrics = M.get_metrics()
    print("Performance Metrics:")
    print(string.format("%-30s %8s %10s %10s %10s %12s", "Operation", "Count", "Avg (ms)", "Min (ms)", "Max (ms)", "Total (ms)"))
    print(string.rep("-", 90))
    for _, m in ipairs(metrics) do
        print(string.format("%-30s %8d %10.2f %10.2f %10.2f %12.2f",
            m.name, m.count, m.avg_ms, m.min_ms, m.max_ms, m.total_ms))
    end
end

return M
```

**Usage:**
```lua
local perf = require("org_markdown.utils.perf")

function scan_files()
    return perf.time_operation("agenda_scan_files", function()
        -- ... scanning logic ...
    end)
end

-- View metrics
:lua require("org_markdown.utils.perf").print_metrics()
```

### Files Created
- `lua/org_markdown/utils/perf.lua` (new, optional)

---

## Success Criteria

- [ ] File query caching: 200ms → <10ms (cached)
- [ ] Agenda refresh: <50ms with cache for 1000+ files
- [ ] No UI blocking on large collections
- [ ] Cache invalidates correctly on file changes
- [ ] `:MarkdownRefreshCache` command works
- [ ] Parser 10-15% faster with compiled patterns
- [ ] All previous tests still pass
- [ ] Performance metrics available (optional)
- [ ] Git branch: `refactor/phase-4-performance`
- [ ] Code reviewed
- [ ] Merged to main

## Performance Benchmarks

Create benchmark suite to track improvements:

**New File:** `tests/benchmark.lua`

```lua
-- Generate large test workspace
local function create_large_workspace()
    local files = {}
    for i = 1, 200 do
        files["notes/file_" .. i .. ".md"] = string.format([[
# TODO Task %d [#A]
Some content here
## DONE Subtask 1 <2025-11-29 Fri>
## TODO Subtask 2 <2025-11-30 Sat 14:00>
]], i)
    end
    return helpers.create_temp_workspace(files)
end

-- Benchmark file queries
function benchmark_file_queries()
    local workspace = create_large_workspace()

    -- First scan (cold)
    local start = vim.loop.hrtime()
    queries.find_markdown_files({ paths = {workspace} })
    local cold_duration = (vim.loop.hrtime() - start) / 1e6

    -- Second scan (cached)
    start = vim.loop.hrtime()
    queries.find_markdown_files({ paths = {workspace} })
    local cached_duration = (vim.loop.hrtime() - start) / 1e6

    print(string.format("File queries: cold=%dms, cached=%dms, speedup=%.1fx",
        cold_duration, cached_duration, cold_duration / cached_duration))

    helpers.cleanup_temp(workspace)
end

-- Benchmark agenda scan
function benchmark_agenda_scan()
    local workspace = create_large_workspace()

    -- First scan
    local start = vim.loop.hrtime()
    agenda.scan_files()
    local first_duration = (vim.loop.hrtime() - start) / 1e6

    -- Second scan (cached)
    start = vim.loop.hrtime()
    agenda.scan_files()
    local cached_duration = (vim.loop.hrtime() - start) / 1e6

    print(string.format("Agenda scan: first=%dms, cached=%dms, speedup=%.1fx",
        first_duration, cached_duration, first_duration / cached_duration))

    helpers.cleanup_temp(workspace)
end

-- Run all benchmarks
benchmark_file_queries()
benchmark_agenda_scan()
```

**Target Results:**
```
File queries: cold=250ms, cached=8ms, speedup=31.3x
Agenda scan: first=1200ms, cached=45ms, speedup=26.7x
```

## Estimated Time

- Query caching: 4 hours
- Agenda caching: 6 hours
- Parser optimization: 2 hours
- Performance monitoring: 2 hours
- Benchmarks and testing: 4 hours
- Async scanning (stretch): 6 hours

**Total: 4-7 days** depending on stretch goals

---

## Final Refactoring Plan Summary

### Total Timeline: 4-6 weeks

**Phase 0 (Days 1-2):** Critical bug fixes - 3 data loss bugs eliminated
**Phase 1 (Days 3-10):** Test infrastructure - 80%+ coverage achieved
**Phase 2 (Days 11-20):** Architecture - 50% code reduction, better abstractions
**Phase 3 (Days 21-28):** Sync system - validation, extended model, state persistence
**Phase 4 (Days 29-35):** Performance - caching, 20-30x speedup for repeated operations

### Key Achievements

- **Zero data loss risks**
- **Comprehensive test coverage**
- **Maintainable, DRY codebase**
- **Extensible sync system**
- **Fast, responsive UI**

The refactoring positions org-markdown for long-term maintainability and feature growth while immediately fixing critical production issues.
