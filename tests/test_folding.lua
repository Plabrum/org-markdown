local MiniTest = require("mini.test")
local folding = require("org_markdown.folding")
local T = MiniTest.new_set()

-- Helper: Create a buffer with test content and display it in a window
local function create_test_buffer(lines)
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].filetype = "markdown"

	-- Display buffer in current window so fold options can be set
	vim.api.nvim_set_current_buf(bufnr)

	return bufnr
end

-- Helper: Clean up buffer
local function cleanup_buffer(bufnr)
	if vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end
end

-- Test: get_heading_level
T["get_heading_level - detects level 1 heading"] = function()
	local line = "# Top Level Heading"
	local level = folding.get_heading_level(line)
	MiniTest.expect.equality(level, 1)
end

T["get_heading_level - detects level 2 heading"] = function()
	local line = "## Second Level"
	local level = folding.get_heading_level(line)
	MiniTest.expect.equality(level, 2)
end

T["get_heading_level - detects level 3 heading"] = function()
	local line = "### Third Level"
	local level = folding.get_heading_level(line)
	MiniTest.expect.equality(level, 3)
end

T["get_heading_level - returns nil for non-heading"] = function()
	local line = "This is just text"
	local level = folding.get_heading_level(line)
	MiniTest.expect.equality(level, nil)
end

T["get_heading_level - returns nil for # without space"] = function()
	local line = "#NoSpace"
	local level = folding.get_heading_level(line)
	MiniTest.expect.equality(level, nil)
end

T["get_heading_level - detects heading with TODO state"] = function()
	local line = "## TODO Fix bug"
	local level = folding.get_heading_level(line)
	MiniTest.expect.equality(level, 2)
end

T["get_heading_level - detects heading with priority"] = function()
	local line = "# TODO [#A] Important task"
	local level = folding.get_heading_level(line)
	MiniTest.expect.equality(level, 1)
end

-- Test: is_heading_line
T["is_heading_line - returns true for heading"] = function()
	local bufnr = create_test_buffer({
		"# Heading",
		"Content",
	})

	local result = folding.is_heading_line(1, bufnr)
	MiniTest.expect.equality(result, true)

	cleanup_buffer(bufnr)
end

T["is_heading_line - returns false for content"] = function()
	local bufnr = create_test_buffer({
		"# Heading",
		"Content",
	})

	local result = folding.is_heading_line(2, bufnr)
	MiniTest.expect.equality(result, false)

	cleanup_buffer(bufnr)
end

-- Test: get_fold_level
T["get_fold_level - returns >1 for level 1 heading"] = function()
	local bufnr = create_test_buffer({
		"# Top Level",
	})
	vim.api.nvim_set_current_buf(bufnr)

	local result = folding.get_fold_level(1)
	MiniTest.expect.equality(result, ">1")

	cleanup_buffer(bufnr)
end

T["get_fold_level - returns >2 for level 2 heading"] = function()
	local bufnr = create_test_buffer({
		"## Second Level",
	})
	vim.api.nvim_set_current_buf(bufnr)

	local result = folding.get_fold_level(1)
	MiniTest.expect.equality(result, ">2")

	cleanup_buffer(bufnr)
end

T["get_fold_level - returns = for content line"] = function()
	local bufnr = create_test_buffer({
		"# Heading",
		"Content line",
	})
	vim.api.nvim_set_current_buf(bufnr)

	local result = folding.get_fold_level(2)
	MiniTest.expect.equality(result, "=")

	cleanup_buffer(bufnr)
end

T["get_fold_level - handles nested headings correctly"] = function()
	local bufnr = create_test_buffer({
		"# Level 1",
		"## Level 2",
		"### Level 3",
		"Content",
	})
	vim.api.nvim_set_current_buf(bufnr)

	MiniTest.expect.equality(folding.get_fold_level(1), ">1")
	MiniTest.expect.equality(folding.get_fold_level(2), ">2")
	MiniTest.expect.equality(folding.get_fold_level(3), ">3")
	MiniTest.expect.equality(folding.get_fold_level(4), "=")

	cleanup_buffer(bufnr)
end

T["get_fold_level - handles sibling headings correctly"] = function()
	local bufnr = create_test_buffer({
		"## TODO Outline landing page",
		"",
		"Content for first task",
		"",
		"## TODO Develop User Personas",
		"",
		"Content for second task",
	})
	vim.api.nvim_set_current_buf(bufnr)

	-- First heading starts a new fold
	MiniTest.expect.equality(folding.get_fold_level(1), ">2")
	-- Content inherits fold level
	MiniTest.expect.equality(folding.get_fold_level(2), "=")
	MiniTest.expect.equality(folding.get_fold_level(3), "=")
	-- Second heading at same level also starts a new fold
	MiniTest.expect.equality(folding.get_fold_level(5), ">2")
	-- Content under second heading inherits fold level
	MiniTest.expect.equality(folding.get_fold_level(7), "=")

	cleanup_buffer(bufnr)
end

T["get_fold_level - handles mixed nesting and siblings"] = function()
	local bufnr = create_test_buffer({
		"# Parent 1",
		"## Child 1a",
		"Content",
		"## Child 1b",
		"# Parent 2",
		"## Child 2a",
	})
	vim.api.nvim_set_current_buf(bufnr)

	-- All headings start their own folds
	MiniTest.expect.equality(folding.get_fold_level(1), ">1")
	MiniTest.expect.equality(folding.get_fold_level(2), ">2")
	MiniTest.expect.equality(folding.get_fold_level(4), ">2")
	MiniTest.expect.equality(folding.get_fold_level(5), ">1")
	MiniTest.expect.equality(folding.get_fold_level(6), ">2")

	cleanup_buffer(bufnr)
end

-- Test: setup_buffer_folding
T["setup_buffer_folding - sets foldmethod to expr"] = function()
	local bufnr = create_test_buffer({
		"# Heading",
		"Content",
	})

	folding.setup_buffer_folding(bufnr)

	-- Check window-local foldmethod
	local winid = vim.fn.bufwinid(bufnr)
	MiniTest.expect.equality(vim.wo[winid].foldmethod, "expr")

	cleanup_buffer(bufnr)
end

T["setup_buffer_folding - sets foldexpr correctly"] = function()
	local bufnr = create_test_buffer({
		"# Heading",
		"Content",
	})

	folding.setup_buffer_folding(bufnr)

	-- Check window-local foldexpr
	local winid = vim.fn.bufwinid(bufnr)
	local expected = 'v:lua.require("org_markdown.folding").get_fold_level(v:lnum)'
	MiniTest.expect.equality(vim.wo[winid].foldexpr, expected)

	cleanup_buffer(bufnr)
end

T["setup_buffer_folding - auto-folds when config enabled"] = function()
	-- Save original config
	local config = require("org_markdown.config")
	local original_config = vim.deepcopy(config._runtime)

	-- Set up config with auto-fold enabled
	config._runtime = config._runtime or {}
	config._runtime.folding = {
		enabled = true,
		auto_fold_on_open = true,
	}

	local bufnr = create_test_buffer({
		"# Heading",
		"Content",
	})

	folding.setup_buffer_folding(bufnr)

	-- Check window-local foldlevel
	local winid = vim.fn.bufwinid(bufnr)
	MiniTest.expect.equality(vim.wo[winid].foldlevel, 0)

	-- Restore original config
	config._runtime = original_config
	cleanup_buffer(bufnr)
end

T["setup_buffer_folding - auto-fold shows sibling headings"] = function()
	-- Save original config
	local config = require("org_markdown.config")
	local original_config = vim.deepcopy(config._runtime)

	-- Set up config with auto-fold enabled
	config._runtime = config._runtime or {}
	config._runtime.folding = {
		enabled = true,
		auto_fold_on_open = true,
	}

	local bufnr = create_test_buffer({
		"## TODO First task",
		"Content",
		"## TODO Second task",
		"More content",
	})

	folding.setup_buffer_folding(bufnr)

	-- Check window-local foldlevel
	-- For level 2 headings, foldlevel should be 1 (shows all ## headings, folds content)
	local winid = vim.fn.bufwinid(bufnr)
	MiniTest.expect.equality(vim.wo[winid].foldlevel, 1)

	-- Restore original config
	config._runtime = original_config
	cleanup_buffer(bufnr)
end

T["setup_buffer_folding - no auto-fold when config disabled"] = function()
	-- Save original config
	local config = require("org_markdown.config")
	local original_config = vim.deepcopy(config._runtime)

	-- Set up config with auto-fold disabled
	config._runtime = config._runtime or {}
	config._runtime.folding = {
		enabled = true,
		auto_fold_on_open = false,
	}

	local bufnr = create_test_buffer({
		"# Heading",
		"Content",
	})

	folding.setup_buffer_folding(bufnr)

	-- Check window-local foldlevel
	local winid = vim.fn.bufwinid(bufnr)
	MiniTest.expect.equality(vim.wo[winid].foldlevel, 99)

	-- Restore original config
	config._runtime = original_config
	cleanup_buffer(bufnr)
end

T["setup_buffer_folding - initializes state tracking"] = function()
	local bufnr = create_test_buffer({
		"# Heading",
		"Content",
	})

	folding.setup_buffer_folding(bufnr)

	MiniTest.expect.equality(type(vim.b[bufnr].org_markdown_fold_states), "table")
	MiniTest.expect.equality(type(vim.b[bufnr].org_markdown_global_fold_level), "number")

	cleanup_buffer(bufnr)
end

-- Test: get_fold_state and set_fold_state
T["get_fold_state - returns nil for untracked heading"] = function()
	local bufnr = create_test_buffer({
		"# Heading",
	})

	-- Just initialize state table, don't do full setup
	vim.b[bufnr].org_markdown_fold_states = {}

	local state = folding.get_fold_state(bufnr, 1)
	MiniTest.expect.equality(state, nil)

	cleanup_buffer(bufnr)
end

T["set_fold_state - stores and retrieves state"] = function()
	local bufnr = create_test_buffer({
		"# Heading",
	})

	-- Set state without calling setup
	folding.set_fold_state(bufnr, 1, "folded")

	local state = folding.get_fold_state(bufnr, 1)
	MiniTest.expect.equality(state, "folded")

	cleanup_buffer(bufnr)
end

T["set_fold_state - can update existing state"] = function()
	local bufnr = create_test_buffer({
		"# Heading",
	})

	folding.set_fold_state(bufnr, 1, "folded")
	folding.set_fold_state(bufnr, 1, "children")

	local state = folding.get_fold_state(bufnr, 1)
	MiniTest.expect.equality(state, "children")

	cleanup_buffer(bufnr)
end

-- Test: cycle_heading_fold
T["cycle_heading_fold - returns false when not on heading"] = function()
	local bufnr = create_test_buffer({
		"# Heading",
		"Content",
	})
	vim.api.nvim_set_current_buf(bufnr)

	folding.setup_buffer_folding(bufnr)

	-- Set cursor on content line
	vim.api.nvim_win_set_cursor(0, { 2, 0 })

	local result = folding.cycle_heading_fold()
	MiniTest.expect.equality(result, false)

	cleanup_buffer(bufnr)
end

T["cycle_heading_fold - returns true when on heading"] = function()
	local bufnr = create_test_buffer({
		"# Heading",
		"Content",
	})
	vim.api.nvim_set_current_buf(bufnr)

	folding.setup_buffer_folding(bufnr)

	-- Set cursor on heading
	vim.api.nvim_win_set_cursor(0, { 1, 0 })

	local result = folding.cycle_heading_fold()
	MiniTest.expect.equality(result, true)

	cleanup_buffer(bufnr)
end

T["cycle_heading_fold - cycles through states"] = function()
	local bufnr = create_test_buffer({
		"# Heading",
		"Content",
	})
	vim.api.nvim_set_current_buf(bufnr)

	-- Setup folding properly (not just state tracking)
	folding.setup_buffer_folding(bufnr)

	-- Set cursor on heading
	vim.api.nvim_win_set_cursor(0, { 1, 0 })

	-- Ensure we start from expanded state by opening all folds
	vim.cmd("normal! zR")
	folding.set_fold_state(bufnr, 1, "expanded")

	-- First cycle: expanded -> folded
	folding.cycle_heading_fold()
	MiniTest.expect.equality(folding.get_fold_state(bufnr, 1), "folded")

	-- Second cycle: folded -> children
	folding.cycle_heading_fold()
	MiniTest.expect.equality(folding.get_fold_state(bufnr, 1), "children")

	-- Third cycle: children -> subtree
	folding.cycle_heading_fold()
	MiniTest.expect.equality(folding.get_fold_state(bufnr, 1), "subtree")

	-- Fourth cycle: subtree -> expanded
	folding.cycle_heading_fold()
	MiniTest.expect.equality(folding.get_fold_state(bufnr, 1), "expanded")

	cleanup_buffer(bufnr)
end

T["cycle_heading_fold - detects closed fold when auto_fold_on_open"] = function()
	-- Save original config
	local config = require("org_markdown.config")
	local original_config = vim.deepcopy(config._runtime)

	-- Set up config with auto-fold enabled
	config._runtime = config._runtime or {}
	config._runtime.folding = {
		enabled = true,
		auto_fold_on_open = true,
	}

	local bufnr = create_test_buffer({
		"# Heading",
		"Content under heading",
	})
	vim.api.nvim_set_current_buf(bufnr)

	-- Setup folding (this will close all folds due to auto_fold_on_open)
	folding.setup_buffer_folding(bufnr)

	-- Set cursor on heading
	vim.api.nvim_win_set_cursor(0, { 1, 0 })

	-- Verify fold is actually closed
	MiniTest.expect.equality(vim.fn.foldclosed(1), 1)

	-- First cycle should detect closed fold and cycle to "children" (not "folded")
	folding.cycle_heading_fold()
	MiniTest.expect.equality(folding.get_fold_state(bufnr, 1), "children")

	-- Verify fold is now open
	MiniTest.expect.equality(vim.fn.foldclosed(1), -1)

	-- Restore original config
	config._runtime = original_config
	cleanup_buffer(bufnr)
end

-- Test: cycle_global_fold
T["cycle_global_fold - cycles through fold levels"] = function()
	local bufnr = create_test_buffer({
		"# Level 1",
		"## Level 2",
		"### Level 3",
	})
	vim.api.nvim_set_current_buf(bufnr)

	folding.setup_buffer_folding(bufnr)

	-- Start at 99 (all expanded)
	vim.b[bufnr].org_markdown_global_fold_level = 99

	-- First cycle: 99 -> 0
	folding.cycle_global_fold()
	MiniTest.expect.equality(vim.b[bufnr].org_markdown_global_fold_level, 0)

	-- Second cycle: 0 -> 1
	folding.cycle_global_fold()
	MiniTest.expect.equality(vim.b[bufnr].org_markdown_global_fold_level, 1)

	-- Third cycle: 1 -> 2
	folding.cycle_global_fold()
	MiniTest.expect.equality(vim.b[bufnr].org_markdown_global_fold_level, 2)

	cleanup_buffer(bufnr)
end

T["cycle_global_fold - clears per-heading states"] = function()
	local bufnr = create_test_buffer({
		"# Heading",
	})
	vim.api.nvim_set_current_buf(bufnr)

	folding.setup_buffer_folding(bufnr)

	-- Set some per-heading state
	folding.set_fold_state(bufnr, 1, "folded")

	-- Cycle global fold
	folding.cycle_global_fold()

	-- Per-heading states should be cleared
	local states = vim.b[bufnr].org_markdown_fold_states
	MiniTest.expect.equality(vim.tbl_count(states), 0)

	cleanup_buffer(bufnr)
end

T["cycle_global_fold - does nothing on buffer with no headings"] = function()
	local bufnr = create_test_buffer({
		"Just content",
		"No headings here",
	})
	vim.api.nvim_set_current_buf(bufnr)

	folding.setup_buffer_folding(bufnr)

	local initial_level = vim.b[bufnr].org_markdown_global_fold_level

	-- Try to cycle
	folding.cycle_global_fold()

	-- Level should not change
	MiniTest.expect.equality(vim.b[bufnr].org_markdown_global_fold_level, initial_level)

	cleanup_buffer(bufnr)
end

return T
