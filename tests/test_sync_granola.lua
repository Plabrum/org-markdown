local MiniTest = require("mini.test")

-- Covers the Granola ingestion source: reading meetings out of the local
-- cache, pulling action items from generated summaries and hand-written notes,
-- and syncing them into the source log without ever touching prior entries.

local cache = require("org_markdown.sync.plugins.granola.cache")
local granola = require("org_markdown.sync.plugins.granola")
local manager = require("org_markdown.sync.manager")
local config = require("org_markdown.config")
local utils = require("org_markdown.utils.utils")

local HEADINGS = { "action items", "next steps" }

local function tmpfile(ext)
	return vim.fn.tempname() .. (ext or ".md")
end

local function read(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local content = f:read("*a")
	f:close()
	return content
end

--- Build a cache file in Granola's on-disk shape: the state is JSON nested in
--- the outer document's `cache` key as a string.
local function write_cache(state)
	local path = tmpfile(".json")
	local f = assert(io.open(path, "w"))
	f:write(vim.json.encode({ cache = vim.json.encode({ state = state }) }))
	f:close()
	return path
end

--- A finished meeting whose summary panel lists the given action items.
local function meeting(id, title, items, opts)
	opts = opts or {}
	local content = { { type = "heading", attrs = { level = 2 }, content = { { type = "text", text = "Action Items" } } } }
	for _, item in ipairs(items) do
		table.insert(content, {
			type = "listItem",
			content = { { type = "paragraph", content = { { type = "text", text = item } } } },
		})
	end

	return {
		document = {
			id = id,
			title = title,
			created_at = opts.created_at or "2026-08-20T09:00:00Z",
			updated_at = opts.updated_at or "2026-08-20T10:00:00Z",
			notes_markdown = opts.notes_markdown,
		},
		panel = { summary = { title = "Summary", content = { type = "doc", content = content } } },
	}
end

--- Assemble a cache state from `meeting()` results.
local function state_of(...)
	local documents, panels = {}, {}
	for _, m in ipairs({ ... }) do
		documents[m.document.id] = m.document
		panels[m.document.id] = m.panel
	end
	return { documents = documents, documentPanels = panels }
end

local T = MiniTest.new_set({
	hooks = {
		post_case = function()
			manager.plugins.granola = nil
			config.sync.plugins.granola = nil
		end,
	},
})

-- timestamps ----------------------------------------------------------------

T["parse_timestamp - reads a UTC timestamp"] = function()
	local epoch = cache.parse_timestamp("2026-08-20T10:00:00Z")
	MiniTest.expect.equality(os.date("!%Y-%m-%d %H:%M", epoch), "2026-08-20 10:00")
end

T["parse_timestamp - applies an explicit offset"] = function()
	local epoch = cache.parse_timestamp("2026-08-20T12:00:00+02:00")
	MiniTest.expect.equality(os.date("!%Y-%m-%d %H:%M", epoch), "2026-08-20 10:00")
end

T["parse_timestamp - nil for anything else"] = function()
	MiniTest.expect.equality(cache.parse_timestamp("not a timestamp"), nil)
	MiniTest.expect.equality(cache.parse_timestamp(nil), nil)
end

-- flattening ----------------------------------------------------------------

T["flatten - renders headings, paragraphs and bullets"] = function()
	local lines = cache.flatten({
		type = "doc",
		content = {
			{ type = "heading", attrs = { level = 2 }, content = { { type = "text", text = "Action Items" } } },
			{
				type = "bulletList",
				content = {
					{
						type = "listItem",
						content = { { type = "paragraph", content = { { type = "text", text = "Send the deck" } } } },
					},
				},
			},
			{ type = "paragraph", content = { { type = "text", text = "Discussed pricing" } } },
		},
	})

	MiniTest.expect.equality(lines, { "## Action Items", "- Send the deck", "Discussed pricing" })
end

T["flatten - keeps a list item's checkbox state"] = function()
	local lines = cache.flatten({
		type = "listItem",
		attrs = { checked = false },
		content = { { type = "paragraph", content = { { type = "text", text = "Book the room" } } } },
	})

	MiniTest.expect.equality(lines, { "- [ ] Book the room" })
end

-- action items --------------------------------------------------------------

T["action_items - takes bullets under an action-item heading"] = function()
	local items = cache.action_items({
		"## Summary",
		"- Talked about Q3",
		"## Action Items",
		"- Send the deck",
		"- Book the room",
	}, HEADINGS)

	MiniTest.expect.equality(items, { "Send the deck", "Book the room" })
end

T["action_items - the section ends at the next heading"] = function()
	local items = cache.action_items({
		"## Action Items",
		"- Send the deck",
		"## Notes",
		"- Not an action item",
	}, HEADINGS)

	MiniTest.expect.equality(items, { "Send the deck" })
end

T["action_items - takes an unchecked checkbox anywhere"] = function()
	local items = cache.action_items({ "## Notes", "- [ ] Send the deck" }, HEADINGS)
	MiniTest.expect.equality(items, { "Send the deck" })
end

T["action_items - skips an item already ticked off"] = function()
	local items = cache.action_items({ "## Action Items", "- [x] Send the deck", "- Book the room" }, HEADINGS)
	MiniTest.expect.equality(items, { "Book the room" })
end

T["action_items - reports an item once however often it appears"] = function()
	local items = cache.action_items({ "## Action Items", "- Send the deck", "- [ ] Send the deck" }, HEADINGS)
	MiniTest.expect.equality(items, { "Send the deck" })
end

-- meetings ------------------------------------------------------------------

T["load - decodes the nested cache document"] = function()
	local path = write_cache(state_of(meeting("m1", "Kickoff", { "Send the deck" })))

	local state = cache.load(path)
	MiniTest.expect.equality(state.documents.m1.title, "Kickoff")
end

T["load - reports a missing cache file"] = function()
	local state, err = cache.load("/does/not/exist.json")
	MiniTest.expect.equality(state, nil)
	MiniTest.expect.equality(err ~= nil, true)
end

T["meetings - only those that have finished"] = function()
	local state = state_of(
		meeting("done", "Kickoff", { "Send the deck" }),
		meeting("running", "Standup", { "Book the room" }, { updated_at = "2026-08-24T10:00:00Z" })
	)

	local meetings = cache.meetings(state, { now = cache.parse_timestamp("2026-08-23T10:00:00Z") })

	MiniTest.expect.equality(#meetings, 1)
	MiniTest.expect.equality(meetings[1].id, "done")
	MiniTest.expect.equality(meetings[1].title, "Kickoff")
end

T["meetings - ordered oldest first"] = function()
	local state = state_of(
		meeting("b", "Later", { "x" }, { updated_at = "2026-08-21T10:00:00Z" }),
		meeting("a", "Earlier", { "y" }, { updated_at = "2026-08-20T10:00:00Z" })
	)

	local meetings = cache.meetings(state, { now = cache.parse_timestamp("2026-08-23T10:00:00Z") })
	MiniTest.expect.equality({ meetings[1].title, meetings[2].title }, { "Earlier", "Later" })
end

T["meetings - carries both the summary and the hand-written notes"] = function()
	local state = state_of(meeting("m1", "Kickoff", { "Send the deck" }, {
		notes_markdown = "## Action Items\n- Book the room",
	}))

	local meetings = cache.meetings(state, { now = cache.parse_timestamp("2026-08-23T10:00:00Z") })
	MiniTest.expect.equality(cache.action_items(meetings[1].lines, HEADINGS), { "Send the deck", "Book the room" })
end

-- pull ----------------------------------------------------------------------

--- Register the plugin against a cache file and a source log of our own.
local function use_granola(cache_path, log_path)
	manager.register_plugin(granola)
	local plugin_config = config.sync.plugins.granola
	plugin_config.enabled = true
	plugin_config.cache_file = cache_path
	plugin_config.sync_file = log_path
	return plugin_config
end

T["pull - one item per action item, tagged with its origin"] = function()
	local plugin_config = use_granola(write_cache(state_of(meeting("m1", "Kickoff", { "Send the deck" }))), tmpfile())

	local result = granola.pull()

	MiniTest.expect.equality(#result.items, 1)
	local item = result.items[1]
	MiniTest.expect.equality(item.title, "Send the deck")
	MiniTest.expect.equality(item.status, "TODO")
	MiniTest.expect.equality(item.key, "granola:m1::Send the deck")

	local datetime = require("org_markdown.utils.datetime")
	local created = os.date("*t", cache.parse_timestamp("2026-08-20T09:00:00Z"))
	local expected_date = datetime.to_org_string({ year = created.year, month = created.month, day = created.day })
	MiniTest.expect.equality(item.body, "**Meeting:** Kickoff\n**Date:** " .. expected_date)
	MiniTest.expect.equality(plugin_config.mode, "append")
end

T["pull - reports a cache it cannot read"] = function()
	use_granola("/does/not/exist.json", tmpfile())

	local result, err = granola.pull()
	MiniTest.expect.equality(result, nil)
	MiniTest.expect.equality(err ~= nil, true)
end

-- sync ----------------------------------------------------------------------

--- Sync and wait for the log to reach the expected number of lines.
local function sync_and_wait(log_path, expected_lines)
	manager.sync_plugin("granola")
	vim.wait(1000, function()
		return #utils.read_lines(log_path) >= expected_lines
	end)
	return utils.read_lines(log_path)
end

T["sync - a finished meeting's action items land in the source log"] = function()
	local log_path = tmpfile()
	use_granola(write_cache(state_of(meeting("m1", "Kickoff", { "Send the deck" }))), log_path)

	local lines = sync_and_wait(log_path, 4)

	MiniTest.expect.equality(lines[1], "# TODO Send the deck :granola:")
	MiniTest.expect.equality(lines[2], "<!-- key: granola:m1::Send the deck status: new -->")
	MiniTest.expect.equality(lines[4], "**Meeting:** Kickoff")
	MiniTest.expect.equality(read(log_path):find("AUTO%-MANAGED"), nil)
end

T["sync - a later meeting appends without touching earlier entries"] = function()
	local log_path = tmpfile()
	local plugin_config = use_granola(write_cache(state_of(meeting("m1", "Kickoff", { "Send the deck" }))), log_path)

	local first = sync_and_wait(log_path, 4)

	-- The next meeting finishes; the cache now reports both.
	plugin_config.cache_file = write_cache(state_of(
		meeting("m1", "Kickoff", { "Send the deck" }),
		meeting("m2", "Review", { "Book the room" }, { updated_at = "2026-08-21T10:00:00Z" })
	))

	local second = sync_and_wait(log_path, #first + 4)

	for i, line in ipairs(first) do
		MiniTest.expect.equality(second[i], line)
	end
	MiniTest.expect.equality(second[#first + 1], "# TODO Book the room :granola:")
	MiniTest.expect.equality(second[#first + 2], "<!-- key: granola:m2::Book the room status: new -->")
end

T["sync - syncing again ingests nothing new"] = function()
	local log_path = tmpfile()
	use_granola(write_cache(state_of(meeting("m1", "Kickoff", { "Send the deck" }))), log_path)

	local first = sync_and_wait(log_path, 4)

	manager.sync_plugin("granola")
	vim.wait(300)

	MiniTest.expect.equality(utils.read_lines(log_path), first)
end

T["sync - the source log is kept out of agenda scanning"] = function()
	local queries = require("org_markdown.utils.queries")
	local root = vim.fn.tempname()
	vim.fn.mkdir(root .. "/sources", "p")
	utils.write_lines(root .. "/refile.md", { "# TODO Tracked" })
	utils.write_lines(root .. "/sources/granola.md", { "# TODO Ingested" })

	local refile_paths = config.refile_paths
	config.refile_paths = { root }
	local files = queries.find_markdown_files({ ignore_patterns = config.agendas.ignore_patterns })
	config.refile_paths = refile_paths

	local scanned = {}
	for _, file in ipairs(files) do
		scanned[file] = true
	end
	MiniTest.expect.equality(scanned[root .. "/refile.md"], true)
	MiniTest.expect.equality(scanned[root .. "/sources/granola.md"], nil)
end

return T
