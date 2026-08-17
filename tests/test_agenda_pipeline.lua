local MiniTest = require("mini.test")

local pipeline = require("org_markdown.agenda.pipeline")
local config = require("org_markdown.config")

-- Build a temp fixture directory with markdown files, point config at it, and
-- exercise the pure compute pipeline end-to-end (scan → filter → sort → group).

local fixture_dir

local function write_file(name, lines)
	local path = fixture_dir .. "/" .. name
	local f = assert(io.open(path, "w"))
	f:write(table.concat(lines, "\n") .. "\n")
	f:close()
	return path
end

local function setup_fixture()
	fixture_dir = vim.fn.tempname()
	vim.fn.mkdir(fixture_dir, "p")

	write_file("tasks.md", {
		"# TODO [#A] Alpha task :work:",
		"# IN_PROGRESS Beta task :home:",
		"# DONE Gamma task",
		"# Plain heading with no state",
	})

	write_file("cal.md", {
		"# Meeting one <2025-01-05>",
		"# TODO Meeting two <2025-01-06>",
		"# Untracked note [2025-01-07]",
	})

	-- Override config to scan only this fixture dir.
	config.setup({
		org_dir = fixture_dir,
		refile_paths = { fixture_dir },
		agendas = {
			ignore_patterns = {},
			views = {
				test_tasks = {
					title = "Test Tasks",
					source = "tasks",
					filters = { states = { "TODO", "IN_PROGRESS" } },
					sort = { by = "title", order = "asc" },
					group_by = "state",
				},
				test_cal = {
					title = "Test Calendar",
					source = "calendar",
					sort = { by = "date", order = "asc" },
					group_by = "date",
				},
			},
		},
	})
end

local function view(id)
	local def = config.agendas.views[id]
	return def
end

local T = MiniTest.new_set({
	hooks = {
		pre_case = setup_fixture,
	},
})

T["compute_view - returns view_id and title"] = function()
	local result = pipeline.compute_view("test_tasks", view("test_tasks"))
	MiniTest.expect.equality(result.view_id, "test_tasks")
	MiniTest.expect.equality(result.title, "Test Tasks")
end

T["compute_view - filters out DONE, groups by state, sorts by title"] = function()
	local result = pipeline.compute_view("test_tasks", view("test_tasks"))

	-- Group keys, in insertion order (TODO appears first in file, then IN_PROGRESS)
	local keys = {}
	for _, g in ipairs(result.groups) do
		table.insert(keys, g.key)
	end
	MiniTest.expect.equality(keys, { "TODO", "IN_PROGRESS" })

	-- TODO group: "Alpha task" (tasks.md) + "Meeting two" (cal.md, also a TODO),
	-- sorted by title ascending. DONE Gamma filtered, plain heading excluded.
	local todo = result.groups[1]
	MiniTest.expect.equality(#todo.items, 2)
	MiniTest.expect.equality(todo.items[1].title, "Alpha task")
	MiniTest.expect.equality(todo.items[1].state, "TODO")
	MiniTest.expect.equality(todo.items[1].priority, "A")
	MiniTest.expect.equality(todo.items[1].tags[1], "work")
	MiniTest.expect.equality(todo.items[2].title, "Meeting two")

	-- IN_PROGRESS group: "Beta task"
	local inprog = result.groups[2]
	MiniTest.expect.equality(#inprog.items, 1)
	MiniTest.expect.equality(inprog.items[1].title, "Beta task")
	MiniTest.expect.equality(inprog.items[1].state, "IN_PROGRESS")
end

T["compute_view - calendar source only includes tracked-date headings"] = function()
	local result = pipeline.compute_view("test_cal", view("test_cal"))

	-- Two tracked-date headings; untracked [2025-01-07] excluded.
	-- group_by date → one group per date, sorted ascending.
	local keys = {}
	local titles = {}
	for _, g in ipairs(result.groups) do
		table.insert(keys, g.key)
		for _, item in ipairs(g.items) do
			table.insert(titles, item.title)
		end
	end

	MiniTest.expect.equality(keys, { "2025-01-05", "2025-01-06" })
	MiniTest.expect.equality(titles, { "Meeting one", "Meeting two" })
end

T["scan_files - buckets headings by tasks/calendar/all"] = function()
	local data = pipeline.scan_files()

	-- 'all' has every top-level heading across both files (4 + 3 = 7)
	MiniTest.expect.equality(#data.all, 7)

	-- 'tasks' = headings with a state (Alpha, Beta, Gamma, Meeting two) = 4
	MiniTest.expect.equality(#data.tasks, 4)

	-- 'calendar' = headings with a tracked <date> (Meeting one, Meeting two) = 2
	MiniTest.expect.equality(#data.calendar, 2)
end

return T
