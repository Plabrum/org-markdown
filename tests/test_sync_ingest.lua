local MiniTest = require("mini.test")

-- Covers append-only ingestion: the stable per-item key, the append primitive
-- that never rewrites prior entries, and the sync manager driving an
-- ingestion-mode plugin twice without duplicating what it already ingested.

local ingest = require("org_markdown.sync.ingest")
local manager = require("org_markdown.sync.manager")
local config = require("org_markdown.config")
local utils = require("org_markdown.utils.utils")

local function tmpfile()
	return vim.fn.tempname() .. ".md"
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

--- Count how often a line appears in the log.
local function occurrences(path, line)
	local count = 0
	for _, l in ipairs(utils.read_lines(path)) do
		if l == line then
			count = count + 1
		end
	end
	return count
end

local T = MiniTest.new_set({
	hooks = {
		post_case = function()
			manager.plugins.test_ingest = nil
			config.sync.plugins.test_ingest = nil
		end,
	},
})

-- entry_key ----------------------------------------------------------------

T["entry_key - prefers the key a plugin supplies"] = function()
	local key = ingest.entry_key({ key = "granola:9f21", title = "Send the deck" })
	MiniTest.expect.equality(key, "granola:9f21")
end

T["entry_key - derives a key from title and date"] = function()
	local key = ingest.entry_key({
		title = "Send the deck",
		start_date = { year = 2026, month = 8, day = 23 },
	})
	MiniTest.expect.equality(key, "Send the deck::2026-08-23")
end

T["entry_key - collapses whitespace so the key fits one line"] = function()
	local key = ingest.entry_key({ title = " Send\nthe   deck " })
	MiniTest.expect.equality(key, "Send the deck")
end

T["entry_key - nil for an item with no identity"] = function()
	MiniTest.expect.equality(ingest.entry_key({ title = "" }), nil)
end

-- marker round trip --------------------------------------------------------

T["format_marker - parse_marker is its inverse"] = function()
	local line = ingest.format_marker("granola:9f21::Send the deck", "promoted")
	MiniTest.expect.equality(ingest.parse_marker(line), {
		key = "granola:9f21::Send the deck",
		status = "promoted",
	})
end

T["format_marker - an entry lands as new"] = function()
	MiniTest.expect.equality(ingest.format_marker("a"), "<!-- key: a status: new -->")
end

T["parse_marker - a marker with no status reads as new"] = function()
	MiniTest.expect.equality(ingest.parse_marker("<!-- key: a -->"), { key = "a", status = "new" })
end

T["parse_marker - ignores ordinary lines"] = function()
	MiniTest.expect.equality(ingest.parse_marker("## TODO Send the deck"), nil)
end

-- append_entries -----------------------------------------------------------

T["append_entries - stamps the key under the heading"] = function()
	local path = tmpfile()

	ingest.append_entries(path, {
		{ key = "a", lines = { "## TODO First", "", "body", "" } },
	})

	MiniTest.expect.equality(read(path), "## TODO First\n<!-- key: a status: new -->\n\nbody\n\n")
end

T["append_entries - keeps prior entries untouched"] = function()
	local path = tmpfile()
	utils.write_lines(path, { "# Sources", "", "## TODO Hand written", "" })

	local appended = ingest.append_entries(path, {
		{ key = "a", lines = { "## TODO First", "" } },
	})

	MiniTest.expect.equality(appended, { "a" })
	local lines = utils.read_lines(path)
	MiniTest.expect.equality(lines[1], "# Sources")
	MiniTest.expect.equality(lines[3], "## TODO Hand written")
	MiniTest.expect.equality(lines[5], "## TODO First")
	MiniTest.expect.equality(lines[6], "<!-- key: a status: new -->")
end

T["append_entries - skips keys already in the log"] = function()
	local path = tmpfile()
	local entries = {
		{ key = "a", lines = { "## TODO First", "" } },
		{ key = "b", lines = { "## TODO Second", "" } },
	}

	ingest.append_entries(path, entries)
	local appended = ingest.append_entries(path, entries)

	MiniTest.expect.equality(appended, {})
	MiniTest.expect.equality(occurrences(path, "## TODO First"), 1)
	MiniTest.expect.equality(occurrences(path, "## TODO Second"), 1)
end

T["append_entries - appends only the entries that are new"] = function()
	local path = tmpfile()
	ingest.append_entries(path, { { key = "a", lines = { "## TODO First", "" } } })

	local appended = ingest.append_entries(path, {
		{ key = "a", lines = { "## TODO First", "" } },
		{ key = "b", lines = { "## TODO Second", "" } },
	})

	MiniTest.expect.equality(appended, { "b" })
	MiniTest.expect.equality(occurrences(path, "## TODO First"), 1)
	MiniTest.expect.equality(occurrences(path, "## TODO Second"), 1)
end

T["append_entries - drops repeats inside one batch"] = function()
	local path = tmpfile()

	local appended = ingest.append_entries(path, {
		{ key = "a", lines = { "## TODO First", "" } },
		{ key = "a", lines = { "## TODO First", "" } },
	})

	MiniTest.expect.equality(appended, { "a" })
	MiniTest.expect.equality(occurrences(path, "## TODO First"), 1)
end

T["append_entries - starts on a fresh line after an unterminated log"] = function()
	local path = tmpfile()
	local f = io.open(path, "w")
	f:write("## TODO Hand written")
	f:close()

	ingest.append_entries(path, { { key = "a", lines = { "## TODO First", "" } } })

	MiniTest.expect.equality(read(path), "## TODO Hand written\n## TODO First\n<!-- key: a status: new -->\n\n")
end

-- promotion status ---------------------------------------------------------

T["entries - reports every entry in file order"] = function()
	local path = tmpfile()
	ingest.append_entries(path, {
		{ key = "a", lines = { "## TODO First", "" } },
		{ key = "b", lines = { "## TODO Second", "" } },
	})

	MiniTest.expect.equality(ingest.entries(path), {
		{ key = "a", status = "new", line = 2, heading = "## TODO First", heading_line = 1 },
		{ key = "b", status = "new", line = 5, heading = "## TODO Second", heading_line = 4 },
	})
end

T["entries - none for a log that doesn't exist yet"] = function()
	MiniTest.expect.equality(ingest.entries(tmpfile()), {})
end

T["set_status - a promoted entry drops out of a later sweep"] = function()
	local path = tmpfile()
	ingest.append_entries(path, {
		{ key = "a", lines = { "## TODO First", "" } },
		{ key = "b", lines = { "## TODO Second", "" } },
	})

	ingest.set_status(path, "a", ingest.STATUS.PROMOTED)
	ingest.set_status(path, "b", ingest.STATUS.REJECTED)

	MiniTest.expect.equality(ingest.pending(path), {})
	MiniTest.expect.equality(ingest.status_of(path, "a"), "promoted")
	MiniTest.expect.equality(ingest.status_of(path, "b"), "rejected")
end

T["set_status - leaves the rest of the log untouched"] = function()
	local path = tmpfile()
	utils.write_lines(path, { "# Sources", "" })
	ingest.append_entries(path, { { key = "a", lines = { "## TODO First", "", "body", "" } } })

	ingest.set_status(path, "a", ingest.STATUS.PROMOTED)

	MiniTest.expect.equality(read(path), "# Sources\n\n## TODO First\n<!-- key: a status: promoted -->\n\nbody\n\n")
end

T["set_status - a status survives re-sync"] = function()
	local path = tmpfile()
	local entries = { { key = "a", lines = { "## TODO First", "" } } }

	ingest.append_entries(path, entries)
	ingest.set_status(path, "a", ingest.STATUS.PROMOTED)
	ingest.append_entries(path, entries)

	MiniTest.expect.equality(ingest.status_of(path, "a"), "promoted")
	MiniTest.expect.equality(occurrences(path, "## TODO First"), 1)
	MiniTest.expect.equality(ingest.pending(path), {})
end

T["set_status - rejects an unknown status"] = function()
	local path = tmpfile()
	ingest.append_entries(path, { { key = "a", lines = { "## TODO First", "" } } })

	local ok, err = ingest.set_status(path, "a", "maybe")
	MiniTest.expect.equality(ok, nil)
	MiniTest.expect.equality(err, "unknown ingestion status: maybe")
	MiniTest.expect.equality(ingest.status_of(path, "a"), "new")
end

T["set_status - reports a key the log doesn't carry"] = function()
	local path = tmpfile()
	ingest.append_entries(path, { { key = "a", lines = { "## TODO First", "" } } })

	local ok, err = ingest.set_status(path, "b", ingest.STATUS.PROMOTED)
	MiniTest.expect.equality(ok, nil)
	MiniTest.expect.equality(err, "no ingested entry with key b in " .. path)
end

T["status_of - nil for a key the log has never carried"] = function()
	MiniTest.expect.equality(ingest.status_of(tmpfile(), "a"), nil)
end

-- manager integration ------------------------------------------------------

--- Register an ingestion-mode plugin that always reports the same items.
local function use_ingest_plugin(path, items)
	local plugin = {
		name = "test_ingest",
		description = "Test Ingest",
		sync_file = path,
		mode = "append",
		pull = function()
			return { items = items, stats = { count = #items } }
		end,
	}

	manager.register_plugin(plugin)
	config.sync.plugins.test_ingest.enabled = true
	return plugin
end

T["sync_plugin - append mode ingests, then ingests nothing new"] = function()
	local path = tmpfile()
	use_ingest_plugin(path, {
		{ title = "Send the deck", status = "TODO", start_date = { year = 2026, month = 8, day = 23 } },
		{ title = "Book the room", status = "TODO" },
	})

	manager.sync_plugin("test_ingest")
	vim.wait(500, function()
		return read(path) ~= nil
	end)

	local first = utils.read_lines(path)
	MiniTest.expect.equality(first[1], "# TODO Send the deck <2026-08-23 Sun>")
	MiniTest.expect.equality(first[2], "<!-- key: Send the deck::2026-08-23 status: new -->")

	manager.sync_plugin("test_ingest")
	vim.wait(200)

	MiniTest.expect.equality(utils.read_lines(path), first)
end

T["sync_plugin - append mode never writes the auto-managed header"] = function()
	local path = tmpfile()
	use_ingest_plugin(path, { { title = "Send the deck" } })

	manager.sync_plugin("test_ingest")
	vim.wait(500, function()
		return read(path) ~= nil
	end)

	MiniTest.expect.equality(read(path):find("AUTO%-MANAGED"), nil)
end

return T
