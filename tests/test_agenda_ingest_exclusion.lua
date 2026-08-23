local MiniTest = require("mini.test")

local pipeline = require("org_markdown.agenda.pipeline")
local ingest = require("org_markdown.sync.ingest")
local config = require("org_markdown.config")

-- Source logs must be untracked by construction: an ingested entry is raw source
-- material until it is promoted, so nothing in a log may reach an agenda view.
-- The log is deliberately placed outside `sources/` here, with empty
-- `ignore_patterns`, so the only thing that can keep it out is the registration
-- of its append-mode plugin.

local fixture_dir

local function write_file(name, lines)
	local path = fixture_dir .. "/" .. name
	local f = assert(io.open(path, "w"))
	f:write(table.concat(lines, "\n") .. "\n")
	f:close()
	return path
end

local log_path

local function setup_fixture()
	fixture_dir = vim.fn.tempname()
	vim.fn.mkdir(fixture_dir, "p")

	write_file("tasks.md", {
		"# TODO Promoted work <2025-01-05>",
	})

	log_path = write_file("granola-inbox.md", {
		"# TODO Ingested item <2025-01-05>",
		"<!-- key: granola:abc::Ingested item status: new -->",
	})

	config.setup({
		org_dir = fixture_dir,
		refile_paths = { fixture_dir },
		sync = {
			plugins = {
				granola = { mode = "append", sync_file = log_path },
			},
		},
		agendas = {
			ignore_patterns = {},
			views = {
				test_all = { title = "Everything", source = "all" },
				test_tasks = { title = "Tasks", source = "tasks" },
				test_cal = { title = "Calendar", source = "calendar" },
			},
		},
	})
end

local function titles(view_id)
	local result = pipeline.compute_view(view_id, config.agendas.views[view_id])
	local found = {}
	for _, group in ipairs(result.groups) do
		for _, item in ipairs(group.items) do
			table.insert(found, item.title)
		end
	end
	return found
end

local T = MiniTest.new_set({
	hooks = {
		pre_case = setup_fixture,
	},
})

T["log_paths - lists the sync file of every append-mode plugin"] = function()
	MiniTest.expect.equality(ingest.log_paths(), { log_path })
end

T["log_paths - ignores plugins that replace their file"] = function()
	config.sync.plugins.granola.mode = "replace"
	MiniTest.expect.equality(ingest.log_paths(), {})
end

T["ingestion log entries never reach an agenda view"] = function()
	for _, view_id in ipairs({ "test_all", "test_tasks", "test_cal" }) do
		MiniTest.expect.equality(titles(view_id), { "Promoted work" })
	end
end

T["a log outside sources/ is still excluded once ingestion stops"] = function()
	-- Nothing but the plugin registration keeps this log out: drop the append
	-- mode and its heading shows up, which is what the exclusion is preventing.
	config.sync.plugins.granola.mode = "replace"
	MiniTest.expect.equality(#titles("test_all"), 2)
end

return T
