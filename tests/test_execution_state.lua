local MiniTest = require("mini.test")

-- Covers the reducer that folds the append-only log into current state: the
-- state of any single task, and the one globally-STARTED task. Everything here
-- is derived from log contents alone -- nothing is ever read off a heading.

local log = require("org_markdown.execution.log")
local state = require("org_markdown.execution.state")
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

--- Append a run of transitions to the configured log, one minute apart.
local function write_events(events)
	for i, event in ipairs(events) do
		log.append_event(event[1], {
			from = event[2],
			to = event[3],
			at = string.format("2026-08-23T18:%02d:00Z", i),
		})
	end
end

local T = MiniTest.new_set({
	hooks = {
		post_case = function()
			config.setup({})
		end,
	},
})

-- Empty log ----------------------------------------------------------------

T["snapshot - a log that does not exist yet is an empty log"] = function()
	config.setup({ execution = { log_file = tmplog() } })

	local snapshot = state.snapshot()
	MiniTest.expect.equality(snapshot.tasks, {})
	MiniTest.expect.equality(snapshot.started, nil)
	MiniTest.expect.equality(state.state_of("a::One"), nil)
	MiniTest.expect.equality(state.started_task(), nil)
end

T["fold - an empty event stream yields no state"] = function()
	local snapshot = state.fold({})
	MiniTest.expect.equality(snapshot.tasks, {})
	MiniTest.expect.equality(snapshot.started, nil)
end

-- Per-task state -----------------------------------------------------------

T["state_of - reports the latest event for a task"] = function()
	use_temp_log()
	write_events({
		{ "a::One", nil, "TODO" },
		{ "a::One", "TODO", "STARTED" },
		{ "a::One", "STARTED", "PAUSED" },
	})

	local current, entry = state.state_of("a::One")
	MiniTest.expect.equality(current, "PAUSED")
	MiniTest.expect.equality(entry.from, "STARTED")
	MiniTest.expect.equality(entry.since, "2026-08-23T18:03:00Z")
end

T["state_of - tracks each task independently"] = function()
	use_temp_log()
	write_events({
		{ "a::One", nil, "TODO" },
		{ "b::Two", nil, "TODO" },
		{ "a::One", "TODO", "DONE" },
	})

	MiniTest.expect.equality(state.state_of("a::One"), "DONE")
	MiniTest.expect.equality(state.state_of("b::Two"), "TODO")
end

T["state_of - an unmentioned task has no state"] = function()
	use_temp_log()
	write_events({ { "a::One", nil, "TODO" } })

	MiniTest.expect.equality(state.state_of("b::Two"), nil)
end

T["state_of - accepts an item table as the task identity"] = function()
	use_temp_log()
	log.append_event({ file = "/org/work.md", title = "Write the report" }, { to = "STARTED" })

	MiniTest.expect.equality(state.state_of({ file = "/org/work.md", title = "Write the report" }), "STARTED")
end

T["state_of - answers from a supplied snapshot without re-reading"] = function()
	use_temp_log()
	write_events({ { "a::One", nil, "TODO" } })

	local snapshot = state.snapshot()
	write_events({ { "a::One", "TODO", "DONE" } })

	MiniTest.expect.equality(state.state_of("a::One", snapshot), "TODO")
	MiniTest.expect.equality(state.state_of("a::One"), "DONE")
end

-- The globally-STARTED task ------------------------------------------------

T["started_task - nothing is running until a task starts"] = function()
	use_temp_log()
	write_events({
		{ "a::One", nil, "TODO" },
		{ "b::Two", nil, "TODO" },
	})

	MiniTest.expect.equality(state.started_task(), nil)
end

T["started_task - reports the task that entered STARTED"] = function()
	use_temp_log()
	write_events({
		{ "a::One", nil, "TODO" },
		{ "b::Two", nil, "TODO" },
		{ "b::Two", "TODO", "STARTED" },
	})

	local task, entry = state.started_task()
	MiniTest.expect.equality(task, "b::Two")
	MiniTest.expect.equality(entry.since, "2026-08-23T18:03:00Z")
end

T["started_task - leaving STARTED releases the slot"] = function()
	use_temp_log()
	write_events({
		{ "a::One", nil, "TODO" },
		{ "a::One", "TODO", "STARTED" },
		{ "a::One", "STARTED", "DONE" },
	})

	MiniTest.expect.equality(state.started_task(), nil)
	MiniTest.expect.equality(state.state_of("a::One"), "DONE")
end

T["started_task - only the most recent start holds the slot"] = function()
	local snapshot = state.fold({
		{ timestamp = "2026-08-23T18:01:00Z", to = "STARTED", task = "a::One" },
		{ timestamp = "2026-08-23T18:02:00Z", to = "STARTED", task = "b::Two" },
	})

	MiniTest.expect.equality(state.started_task(snapshot), "b::Two")
end

T["started_task - a later task leaving STARTED does not free another's slot"] = function()
	local snapshot = state.fold({
		{ timestamp = "2026-08-23T18:01:00Z", to = "STARTED", task = "a::One" },
		{ timestamp = "2026-08-23T18:02:00Z", from = "TODO", to = "DONE", task = "b::Two" },
	})

	MiniTest.expect.equality(state.started_task(snapshot), "a::One")
end

T["started_task - a task may be restarted after a pause"] = function()
	use_temp_log()
	write_events({
		{ "a::One", nil, "TODO" },
		{ "a::One", "TODO", "STARTED" },
		{ "a::One", "STARTED", "PAUSED" },
		{ "a::One", "PAUSED", "STARTED" },
	})

	MiniTest.expect.equality(state.started_task(), "a::One")
	MiniTest.expect.equality(state.state_of("a::One"), "STARTED")
end

-- Reading the log ----------------------------------------------------------

T["read_events - returns events in write order and skips junk lines"] = function()
	local path = use_temp_log()
	write_events({
		{ "a::One", nil, "TODO" },
		{ "a::One", "TODO", "STARTED" },
	})

	local file = io.open(path, "a")
	file:write("\nnot a log line\n")
	file:close()

	local events = state.read_events()
	MiniTest.expect.equality(#events, 2)
	MiniTest.expect.equality(events[1].to, "TODO")
	MiniTest.expect.equality(events[2].to, "STARTED")
end

-- Standalone (no Neovim) ---------------------------------------------------

T["state is derivable under plain luajit"] = function()
	if vim.fn.executable("luajit") ~= 1 then
		MiniTest.skip("luajit not available on PATH")
		return
	end

	local path = use_temp_log()
	write_events({
		{ "a::One", nil, "TODO" },
		{ "a::One", "TODO", "STARTED" },
	})

	local cwd = vim.fn.getcwd()
	local script = string.format(
		[[package.path = "%s/lua/?.lua;%s/lua/?/init.lua;" .. package.path
		require("org_markdown.config").setup({ execution = { log_file = "%s" } })
		local state = require("org_markdown.execution.state")
		io.write(state.state_of("a::One") .. " " .. state.started_task())]],
		cwd,
		cwd,
		path
	)

	local out = vim.fn.system({ "luajit", "-e", script })
	MiniTest.expect.equality(vim.v.shell_error, 0)
	MiniTest.expect.equality(out, "STARTED a::One")
end

return T
