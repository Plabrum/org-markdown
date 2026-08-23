local MiniTest = require("mini.test")

-- Covers the state machine layered over the log and the reducer: which moves are
-- legal, and the single-STARTED invariant that starting one task auto-pauses
-- whatever was running.

local log = require("org_markdown.execution.log")
local state = require("org_markdown.execution.state")
local machine = require("org_markdown.execution.machine")
local config = require("org_markdown.config")

local function tmplog()
	return vim.fn.tempname() .. ".log"
end

--- Point the log at a fresh temp file and return its path.
local function use_temp_log()
	local path = tmplog()
	config.setup({ execution = { log_file = path } })
	return path
end

local function read_lines(path)
	local lines = {}
	for line in io.lines(path) do
		lines[#lines + 1] = line
	end
	return lines
end

local T = MiniTest.new_set({
	hooks = {
		post_case = function()
			config.setup({})
		end,
	},
})

-- Legal moves --------------------------------------------------------------

T["transition - an unmentioned task starts as if it were TODO"] = function()
	use_temp_log()

	local events = machine.transition("a::One", "STARTED", { at = "2026-08-23T18:01:00Z" })
	MiniTest.expect.equality(#events, 1)
	MiniTest.expect.equality(events[1].from, nil)
	MiniTest.expect.equality(events[1].to, "STARTED")
	MiniTest.expect.equality(state.state_of("a::One"), "STARTED")
end

T["transition - walks TODO to STARTED to PAUSED to DONE"] = function()
	use_temp_log()

	MiniTest.expect.no_equality(machine.transition("a::One", "STARTED"), nil)
	MiniTest.expect.no_equality(machine.transition("a::One", "PAUSED"), nil)
	MiniTest.expect.no_equality(machine.transition("a::One", "DONE"), nil)

	MiniTest.expect.equality(state.state_of("a::One"), "DONE")
	MiniTest.expect.equality(state.started_task(), nil)
end

T["transition - a paused task can be resumed"] = function()
	use_temp_log()
	machine.transition("a::One", "STARTED")
	machine.transition("a::One", "PAUSED")

	local events = machine.transition("a::One", "STARTED")
	MiniTest.expect.equality(events[1].from, "PAUSED")
	MiniTest.expect.equality(state.started_task(), "a::One")
end

T["transition - a started task can finish without pausing"] = function()
	use_temp_log()
	machine.transition("a::One", "STARTED")

	MiniTest.expect.no_equality(machine.transition("a::One", "DONE"), nil)
	MiniTest.expect.equality(state.started_task(), nil)
end

T["transition - records the task identity of an item table"] = function()
	use_temp_log()
	machine.transition({ file = "/org/work.md", title = "Write the report" }, "STARTED")

	MiniTest.expect.equality(state.started_task(), "/org/work.md::Write the report")
end

-- Illegal moves ------------------------------------------------------------

T["transition - refuses to start a task that is already started"] = function()
	local path = use_temp_log()
	machine.transition("a::One", "STARTED")

	local events, err = machine.transition("a::One", "STARTED")
	MiniTest.expect.equality(events, nil)
	MiniTest.expect.equality(err, "cannot move `a::One` from STARTED to STARTED")
	MiniTest.expect.equality(#read_lines(path), 1)
end

T["transition - refuses to pause a task that never started"] = function()
	use_temp_log()

	local events, err = machine.transition("a::One", "PAUSED")
	MiniTest.expect.equality(events, nil)
	MiniTest.expect.equality(err, "cannot move `a::One` from TODO to PAUSED")
end

T["transition - DONE is terminal"] = function()
	use_temp_log()
	machine.transition("a::One", "STARTED")
	machine.transition("a::One", "DONE")

	local events, err = machine.transition("a::One", "STARTED")
	MiniTest.expect.equality(events, nil)
	MiniTest.expect.equality(err, "cannot move `a::One` from DONE to STARTED")
end

T["transition - refuses a state the machine does not know"] = function()
	use_temp_log()

	local events, err = machine.transition("a::One", "WAITING")
	MiniTest.expect.equality(events, nil)
	MiniTest.expect.equality(err, "unknown execution state `WAITING`")
end

T["can - reports the legal moves out of each state"] = function()
	MiniTest.expect.equality(machine.can(nil, "STARTED"), true)
	MiniTest.expect.equality(machine.can("TODO", "STARTED"), true)
	MiniTest.expect.equality(machine.can("STARTED", "PAUSED"), true)
	MiniTest.expect.equality(machine.can("PAUSED", "DONE"), true)
	MiniTest.expect.equality(machine.can("TODO", "DONE"), false)
	MiniTest.expect.equality(machine.can("DONE", "STARTED"), false)
end

-- The single-STARTED invariant ---------------------------------------------

T["transition - starting B pauses the started A and leaves B the sole active task"] = function()
	local path = use_temp_log()
	machine.transition("a::One", "STARTED", { at = "2026-08-23T18:01:00Z" })

	local events = machine.transition("b::Two", "STARTED", { at = "2026-08-23T18:02:00Z" })
	MiniTest.expect.equality(#events, 2)
	MiniTest.expect.equality(events[1].task, "a::One")
	MiniTest.expect.equality(events[1].from, "STARTED")
	MiniTest.expect.equality(events[1].to, "PAUSED")
	MiniTest.expect.equality(events[2].task, "b::Two")
	MiniTest.expect.equality(events[2].to, "STARTED")

	local snapshot = state.snapshot()
	MiniTest.expect.equality(state.started_task(snapshot), "b::Two")
	MiniTest.expect.equality(state.state_of("a::One", snapshot), "PAUSED")

	-- The pause is written before the start it made room for, in one append.
	local lines = read_lines(path)
	MiniTest.expect.equality(#lines, 3)
	MiniTest.expect.equality(log.parse_event(lines[2]).to, "PAUSED")
	MiniTest.expect.equality(log.parse_event(lines[3]).to, "STARTED")
end

T["transition - the auto-pause resumes like any other pause"] = function()
	use_temp_log()
	machine.transition("a::One", "STARTED")
	machine.transition("b::Two", "STARTED")

	local events = machine.transition("a::One", "STARTED")
	MiniTest.expect.equality(#events, 2)
	MiniTest.expect.equality(events[1].task, "b::Two")
	MiniTest.expect.equality(events[2].from, "PAUSED")
	MiniTest.expect.equality(state.started_task(), "a::One")
end

T["transition - starting a task while nothing runs pauses nothing"] = function()
	use_temp_log()
	machine.transition("a::One", "STARTED")
	machine.transition("a::One", "PAUSED")

	local events = machine.transition("b::Two", "STARTED")
	MiniTest.expect.equality(#events, 1)
	MiniTest.expect.equality(events[1].task, "b::Two")
	MiniTest.expect.equality(state.state_of("a::One"), "PAUSED")
end

T["transition - answers from a supplied snapshot"] = function()
	use_temp_log()
	machine.transition("a::One", "STARTED")

	local snapshot = state.snapshot()
	local events = machine.transition("b::Two", "STARTED", { snapshot = snapshot })
	MiniTest.expect.equality(#events, 2)
	MiniTest.expect.equality(events[1].to, "PAUSED")
end

-- Standalone (no Neovim) ---------------------------------------------------

T["the machine runs under plain luajit"] = function()
	if vim.fn.executable("luajit") ~= 1 then
		MiniTest.skip("luajit not available on PATH")
		return
	end

	local path = use_temp_log()
	local cwd = vim.fn.getcwd()
	local script = string.format(
		[[package.path = "%s/lua/?.lua;%s/lua/?/init.lua;" .. package.path
		require("org_markdown.config").setup({ execution = { log_file = "%s" } })
		local machine = require("org_markdown.execution.machine")
		local state = require("org_markdown.execution.state")
		machine.transition("a::One", "STARTED")
		machine.transition("b::Two", "STARTED")
		io.write(state.state_of("a::One") .. " " .. state.started_task())]],
		cwd,
		cwd,
		path
	)

	local out = vim.fn.system({ "luajit", "-e", script })
	MiniTest.expect.equality(vim.v.shell_error, 0)
	MiniTest.expect.equality(out, "PAUSED b::Two")
end

return T
