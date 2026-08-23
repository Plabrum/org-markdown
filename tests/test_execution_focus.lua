local MiniTest = require("mini.test")
local helpers = require("helpers")

-- Covers focus blocks: the markdown one is, telling a block apart from a meeting
-- and from a task, reading blocks back off the calendar, and the refusals.

local config = require("org_markdown.config")
local focus = require("org_markdown.execution.focus")
local parser = require("org_markdown.utils.parser")
local utils = require("org_markdown.utils.utils")

local workspace = nil
local original_paths = nil

--- Offer a workspace of `{ [relative path] = lines }` as the only refile path.
local function with_workspace(files)
	workspace = helpers.create_temp_workspace(files)
	original_paths = config.refile_paths
	config.refile_paths = { workspace }
	return workspace
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

-- What a focus block is ------------------------------------------------------

T["format - a titled, dated, tagged heading with no state"] = function()
	local lines = focus.format({
		date = { year = 2026, month = 8, day = 23 },
		start_time = "09:00",
		end_time = "11:00",
	})

	MiniTest.expect.equality(lines[1], "# Focus <2026-08-23 Sun 09:00-11:00> :focus:")

	local headline = parser.parse_headline(lines[1])
	MiniTest.expect.equality(headline.state, nil)
	MiniTest.expect.equality(headline.text, "Focus")
	MiniTest.expect.equality(headline.tracked, "2026-08-23")
	MiniTest.expect.equality(headline.start_time, "09:00")
	MiniTest.expect.equality(headline.end_time, "11:00")
	MiniTest.expect.equality(headline.tags, { "focus" })
end

T["format - a block with no span is the whole day"] = function()
	local lines = focus.format({ title = "Deep work", date = "2026-08-23" })
	MiniTest.expect.equality(lines[1], "# Deep work <2026-08-23 Sun> :focus:")
end

-- Telling blocks apart -------------------------------------------------------

T["kind - a tagged, stateless calendar entry is a focus block"] = function()
	local headline = parser.parse_headline("# Focus <2026-08-23 Sun 09:00-11:00> :focus:")
	MiniTest.expect.equality(focus.kind(headline), focus.FOCUS)
	MiniTest.expect.equality(focus.is_focus(headline), true)
	MiniTest.expect.equality(focus.is_meeting(headline), false)
end

T["kind - an untagged calendar entry is a meeting"] = function()
	local headline = parser.parse_headline("# Kickoff <2026-08-23 Sun 14:00-15:00> :work:")
	MiniTest.expect.equality(focus.kind(headline), focus.MEETING)
	MiniTest.expect.equality(focus.is_meeting(headline), true)
	MiniTest.expect.equality(focus.is_focus(headline), false)
end

T["kind - a dated task stays a task, tag or no tag"] = function()
	MiniTest.expect.equality(focus.kind(parser.parse_headline("# TODO Write docs <2026-08-23 Sun>")), focus.TASK)
	MiniTest.expect.equality(
		focus.kind(parser.parse_headline("# TODO Write docs <2026-08-23 Sun> :focus:")),
		focus.TASK
	)
end

T["kind - a plain heading is neither"] = function()
	MiniTest.expect.equality(focus.kind(parser.parse_headline("# Notes")), nil)
end

T["kind - reads agenda items as well as parsed headlines"] = function()
	local item = { title = "Focus", date = "2026-08-23", tags = { "focus" } }
	MiniTest.expect.equality(focus.kind(item), focus.FOCUS)
end

-- Creating -------------------------------------------------------------------

T["create - writes a block onto the calendar"] = function()
	local root = with_workspace({ ["focus.md"] = { "" } })

	local created, err = focus.create({
		date = { year = 2026, month = 8, day = 23 },
		start_time = "09:00",
		end_time = "11:00",
	}, { file = root .. "/focus.md" })

	MiniTest.expect.equality(err, nil)
	MiniTest.expect.equality(created.date, "2026-08-23")
	MiniTest.expect.equality(utils.read_lines(root .. "/focus.md")[1], "# Focus <2026-08-23 Sun 09:00-11:00> :focus:")
end

T["create - lands the block under the destination heading"] = function()
	local root = with_workspace({ ["focus.md"] = { "# Blocks", "" } })

	focus.create({ date = "2026-08-23", start_time = "09:00" }, {
		file = root .. "/focus.md",
		heading = "Blocks",
	})

	local lines = utils.read_lines(root .. "/focus.md")
	MiniTest.expect.equality(lines[1], "# Blocks")

	local headline = parser.parse_headline(lines[2])
	MiniTest.expect.equality(lines[2]:match("^## ") ~= nil, true)
	MiniTest.expect.equality(headline.text, "Focus")
	MiniTest.expect.equality(headline.tracked, "2026-08-23")
	MiniTest.expect.equality(headline.start_time, "09:00")
	MiniTest.expect.equality(headline.tags, { "focus" })
end

T["create - defaults the destination to the configured file"] = function()
	local root = with_workspace({ ["focus.md"] = { "" } })
	local original = config.focus.file
	config.focus.file = root .. "/blocks.md"

	local created = focus.create({ date = "2026-08-23", start_time = "09:00" })
	config.focus.file = original

	MiniTest.expect.equality(created.file, root .. "/blocks.md")
	MiniTest.expect.equality(utils.read_lines(root .. "/blocks.md")[1]:match("Focus") ~= nil, true)
end

T["create - refuses a time that is not one"] = function()
	local created, err = focus.create({ start_time = "9am" })
	MiniTest.expect.equality(created, nil)
	MiniTest.expect.equality(err:match("is not a time") ~= nil, true)
end

T["create - refuses an end with nothing to bound"] = function()
	local created, err = focus.create({ end_time = "11:00" })
	MiniTest.expect.equality(created, nil)
	MiniTest.expect.equality(err:match("needs a start time") ~= nil, true)
end

-- Reading back ---------------------------------------------------------------

T["blocks - lists the blocks and not the meetings"] = function()
	local root = with_workspace({
		["calendar.md"] = {
			"# Kickoff <2026-08-23 Sun 14:00-15:00>",
			"",
			"# Focus <2026-08-23 Sun 09:00-11:00> :focus:",
			"",
			"# TODO Write docs <2026-08-23 Sun> :focus:",
			"",
		},
	})

	local blocks = focus.blocks()
	MiniTest.expect.equality(#blocks, 1)
	MiniTest.expect.equality(blocks[1].title, "Focus")
	MiniTest.expect.equality(blocks[1].start_time, "09:00")
	MiniTest.expect.equality(blocks[1].file, root .. "/calendar.md")
end

T["blocks - finds a block nested under another heading"] = function()
	with_workspace({
		["calendar.md"] = {
			"# Week",
			"",
			"## Focus <2026-08-23 Sun 09:00-11:00> :focus:",
			"",
		},
	})

	local blocks = focus.blocks()
	MiniTest.expect.equality(#blocks, 1)
	MiniTest.expect.equality(blocks[1].line, 3)
end

T["blocks - orders them earliest first and narrows to a day"] = function()
	with_workspace({
		["calendar.md"] = {
			"# Afternoon <2026-08-24 Mon 14:00-16:00> :focus:",
			"",
			"# Morning <2026-08-23 Sun 09:00-11:00> :focus:",
			"",
			"# Later <2026-08-23 Sun 13:00-14:00> :focus:",
			"",
		},
	})

	local titles = {}
	for _, block in ipairs(focus.blocks()) do
		table.insert(titles, block.title)
	end
	MiniTest.expect.equality(titles, { "Morning", "Later", "Afternoon" })

	local day = focus.blocks({ date = "2026-08-24" })
	MiniTest.expect.equality(#day, 1)
	MiniTest.expect.equality(day[1].title, "Afternoon")
end

-- Spans ----------------------------------------------------------------------

T["parse_span - reads a span, a bare start, and refuses the rest"] = function()
	MiniTest.expect.equality({ focus.parse_span("09:00-11:00") }, { "09:00", "11:00" })
	MiniTest.expect.equality({ focus.parse_span(" 09:00 ") }, { "09:00" })

	local start_time, err = focus.parse_span("9-11")
	MiniTest.expect.equality(start_time, nil)
	MiniTest.expect.equality(err:match("is not a time span") ~= nil, true)
end

return T
