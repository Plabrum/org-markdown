local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local execution = require("org_markdown.execution")
local utils = require("org_markdown.utils.utils")

local test_dir = "/tmp/org-markdown-test-execution"

local function create_test_buffer(lines, name)
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	if name then
		vim.api.nvim_buf_set_name(bufnr, name)
	end
	return bufnr
end

local function create_test_file(filename, lines)
	vim.fn.mkdir(test_dir, "p")
	local filepath = test_dir .. "/" .. filename
	utils.write_lines(filepath, lines)
	return filepath
end

-- ============================================================================
-- start()
-- ============================================================================

T["start - TODO becomes IN_PROGRESS"] = function()
	execution.reset()
	local bufnr = create_test_buffer({ "## TODO Write plugin" })
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })

	local ok = execution.start(bufnr)

	MiniTest.expect.equality(ok, true)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	MiniTest.expect.equality(lines[1], "## IN_PROGRESS Write plugin")
end

T["start - non-heading line returns false"] = function()
	execution.reset()
	local bufnr = create_test_buffer({ "Just some text" })
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })

	local ok = execution.start(bufnr)

	MiniTest.expect.equality(ok, false)
end

T["start - heading with no state returns false"] = function()
	execution.reset()
	local bufnr = create_test_buffer({ "## Just a heading" })
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })

	local ok = execution.start(bufnr)

	MiniTest.expect.equality(ok, false)
end

T["start - auto-pauses previously-started task in same buffer"] = function()
	execution.reset()
	local bufnr = create_test_buffer({
		"## IN_PROGRESS First task",
		"## TODO Second task",
	})
	vim.api.nvim_set_current_buf(bufnr)

	-- Register "First task" as the currently tracked task by starting it first.
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	execution.start(bufnr)

	-- Now start the second task; the first should auto-pause back to TODO.
	vim.api.nvim_win_set_cursor(0, { 2, 0 })
	local ok = execution.start(bufnr)

	MiniTest.expect.equality(ok, true)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	MiniTest.expect.equality(lines[1], "## TODO First task")
	MiniTest.expect.equality(lines[2], "## IN_PROGRESS Second task")
end

T["start - auto-pauses previously-started task in another file"] = function()
	execution.reset()
	local file_a = create_test_file("a.md", { "## IN_PROGRESS Task A" })
	local file_b = create_test_file("b.md", { "## TODO Task B" })

	local buf_a = create_test_buffer({ "## IN_PROGRESS Task A" }, file_a)
	local buf_b = create_test_buffer({ "## TODO Task B" }, file_b)

	-- Start task A first so it becomes the tracked "current" task.
	vim.api.nvim_set_current_buf(buf_a)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	execution.start(buf_a)

	-- Starting task B (a different open buffer) should auto-pause task A.
	vim.api.nvim_set_current_buf(buf_b)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	local ok = execution.start(buf_b)

	MiniTest.expect.equality(ok, true)
	local lines_a = vim.api.nvim_buf_get_lines(buf_a, 0, -1, false)
	local lines_b = vim.api.nvim_buf_get_lines(buf_b, 0, -1, false)
	MiniTest.expect.equality(lines_a[1], "## TODO Task A")
	MiniTest.expect.equality(lines_b[1], "## IN_PROGRESS Task B")
end

T["start - starting the already-current task does not notify a pause"] = function()
	execution.reset()
	local bufnr = create_test_buffer({ "## TODO Task" })
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })

	execution.start(bufnr)
	local ok = execution.start(bufnr)

	MiniTest.expect.equality(ok, true)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	MiniTest.expect.equality(lines[1], "## IN_PROGRESS Task")
end

-- ============================================================================
-- pause()
-- ============================================================================

T["pause - IN_PROGRESS becomes TODO"] = function()
	execution.reset()
	local bufnr = create_test_buffer({ "## IN_PROGRESS Task" })
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })

	local ok = execution.pause(bufnr)

	MiniTest.expect.equality(ok, true)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	MiniTest.expect.equality(lines[1], "## TODO Task")
end

T["pause - TODO task is left unchanged and returns false"] = function()
	execution.reset()
	local bufnr = create_test_buffer({ "## TODO Task" })
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })

	local ok = execution.pause(bufnr)

	MiniTest.expect.equality(ok, false)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	MiniTest.expect.equality(lines[1], "## TODO Task")
end

T["pause - clears tracked current task"] = function()
	execution.reset()
	local bufnr = create_test_buffer({ "## TODO Task" })
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })

	execution.start(bufnr)
	execution.pause(bufnr)

	-- Starting a second task now should not report any auto-pause of "Task",
	-- since pausing already cleared the tracked current task.
	local bufnr2 = create_test_buffer({ "## TODO Other" })
	vim.api.nvim_set_current_buf(bufnr2)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	local ok = execution.start(bufnr2)

	MiniTest.expect.equality(ok, true)
	local lines = vim.api.nvim_buf_get_lines(bufnr2, 0, -1, false)
	MiniTest.expect.equality(lines[1], "## IN_PROGRESS Other")
end

-- ============================================================================
-- done()
-- ============================================================================

T["done - TODO becomes DONE"] = function()
	execution.reset()
	local bufnr = create_test_buffer({ "## TODO Task" })
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })

	local ok = execution.done(bufnr)

	MiniTest.expect.equality(ok, true)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	MiniTest.expect.equality(lines[1]:match("^## DONE Task"), "## DONE Task")
end

T["done - adds COMPLETED_AT property"] = function()
	execution.reset()
	local bufnr = create_test_buffer({ "## IN_PROGRESS Task" })
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })

	execution.done(bufnr)

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local has_completed_at = false
	for _, line in ipairs(lines) do
		if line:match("^COMPLETED_AT: %[") then
			has_completed_at = true
		end
	end
	MiniTest.expect.equality(has_completed_at, true)
end

T["done - clears tracked current task"] = function()
	execution.reset()
	local bufnr = create_test_buffer({ "## TODO Task" })
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })

	execution.start(bufnr)
	execution.done(bufnr)

	local bufnr2 = create_test_buffer({ "## TODO Other" })
	vim.api.nvim_set_current_buf(bufnr2)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	local ok = execution.start(bufnr2)

	MiniTest.expect.equality(ok, true)
	local lines = vim.api.nvim_buf_get_lines(bufnr2, 0, -1, false)
	MiniTest.expect.equality(lines[1], "## IN_PROGRESS Other")
end

return T
