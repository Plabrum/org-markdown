local MiniTest = require("mini.test")

-- Covers driving execution state from the heading under the cursor: locating the
-- task, the commands walking it through the states, and the auto-pause of the
-- previously started task being reported back to the user.

local commands = require("org_markdown.commands")
local config = require("org_markdown.config")
local heading = require("org_markdown.execution.heading")
local state = require("org_markdown.execution.state")

local notifications = {}
local original_notify = nil

--- Point the log at a fresh temp file and return its path. Folding is off so the
--- FileType autocmd does not schedule work against the throwaway buffers below.
local function use_temp_log()
	local path = vim.fn.tempname() .. ".log"
	config.setup({ execution = { log_file = path }, folding = { enabled = false } })
	return path
end

--- Open a buffer holding `lines` under a real path, cursor on `row`.
local function open_buffer(name, lines, row)
	local path = vim.fn.tempname() .. "-" .. name
	vim.fn.writefile(lines, path)
	vim.cmd("edit " .. vim.fn.fnameescape(path))
	vim.api.nvim_win_set_cursor(0, { row, 0 })
	return path
end

local T = MiniTest.new_set({
	hooks = {
		pre_case = function()
			notifications = {}
			original_notify = vim.notify
			vim.notify = function(msg)
				table.insert(notifications, msg)
			end
		end,
		post_case = function()
			vim.notify = original_notify
			config.setup({})
			-- `register` installs the editing autocmd for every markdown buffer;
			-- drop it again so it does not fire for the rest of the suite.
			vim.api.nvim_create_augroup("OrgMarkdownEditing", { clear = true })
		end,
	},
})

-- Finding the task ----------------------------------------------------------

T["task_at - takes the heading the cursor sits on"] = function()
	local lines = { "# Project", "## TODO [#A] Write the report <2026-08-23> :work:" }

	local task = heading.task_at(lines, 2, "/org/work.md")
	MiniTest.expect.equality(task.file, "/org/work.md")
	MiniTest.expect.equality(task.text, "Write the report")
	MiniTest.expect.equality(task.line, 2)
end

T["task_at - a body line belongs to the heading above it"] = function()
	local lines = { "# Project", "## TODO Write the report", "some notes", "more notes" }

	local task = heading.task_at(lines, 4, "/org/work.md")
	MiniTest.expect.equality(task.text, "Write the report")
	MiniTest.expect.equality(task.line, 2)
end

T["task_at - reports a cursor above every heading"] = function()
	local task, err = heading.task_at({ "intro", "# Project" }, 1)
	MiniTest.expect.equality(task, nil)
	MiniTest.expect.equality(err, "no heading at or above the cursor")
end

-- Reporting the outcome -----------------------------------------------------

T["summarize - names the task that moved"] = function()
	local events = { { task = "/org/work.md::Write the report", to = "STARTED" } }
	MiniTest.expect.equality(heading.summarize(events), "STARTED Write the report")
end

T["summarize - names the task that was auto-paused to make room"] = function()
	local events = {
		{ task = "/org/work.md::Read the brief", to = "PAUSED" },
		{ task = "/org/work.md::Write the report", to = "STARTED" },
	}
	MiniTest.expect.equality(heading.summarize(events), "STARTED Write the report (paused Read the brief)")
end

-- The commands --------------------------------------------------------------

T["commands - move the task under the cursor through the states"] = function()
	use_temp_log()
	commands.register()
	local path = open_buffer("work.md", { "## TODO Write the report" }, 1)
	local task = path .. "::Write the report"

	vim.cmd("MarkdownStartTask")
	MiniTest.expect.equality(state.state_of(task), "STARTED")

	vim.cmd("MarkdownPauseTask")
	MiniTest.expect.equality(state.state_of(task), "PAUSED")

	vim.cmd("MarkdownDoneTask")
	MiniTest.expect.equality(state.state_of(task), "DONE")
	MiniTest.expect.equality(notifications[#notifications], "DONE Write the report")
end

T["commands - starting one task pauses the started one, visibly"] = function()
	use_temp_log()
	commands.register()
	local first = open_buffer("first.md", { "## TODO Read the brief" }, 1)
	vim.cmd("MarkdownStartTask")

	open_buffer("second.md", { "## TODO Write the report" }, 1)
	vim.cmd("MarkdownStartTask")

	MiniTest.expect.equality(state.state_of(first .. "::Read the brief"), "PAUSED")
	MiniTest.expect.equality(notifications[#notifications], "STARTED Write the report (paused Read the brief)")
end

T["commands - report an illegal move instead of writing it"] = function()
	local path = use_temp_log()
	commands.register()
	open_buffer("work.md", { "## TODO Write the report" }, 1)

	vim.cmd("MarkdownPauseTask")
	MiniTest.expect.equality(notifications[#notifications]:find("cannot move") ~= nil, true)
	MiniTest.expect.equality(vim.fn.filereadable(path), 0)
end

T["commands - report a cursor with no heading above it"] = function()
	use_temp_log()
	commands.register()
	open_buffer("work.md", { "just prose" }, 1)

	vim.cmd("MarkdownStartTask")
	MiniTest.expect.equality(notifications[#notifications], "no heading at or above the cursor")
end

return T
