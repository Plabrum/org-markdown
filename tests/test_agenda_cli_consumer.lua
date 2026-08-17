local MiniTest = require("mini.test")

local pipeline = require("org_markdown.agenda.pipeline")
local agenda_cli = require("org_markdown.agenda.cli")
local config = require("org_markdown.config")
local config_export = require("org_markdown.utils.config_export")

-- Proves the in-editor agenda is a thin CLI consumer: the groups returned by the
-- CLI bridge (shell out to `org agenda --view <id>` + JSON decode) must match
-- what the in-process `pipeline.compute_view` oracle produces for the SAME live
-- config. Config parity flows through the exported temp config + env var, so a
-- custom `refile_paths` and custom view are used here to exercise that path.

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
		"## TODO Alpha subtask",
		"# IN_PROGRESS Beta task :home:",
		"# DONE Gamma task",
		"# Plain heading with no state",
	})

	write_file("cal.md", {
		"# Meeting one <2025-01-05>",
		"# TODO Meeting two <2025-01-06>",
	})

	-- Live in-editor config: custom refile_paths (only the fixture) and custom
	-- views that a defaults-only CLI would never know about.
	config.setup({
		org_dir = fixture_dir,
		refile_paths = { fixture_dir },
		agendas = {
			ignore_patterns = {},
			views = {
				custom_tasks = {
					title = "Custom Tasks",
					source = "tasks",
					filters = { states = { "TODO", "IN_PROGRESS" } },
					sort = { by = "title", order = "asc" },
					group_by = "state",
				},
				custom_cal = {
					title = "Custom Calendar",
					source = "calendar",
					sort = { by = "date", order = "asc" },
					group_by = "date",
				},
			},
		},
	})
end

-- Project an item onto its serializable fields (dropping the transient `node`
-- back-reference and normalizing empty arrays) so CLI-decoded items and oracle
-- items compare structurally.
local ITEM_FIELDS = {
	"title",
	"state",
	"priority",
	"date",
	"start_time",
	"end_time",
	"all_day",
	"line",
	"file",
	"source",
	"depth",
}

local function normalize_item(item)
	local out = {}
	for _, field in ipairs(ITEM_FIELDS) do
		out[field] = item[field]
	end

	local tags = {}
	for i, tag in ipairs(item.tags or {}) do
		tags[i] = tag
	end
	out.tags = tags

	local children = {}
	for i, child in ipairs(item.children or {}) do
		children[i] = normalize_item(child)
	end
	out.children = children

	return out
end

local function normalize_groups(groups)
	local out = {}
	for i, group in ipairs(groups) do
		local items = {}
		for j, item in ipairs(group.items) do
			items[j] = normalize_item(item)
		end
		out[i] = { key = group.key, items = items }
	end
	return out
end

local function oracle_groups(view_id)
	return pipeline.compute_view(view_id, config.agendas.views[view_id]).groups
end

local T = MiniTest.new_set({
	hooks = {
		pre_case = setup_fixture,
	},
})

T["compute_view (CLI) - task view matches the in-process pipeline"] = function()
	local cli_groups = assert(agenda_cli.compute_view("custom_tasks"))
	MiniTest.expect.equality(normalize_groups(cli_groups), normalize_groups(oracle_groups("custom_tasks")))
end

T["compute_view (CLI) - calendar view matches the in-process pipeline"] = function()
	local cli_groups = assert(agenda_cli.compute_view("custom_cal"))
	MiniTest.expect.equality(normalize_groups(cli_groups), normalize_groups(oracle_groups("custom_cal")))
end

T["compute_view (CLI) - preserves hierarchy (children) through JSON"] = function()
	local cli_groups = assert(agenda_cli.compute_view("custom_tasks"))

	-- Alpha task carries one subtask; confirm the child survived the round trip.
	local alpha
	for _, group in ipairs(cli_groups) do
		for _, item in ipairs(group.items) do
			if item.title == "Alpha task" then
				alpha = item
			end
		end
	end
	MiniTest.expect.equality(alpha ~= nil, true)
	MiniTest.expect.equality(#alpha.children, 1)
	MiniTest.expect.equality(alpha.children[1].title, "Alpha subtask")
end

T["compute_view (CLI) - unknown view fails gracefully with an error"] = function()
	local groups, err = agenda_cli.compute_view("no_such_view")
	MiniTest.expect.equality(groups, nil)
	MiniTest.expect.equality(type(err), "string")
end

T["config_export - round-trips the resolved config as a loadable chunk"] = function()
	local chunk = config_export.serialize(config._runtime)
	local loader = assert(loadstring(chunk))
	local restored = loader()

	MiniTest.expect.equality(restored.refile_paths, { fixture_dir })
	MiniTest.expect.equality(restored.agendas.views.custom_tasks.title, "Custom Tasks")
	MiniTest.expect.equality(restored.agendas.views.custom_tasks.filters.states, { "TODO", "IN_PROGRESS" })
end

return T
