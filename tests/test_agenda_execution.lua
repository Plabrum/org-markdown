local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local helpers = require("helpers")
local config = require("org_markdown.config")
local agenda = require("org_markdown.agenda")
local execution_log = require("org_markdown.utils.execution_log")

-- ============================================================
-- Reducer unit tests (pure, no filesystem/config involved)
-- ============================================================

T["reduce - START marks task STARTED and active"] = function()
	local result = execution_log.reduce({
		{ timestamp = "t1", verb = "START", id = "a" },
	})

	MiniTest.expect.equality(result.states.a, "STARTED")
	MiniTest.expect.equality(result.active, "a")
end

T["reduce - PAUSE marks task PAUSED and clears active"] = function()
	local result = execution_log.reduce({
		{ timestamp = "t1", verb = "START", id = "a" },
		{ timestamp = "t2", verb = "PAUSE", id = "a" },
	})

	MiniTest.expect.equality(result.states.a, "PAUSED")
	MiniTest.expect.equality(result.active, nil)
end

T["reduce - DONE marks task DONE and clears active"] = function()
	local result = execution_log.reduce({
		{ timestamp = "t1", verb = "START", id = "a" },
		{ timestamp = "t2", verb = "DONE", id = "a" },
	})

	MiniTest.expect.equality(result.states.a, "DONE")
	MiniTest.expect.equality(result.active, nil)
end

T["reduce - PAUSE on a non-active task does not clear active"] = function()
	local result = execution_log.reduce({
		{ timestamp = "t1", verb = "START", id = "a" },
		{ timestamp = "t2", verb = "PAUSE", id = "b" }, -- b was never active
	})

	MiniTest.expect.equality(result.states.a, "STARTED")
	MiniTest.expect.equality(result.states.b, "PAUSED")
	MiniTest.expect.equality(result.active, "a")
end

T["reduce - starting a new task demotes the previously active one to PAUSED"] = function()
	local result = execution_log.reduce({
		{ timestamp = "t1", verb = "START", id = "a" },
		{ timestamp = "t2", verb = "START", id = "b" },
	})

	-- Invariant: at most one active task at a time.
	MiniTest.expect.equality(result.states.a, "PAUSED")
	MiniTest.expect.equality(result.states.b, "STARTED")
	MiniTest.expect.equality(result.active, "b")
end

T["reduce - empty event list yields no states and no active task"] = function()
	local result = execution_log.reduce({})

	MiniTest.expect.equality(next(result.states), nil)
	MiniTest.expect.equality(result.active, nil)
end

T["parse_line - parses a well-formed event"] = function()
	local event = execution_log.parse_line("2026-01-01T09:00:00 START /tmp/foo.md:3")

	MiniTest.expect.equality(event.timestamp, "2026-01-01T09:00:00")
	MiniTest.expect.equality(event.verb, "START")
	MiniTest.expect.equality(event.id, "/tmp/foo.md:3")
end

T["parse_line - rejects unknown verbs"] = function()
	local event = execution_log.parse_line("2026-01-01T09:00:00 FROB /tmp/foo.md:3")
	MiniTest.expect.equality(event, nil)
end

T["parse_line - rejects malformed lines"] = function()
	MiniTest.expect.equality(execution_log.parse_line(""), nil)
	MiniTest.expect.equality(execution_log.parse_line("not an event"), nil)
	MiniTest.expect.equality(execution_log.parse_line(nil), nil)
end

T["read_events - missing file returns empty list"] = function()
	local events = execution_log.read_events("/nonexistent/path/execution.log")
	MiniTest.expect.equality(#events, 0)
end

T["read_events - skips malformed lines but keeps valid ones"] = function()
	local log_path = helpers.create_temp_file({
		"2026-01-01T09:00:00 START /tmp/foo.md:1",
		"garbage line",
		"2026-01-01T09:05:00 DONE /tmp/foo.md:1",
	}, ".log")

	local events = execution_log.read_events(log_path)
	MiniTest.expect.equality(#events, 2)
	MiniTest.expect.equality(events[1].verb, "START")
	MiniTest.expect.equality(events[2].verb, "DONE")

	helpers.cleanup_temp(log_path)
end

-- ============================================================
-- Integration: mixed-state task set rendered through the agenda
-- pipeline, with execution state sourced from the reducer.
-- ============================================================

T["agenda pipeline - renders execution state and a single active task"] = function()
	local original_refile_paths = config.refile_paths
	local original_execution = config.execution

	local workspace = helpers.create_temp_workspace({
		["tasks.md"] = {
			"## TODO Task A", -- line 1: will be STARTED + active
			"## IN_PROGRESS Task B", -- line 2: will be PAUSED
			"## TODO Task C", -- line 3: no execution events
			"## DONE Task D", -- line 4: will be DONE
		},
	})
	local task_file = workspace .. "/tasks.md"

	local log_path = helpers.create_temp_file({
		string.format("2026-01-01T09:00:00 START %s:2", task_file), -- Task B starts...
		string.format("2026-01-01T09:05:00 PAUSE %s:2", task_file), -- ...then pauses
		string.format("2026-01-01T09:10:00 START %s:4", task_file), -- Task D starts...
		string.format("2026-01-01T09:15:00 DONE %s:4", task_file), -- ...then finishes
		string.format("2026-01-01T09:20:00 START %s:1", task_file), -- Task A starts (stays active)
	}, ".log")

	config.setup({
		refile_paths = { workspace },
		execution = { log_file = log_path },
		agendas = {
			views = {
				exec_test = {
					title = "Execution Test",
					source = "tasks",
				},
			},
		},
	})

	local lines = agenda.process_view("exec_test")
	MiniTest.expect.no_equality(lines, nil)

	local function find_line(needle)
		for _, line in ipairs(lines) do
			if line:find(needle, 1, true) then
				return line
			end
		end
		return nil
	end

	local line_a = find_line("Task A")
	local line_b = find_line("Task B")
	local line_c = find_line("Task C")
	local line_d = find_line("Task D")

	MiniTest.expect.no_equality(line_a, nil)
	MiniTest.expect.no_equality(line_b, nil)
	MiniTest.expect.no_equality(line_c, nil)
	MiniTest.expect.no_equality(line_d, nil)

	-- Execution state is shown per task, sourced from the reducer.
	MiniTest.expect.no_equality(line_a:find("[STARTED]", 1, true), nil)
	MiniTest.expect.no_equality(line_b:find("[PAUSED]", 1, true), nil)
	MiniTest.expect.no_equality(line_d:find("[DONE]", 1, true), nil)

	-- Task C has no execution events: no execution-state tag rendered.
	MiniTest.expect.equality(line_c:find("[STARTED]", 1, true), nil)
	MiniTest.expect.equality(line_c:find("[PAUSED]", 1, true), nil)
	MiniTest.expect.equality(line_c:find("[DONE]", 1, true), nil)

	-- Exactly one task (Task A) is marked as the active task.
	MiniTest.expect.no_equality(line_a:find("▶", 1, true), nil)
	MiniTest.expect.equality(line_b:find("▶", 1, true), nil)
	MiniTest.expect.equality(line_c:find("▶", 1, true), nil)
	MiniTest.expect.equality(line_d:find("▶", 1, true), nil)

	local active_count = 0
	for _, line in ipairs(lines) do
		if line:find("▶", 1, true) then
			active_count = active_count + 1
		end
	end
	MiniTest.expect.equality(active_count, 1)

	-- Cleanup
	config.refile_paths = original_refile_paths
	config.execution = original_execution
	config.setup({})
	helpers.cleanup_temp(workspace)
	helpers.cleanup_temp(log_path)
end

return T
