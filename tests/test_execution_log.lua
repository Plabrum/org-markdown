local MiniTest = require("mini.test")

-- Covers the append-only execution log: the on-disk record format, the append
-- primitive, and the round trip through parse_event. The final case runs the
-- module under a real `luajit` to prove it stays callable with NO Neovim.

local log = require("org_markdown.execution.log")
local config = require("org_markdown.config")

local function tmplog()
	return vim.fn.tempname() .. ".log"
end

local function read_lines(path)
	local lines = {}
	for line in io.lines(path) do
		lines[#lines + 1] = line
	end
	return lines
end

--- Point the log at a fresh temp file and return its path.
local function use_temp_log()
	local path = tmplog()
	config.setup({ execution = { log_file = path } })
	return path
end

local T = MiniTest.new_set({
	hooks = {
		post_case = function()
			config.setup({})
		end,
	},
})

-- task_id ------------------------------------------------------------------

T["task_id - builds file::heading identity"] = function()
	local id = log.task_id({ file = "/org/work.md", title = "Write the report" })
	MiniTest.expect.equality(id, "/org/work.md::Write the report")
end

T["task_id - accepts a parsed headline's text field"] = function()
	MiniTest.expect.equality(log.task_id({ file = "/org/work.md", text = "Ship it" }), "/org/work.md::Ship it")
end

T["task_id - falls back to the heading alone without a file"] = function()
	MiniTest.expect.equality(log.task_id({ title = "Standalone task" }), "Standalone task")
end

T["task_id - passes an explicit id through"] = function()
	MiniTest.expect.equality(log.task_id("/org/work.md::Write the report"), "/org/work.md::Write the report")
end

T["task_id - rejects a task with no heading text"] = function()
	local id, err = log.task_id({ file = "/org/work.md" })
	MiniTest.expect.equality(id, nil)
	MiniTest.expect.equality(type(err), "string")
end

-- format/parse round trip --------------------------------------------------

T["format_event - renders four tab-separated fields"] = function()
	local line = log.format_event({
		timestamp = "2026-08-23T18:04:11Z",
		from = "TODO",
		to = "STARTED",
		task = "/org/work.md::Write the report",
	})
	MiniTest.expect.equality(line, "2026-08-23T18:04:11Z\tTODO\tSTARTED\t/org/work.md::Write the report")
end

T["format_event - an absent from state renders as -"] = function()
	local line = log.format_event({ timestamp = "2026-08-23T18:04:11Z", to = "TODO", task = "x" })
	MiniTest.expect.equality(line, "2026-08-23T18:04:11Z\t-\tTODO\tx")
end

T["parse_event - round-trips an event"] = function()
	local event = {
		timestamp = "2026-08-23T18:04:11Z",
		from = "TODO",
		to = "STARTED",
		task = "/org/work.md::Write the report",
	}
	MiniTest.expect.equality(log.parse_event(log.format_event(event)), event)
end

T["parse_event - round-trips a first event with no from state"] = function()
	local event = { timestamp = "2026-08-23T18:04:11Z", to = "TODO", task = "/org/work.md::New task" }
	MiniTest.expect.equality(log.parse_event(log.format_event(event)), event)
end

T["parse_event - round-trips tabs and newlines in the task id"] = function()
	local event = {
		timestamp = "2026-08-23T18:04:11Z",
		from = "STARTED",
		to = "PAUSED",
		task = "/org/w\tk.md::Odd\nheading \\ here",
	}
	local line = log.format_event(event)
	MiniTest.expect.equality(line:find("\n", 1, true), nil)
	MiniTest.expect.equality(log.parse_event(line), event)
end

T["parse_event - ignores blank and malformed lines"] = function()
	MiniTest.expect.equality(log.parse_event(""), nil)
	MiniTest.expect.equality(log.parse_event("not a log line"), nil)
	MiniTest.expect.equality(log.parse_event("2026-08-23T18:04:11Z\tTODO\tSTARTED"), nil)
end

-- append_event -------------------------------------------------------------

T["append_event - writes one parseable line"] = function()
	local path = use_temp_log()

	local event = log.append_event({ file = "/org/work.md", title = "Write the report" }, {
		from = "TODO",
		to = "STARTED",
		at = "2026-08-23T18:04:11Z",
	})

	MiniTest.expect.equality(event.task, "/org/work.md::Write the report")

	local lines = read_lines(path)
	MiniTest.expect.equality(#lines, 1)
	MiniTest.expect.equality(log.parse_event(lines[1]), event)
end

T["append_event - stamps an ISO-8601 UTC timestamp by default"] = function()
	use_temp_log()

	local event = log.append_event("task", { to = "TODO" })
	MiniTest.expect.equality(event.timestamp:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$") ~= nil, true)
end

T["append_event - never overwrites earlier entries"] = function()
	local path = use_temp_log()

	log.append_event("a::One", { to = "TODO", at = "2026-08-23T18:00:00Z" })
	log.append_event("a::One", { from = "TODO", to = "STARTED", at = "2026-08-23T18:01:00Z" })
	log.append_event("b::Two", { from = "TODO", to = "STARTED", at = "2026-08-23T18:02:00Z" })

	local lines = read_lines(path)
	MiniTest.expect.equality(#lines, 3)

	local seen = {}
	for i, line in ipairs(lines) do
		local event = log.parse_event(line)
		seen[i] = event.task .. " " .. event.to .. " @" .. event.timestamp
	end
	MiniTest.expect.equality(seen, {
		"a::One TODO @2026-08-23T18:00:00Z",
		"a::One STARTED @2026-08-23T18:01:00Z",
		"b::Two STARTED @2026-08-23T18:02:00Z",
	})
end

T["append_event - rejects a transition with no target state"] = function()
	local path = use_temp_log()

	local event, err = log.append_event("a::One", {})
	MiniTest.expect.equality(event, nil)
	MiniTest.expect.equality(type(err), "string")
	MiniTest.expect.equality(vim.fn.filereadable(path), 0)
end

T["append_event - reports an unwritable log path"] = function()
	config.setup({ execution = { log_file = "/nonexistent-dir/execution.log" } })

	local event, err = log.append_event("a::One", { to = "TODO" })
	MiniTest.expect.equality(event, nil)
	MiniTest.expect.equality(type(err), "string")
end

-- Standalone (no Neovim) ---------------------------------------------------

T["append_event works under plain luajit"] = function()
	if vim.fn.executable("luajit") ~= 1 then
		MiniTest.skip("luajit not available on PATH")
		return
	end

	local path = tmplog()
	local cwd = vim.fn.getcwd()
	local script = string.format(
		[[package.path = "%s/lua/?.lua;%s/lua/?/init.lua;" .. package.path
		require("org_markdown.config").setup({ execution = { log_file = "%s" } })
		local log = require("org_markdown.execution.log")
		log.append_event({ file = "/org/work.md", title = "From the CLI" }, { from = "TODO", to = "STARTED" })]],
		cwd,
		cwd,
		path
	)

	vim.fn.system({ "luajit", "-e", script })
	MiniTest.expect.equality(vim.v.shell_error, 0)

	local lines = read_lines(path)
	MiniTest.expect.equality(#lines, 1)
	MiniTest.expect.equality(log.parse_event(lines[1]).task, "/org/work.md::From the CLI")
end

return T
