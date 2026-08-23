local MiniTest = require("mini.test")

-- Execution state is derived, so an agenda view has to fold the log rather than
-- read anything off the heading. These cover a mixed-state task set travelling
-- through the pipeline and out the formatters, including the one task holding
-- the STARTED slot staying distinguishable from the rest.

local pipeline = require("org_markdown.agenda.pipeline")
local formatters = require("org_markdown.agenda_formatters")
local log = require("org_markdown.execution.log")
local config = require("org_markdown.config")

local fixture_dir
local tasks_file

local function setup_fixture()
	fixture_dir = vim.fn.tempname()
	vim.fn.mkdir(fixture_dir, "p")

	tasks_file = fixture_dir .. "/tasks.md"
	local f = assert(io.open(tasks_file, "w"))
	f:write(table.concat({
		"# TODO Running task",
		"# TODO Parked task",
		"# TODO Finished task",
		"# TODO Untouched task",
	}, "\n") .. "\n")
	f:close()

	config.setup({
		org_dir = fixture_dir,
		refile_paths = { fixture_dir },
		execution = { log_file = fixture_dir .. "/execution.log" },
		agendas = {
			ignore_patterns = {},
			views = {
				exec = {
					title = "Execution",
					source = "tasks",
					sort = { by = "title", order = "asc" },
				},
			},
		},
	})

	-- Parked started then paused, Finished ran through to DONE, and Running
	-- claimed the slot last -- so it is the one active task.
	local minute = 0
	local function event(title, from, to)
		minute = minute + 1
		log.append_event({ file = tasks_file, title = title }, {
			from = from,
			to = to,
			at = string.format("2026-08-23T18:%02d:00Z", minute),
		})
	end

	event("Parked task", "TODO", "STARTED")
	event("Parked task", "STARTED", "PAUSED")
	event("Finished task", "TODO", "STARTED")
	event("Finished task", "STARTED", "DONE")
	event("Running task", "TODO", "STARTED")
end

local function items_by_title()
	local result = pipeline.compute_view("exec", config.agendas.views.exec)
	local by_title = {}
	for _, group in ipairs(result.groups) do
		for _, item in ipairs(group.items) do
			by_title[item.title] = item
		end
	end
	return by_title
end

local T = MiniTest.new_set({
	hooks = {
		pre_case = setup_fixture,
		post_case = function()
			config.setup({})
		end,
	},
})

T["compute_view - carries each task's execution state from the log"] = function()
	local items = items_by_title()

	MiniTest.expect.equality(items["Running task"].execution, "STARTED")
	MiniTest.expect.equality(items["Parked task"].execution, "PAUSED")
	MiniTest.expect.equality(items["Finished task"].execution, "DONE")
	MiniTest.expect.equality(items["Untouched task"].execution, nil)

	-- The heading text never said any of this.
	MiniTest.expect.equality(items["Running task"].state, "TODO")
end

T["compute_view - only the task holding the STARTED slot is active"] = function()
	local items = items_by_title()

	MiniTest.expect.equality(items["Running task"].active, true)
	MiniTest.expect.equality(items["Parked task"].active, false)
	MiniTest.expect.equality(items["Finished task"].active, false)
	MiniTest.expect.equality(items["Untouched task"].active, nil)
end

T["format_timeline - renders execution state, marking the active task"] = function()
	local items = items_by_title()

	MiniTest.expect.equality(formatters.format_timeline(items["Running task"]), "TODO Running task ▶ STARTED")
	MiniTest.expect.equality(formatters.format_timeline(items["Parked task"]), "TODO Parked task ⏸ PAUSED")
	MiniTest.expect.equality(formatters.format_timeline(items["Finished task"]), "TODO Finished task ✓ DONE")
	MiniTest.expect.equality(formatters.format_timeline(items["Untouched task"]), "TODO Untouched task")
end

T["format_blocks - renders execution state before tags"] = function()
	local item = items_by_title()["Running task"]
	item.tags = { "work" }

	MiniTest.expect.equality(formatters.format_blocks(item), "Running task ▶ STARTED :work:")
end

return T
