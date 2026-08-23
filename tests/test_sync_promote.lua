local MiniTest = require("mini.test")
local helpers = require("helpers")

-- Covers promoting one ingested entry: the tracked TODO it becomes, the by-ID
-- link back to the source entry it carries, the entry being stamped promoted,
-- and the refusals (unknown key, already disposed of).

local config = require("org_markdown.config")
local ingest = require("org_markdown.sync.ingest")
local link = require("org_markdown.node.link")
local parser = require("org_markdown.utils.parser")
local pipeline = require("org_markdown.agenda.pipeline")
local promote = require("org_markdown.sync.promote")
local utils = require("org_markdown.utils.utils")

local KEY = "granola:9f21::Send the deck"

local workspace = nil
local original_paths = nil

--- Offer a workspace of `{ [relative path] = lines }` as the only refile path.
local function with_workspace(files)
	workspace = helpers.create_temp_workspace(files)
	original_paths = config.refile_paths
	config.refile_paths = { workspace }
	return workspace
end

--- A workspace holding a source log with one pending entry.
local function with_source_log(extra_lines)
	local lines = {
		"# TODO Send the deck :granola:",
		ingest.format_marker(KEY),
		"",
		"**Meeting:** Kickoff",
		"",
	}
	for _, line in ipairs(extra_lines or {}) do
		table.insert(lines, line)
	end

	return with_workspace({ ["sources/granola.md"] = lines, ["refile.md"] = { "# Inbox", "" } })
end

local T = MiniTest.new_set({
	hooks = {
		post_case = function()
			if workspace then
				config.refile_paths = original_paths
				helpers.cleanup_temp(workspace)
				workspace = nil
			end
		end,
	},
})

-- Promoting ------------------------------------------------------------------

T["entry - writes a tracked TODO into the destination"] = function()
	local root = with_source_log()

	local promoted, err = promote.entry(
		{ file = root .. "/sources/granola.md", key = KEY },
		{ file = root .. "/refile.md" },
		{ date = { year = 2026, month = 8, day = 23 } }
	)

	MiniTest.expect.equality(err, nil)
	MiniTest.expect.equality(promoted.text, "Send the deck")

	local headline = nil
	for _, line in ipairs(utils.read_lines(root .. "/refile.md")) do
		local parsed = parser.parse_headline(line)
		if parsed and parsed.text == "Send the deck" then
			headline = parsed
		end
	end

	MiniTest.expect.equality(headline.state, "TODO")
	MiniTest.expect.equality(headline.text, "Send the deck")
	MiniTest.expect.equality(headline.tracked, "2026-08-23")
	MiniTest.expect.equality(headline.tags, { "granola" })
end

T["entry - lands the TODO under the destination heading"] = function()
	local root = with_source_log()

	promote.entry({ file = root .. "/sources/granola.md", key = KEY }, {
		file = root .. "/refile.md",
		heading = "Inbox",
	})

	local lines = utils.read_lines(root .. "/refile.md")
	MiniTest.expect.equality(lines[1], "# Inbox")
	MiniTest.expect.equality(lines[2]:match("^## TODO Send the deck") ~= nil, true)
end

T["entry - carries a link that resolves back to the source entry"] = function()
	local root = with_source_log()

	local promoted = promote.entry({ file = root .. "/sources/granola.md", key = KEY }, {
		file = root .. "/refile.md",
	})

	local parsed = parser.parse_link(promoted.link)
	MiniTest.expect.equality(parsed.text, "Send the deck")

	local location = link.resolve(parsed.id)
	MiniTest.expect.equality(location.file, root .. "/sources/granola.md")
	MiniTest.expect.equality(location.heading, "Send the deck")
end

T["entry - stamps the source entry promoted"] = function()
	local root = with_source_log()
	local log = root .. "/sources/granola.md"

	promote.entry({ file = log, key = KEY }, { file = root .. "/refile.md" })

	MiniTest.expect.equality(ingest.status_of(log, KEY), ingest.STATUS.PROMOTED)
	MiniTest.expect.equality(#ingest.pending(log), 0)
end

T["entry - the promoted TODO appears in planning"] = function()
	local root = with_source_log()

	promote.entry({ file = root .. "/sources/granola.md", key = KEY }, { file = root .. "/refile.md" })

	local tasks = {}
	for _, item in ipairs(pipeline.scan_files().tasks) do
		if item.title == "Send the deck" then
			table.insert(tasks, item.file)
		end
	end

	-- The source log is out of the agenda's scope (`sources/*` is ignored), so
	-- only the promoted copy can account for this.
	MiniTest.expect.equality(tasks, { root .. "/refile.md" })
end

T["entry - defaults the destination to the configured file"] = function()
	local root = with_source_log()
	local original = config.promotion.file
	config.promotion.file = root .. "/planning.md"

	local promoted = promote.entry({ file = root .. "/sources/granola.md", key = KEY })
	config.promotion.file = original

	MiniTest.expect.equality(promoted.file, root .. "/planning.md")
	MiniTest.expect.equality(utils.read_lines(root .. "/planning.md")[1]:match("Send the deck") ~= nil, true)
end

-- Refusals -------------------------------------------------------------------

T["entry - refuses an entry the log does not carry"] = function()
	local root = with_source_log()

	local promoted, err = promote.entry({ file = root .. "/sources/granola.md", key = "granola:nope" })
	MiniTest.expect.equality(promoted, nil)
	MiniTest.expect.equality(err:match("no ingested entry") ~= nil, true)
end

T["entry - refuses an entry already disposed of"] = function()
	local root = with_source_log()
	local log = root .. "/sources/granola.md"
	ingest.set_status(log, KEY, ingest.STATUS.REJECTED)

	local promoted, err = promote.entry({ file = log, key = KEY }, { file = root .. "/refile.md" })
	MiniTest.expect.equality(promoted, nil)
	MiniTest.expect.equality(err:match("already rejected") ~= nil, true)
end

-- Entry lookup ---------------------------------------------------------------

T["find - reports the heading an entry was stamped under"] = function()
	local root = with_source_log()

	local entry = ingest.find(root .. "/sources/granola.md", KEY)
	MiniTest.expect.equality(entry.heading, "# TODO Send the deck :granola:")
	MiniTest.expect.equality(entry.status, ingest.STATUS.NEW)
end

T["find - still finds the heading once the entry carries an id"] = function()
	local root = with_source_log()
	local log = root .. "/sources/granola.md"

	-- Minting the entry's id puts a property line between heading and marker.
	link.to_target({ file = log, heading = "Send the deck" })

	local entry = ingest.find(log, KEY)
	MiniTest.expect.equality(entry.heading, "# TODO Send the deck :granola:")
end

return T
