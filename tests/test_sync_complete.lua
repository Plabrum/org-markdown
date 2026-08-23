local MiniTest = require("mini.test")
local helpers = require("helpers")

-- Covers mirroring a source's completion onto the heading promoted from it:
-- the heading going DONE with a completion date, the heading being found
-- through its `**Source:**` link rather than by where it sits, and the cases
-- there is nothing to complete.

local complete = require("org_markdown.sync.complete")
local config = require("org_markdown.config")
local ingest = require("org_markdown.sync.ingest")
local parser = require("org_markdown.utils.parser")
local promote = require("org_markdown.sync.promote")
local utils = require("org_markdown.utils.utils")

local KEY = "granola:9f21::Send the deck"
local DATE = { year = 2026, month = 8, day = 23 }

local workspace = nil
local original_paths = nil

--- A workspace holding a source log with one pending entry, offered as the only
--- refile path so the backlink scan sees it.
local function with_source_log()
	workspace = helpers.create_temp_workspace({
		["sources/granola.md"] = {
			"# TODO Send the deck :granola:",
			ingest.format_marker(KEY),
			"",
			"**Meeting:** Kickoff",
			"",
		},
		["refile.md"] = { "# Inbox", "" },
	})

	original_paths = config.refile_paths
	config.refile_paths = { workspace }
	return workspace
end

--- Promote the pending entry, as an earlier sync would have.
local function promoted(root, destination)
	local result, err = promote.entry({ file = root .. "/sources/granola.md", key = KEY }, {
		file = destination or (root .. "/refile.md"),
	})
	MiniTest.expect.equality(err, nil)
	return result
end

--- The parsed heading named `text` in a file, and the properties under it.
local function heading_in(file, text)
	local lines = utils.read_lines(file)
	for i, line in ipairs(lines) do
		local parsed = parser.parse_headline(line)
		if parsed and parsed.text == text then
			local properties = {}
			for j = i + 1, #lines do
				local key, value = lines[j]:match("^(%u[%u_]*): %[(.*)%]$")
				if not key then
					break
				end
				properties[key] = value
			end
			return parsed, properties
		end
	end
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

-- Reporting done --------------------------------------------------------------

T["reports_done - a done or cancelled item"] = function()
	MiniTest.expect.equality(complete.reports_done({ status = "DONE" }), true)
	MiniTest.expect.equality(complete.reports_done({ status = "CANCELLED" }), true)
	MiniTest.expect.equality(complete.reports_done({ done = true }), true)
	MiniTest.expect.equality(complete.reports_done({ status = "TODO" }), false)
	MiniTest.expect.equality(complete.reports_done({}), false)
end

-- Completing ------------------------------------------------------------------

T["entry - marks the promoted heading DONE"] = function()
	local root = with_source_log()
	promoted(root)

	local completed, err = complete.entry({ file = root .. "/sources/granola.md", key = KEY }, { date = DATE })

	MiniTest.expect.equality(err, nil)
	MiniTest.expect.equality(#completed, 1)
	MiniTest.expect.equality(completed[1].file, root .. "/refile.md")

	local headline = heading_in(root .. "/refile.md", "Send the deck")
	MiniTest.expect.equality(headline.state, "DONE")
end

T["entry - stamps the completion date in org format"] = function()
	local root = with_source_log()
	promoted(root)

	complete.entry({ file = root .. "/sources/granola.md", key = KEY }, { date = DATE })

	local _, properties = heading_in(root .. "/refile.md", "Send the deck")
	MiniTest.expect.equality(properties.COMPLETED_AT, "2026-08-23 Sun")
end

T["entry - finds the heading wherever the link now sits"] = function()
	local root = with_source_log()
	promoted(root, root .. "/planning.md")

	local completed = complete.entry({ file = root .. "/sources/granola.md", key = KEY }, { date = DATE })

	MiniTest.expect.equality(completed[1].file, root .. "/planning.md")
	MiniTest.expect.equality(heading_in(root .. "/planning.md", "Send the deck").state, "DONE")
end

T["entry - leaves a heading it has already completed alone"] = function()
	local root = with_source_log()
	promoted(root)
	complete.entry({ file = root .. "/sources/granola.md", key = KEY }, { date = DATE })

	local before = utils.read_lines(root .. "/refile.md")
	local completed = complete.entry({ file = root .. "/sources/granola.md", key = KEY })

	MiniTest.expect.equality(completed, {})
	MiniTest.expect.equality(utils.read_lines(root .. "/refile.md"), before)
end

T["entry - refuses an entry nothing was promoted from"] = function()
	local root = with_source_log()

	local completed, err = complete.entry({ file = root .. "/sources/granola.md", key = KEY })
	MiniTest.expect.equality(completed, nil)
	MiniTest.expect.equality(err:match("nothing was promoted") ~= nil, true)
end

T["entry - refuses a key the log does not carry"] = function()
	local root = with_source_log()

	local completed, err = complete.entry({ file = root .. "/sources/granola.md", key = "granola:nope" })
	MiniTest.expect.equality(completed, nil)
	MiniTest.expect.equality(err:match("no ingested entry") ~= nil, true)
end

-- Sweeping a pull's items -----------------------------------------------------

T["sweep - completes the headings of the items reporting done"] = function()
	local root = with_source_log()
	promoted(root)

	local completed = complete.sweep(root .. "/sources/granola.md", {
		{ title = "Send the deck", key = KEY, status = "DONE" },
		{ title = "Book the room", key = "granola:9f21::Book the room", status = "TODO" },
	}, { date = DATE })

	MiniTest.expect.equality(#completed, 1)
	MiniTest.expect.equality(heading_in(root .. "/refile.md", "Send the deck").state, "DONE")
end

T["sweep - passes over an item with nothing promoted from it"] = function()
	local root = with_source_log()

	local completed = complete.sweep(root .. "/sources/granola.md", {
		{ title = "Send the deck", key = KEY, status = "DONE" },
		{ title = "Never ingested", key = "granola:9f21::Never ingested", status = "DONE" },
	})

	MiniTest.expect.equality(completed, {})
	MiniTest.expect.equality(ingest.status_of(root .. "/sources/granola.md", KEY), ingest.STATUS.NEW)
end

return T
