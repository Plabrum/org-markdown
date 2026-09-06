local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local parser = require("org_markdown.utils.parser")

-- classify_entry: the four calendar/task shapes
T["classify_entry - dated + state -> task"] = function()
	local line = "# TODO Review PR <2026-08-24>"
	MiniTest.expect.equality(parser.classify_entry(line), "task")
end

T["classify_entry - dated + no state + no focus tag -> meeting"] = function()
	local line = "# Team sync <2026-08-24 Mon 11:30-12:00>"
	MiniTest.expect.equality(parser.classify_entry(line), "meeting")
end

T["classify_entry - dated + no state + :focus: tag -> focus"] = function()
	local line = "# Deep work <2026-08-24 Mon 09:00-11:00> :focus:"
	MiniTest.expect.equality(parser.classify_entry(line), "focus")
end

T["classify_entry - dated + state + :focus: tag -> task (assigned, no longer generic)"] = function()
	local line = "# TODO Deep work <2026-08-24 Mon 09:00-11:00> :focus:"
	MiniTest.expect.equality(parser.classify_entry(line), "task")
end

T["classify_entry - undated + state -> task"] = function()
	local line = "# TODO Write docs"
	MiniTest.expect.equality(parser.classify_entry(line), "task")
end

T["classify_entry - undated + no state -> nil"] = function()
	local line = "# Just a heading"
	MiniTest.expect.equality(parser.classify_entry(line), nil)
end

T["classify_entry - undated + :focus: tag alone is not a focus block"] = function()
	-- Focus blocks are calendar entries; a :focus: tag with no tracked date
	-- doesn't qualify (nothing to schedule).
	local line = "# Some note :focus:"
	MiniTest.expect.equality(parser.classify_entry(line), nil)
end

T["classify_entry - accepts a parsed table (not just a raw line)"] = function()
	local parsed = parser.parse_headline("# Focus time <2026-08-24 Mon 09:00-11:00> :focus:")
	MiniTest.expect.equality(parser.classify_entry(parsed), "focus")
end

T["classify_entry - nil input returns nil"] = function()
	MiniTest.expect.equality(parser.classify_entry(nil), nil)
end

-- is_focus_block / is_meeting helpers
T["is_focus_block - true for focus block"] = function()
	local line = "# Deep work <2026-08-24 Mon 09:00-11:00> :focus:"
	MiniTest.expect.equality(parser.is_focus_block(line), true)
end

T["is_focus_block - false for meeting"] = function()
	local line = "# Team sync <2026-08-24 Mon 11:30-12:00>"
	MiniTest.expect.equality(parser.is_focus_block(line), false)
end

T["is_focus_block - false for task"] = function()
	local line = "# TODO Review PR <2026-08-24>"
	MiniTest.expect.equality(parser.is_focus_block(line), false)
end

T["is_meeting - true for meeting"] = function()
	local line = "# Team sync <2026-08-24 Mon 11:30-12:00>"
	MiniTest.expect.equality(parser.is_meeting(line), true)
end

T["is_meeting - false for focus block"] = function()
	local line = "# Deep work <2026-08-24 Mon 09:00-11:00> :focus:"
	MiniTest.expect.equality(parser.is_meeting(line), false)
end

-- parse_headline: entry_type / is_focus fields
T["parse_headline - focus block sets entry_type and is_focus"] = function()
	local line = "# Deep work <2026-08-24 Mon 09:00-11:00> :focus:"
	local result = parser.parse_headline(line)
	MiniTest.expect.equality(result.entry_type, "focus")
	MiniTest.expect.equality(result.is_focus, true)
	MiniTest.expect.equality(result.state, nil)
	MiniTest.expect.equality(result.text, "Deep work")
end

T["parse_headline - meeting sets entry_type and is_focus=false"] = function()
	local line = "# Team sync <2026-08-24 Mon 11:30-12:00>"
	local result = parser.parse_headline(line)
	MiniTest.expect.equality(result.entry_type, "meeting")
	MiniTest.expect.equality(result.is_focus, false)
end

T["parse_headline - task sets entry_type and is_focus=false"] = function()
	local line = "# TODO Review PR <2026-08-24>"
	local result = parser.parse_headline(line)
	MiniTest.expect.equality(result.entry_type, "task")
	MiniTest.expect.equality(result.is_focus, false)
end

-- format_focus_block: creation path, round-tripped through parse_headline
T["format_focus_block - builds a task-less heading with time range"] = function()
	local line = parser.format_focus_block({
		title = "Deep work",
		date = "2026-08-24",
		start_time = "09:00",
		end_time = "11:00",
	})

	MiniTest.expect.equality(line, "# Deep work <2026-08-24 Mon 09:00-11:00> :focus:")

	local result = parser.parse_headline(line)
	MiniTest.expect.equality(result.entry_type, "focus")
	MiniTest.expect.equality(result.is_focus, true)
	MiniTest.expect.equality(result.state, nil)
	MiniTest.expect.equality(result.tracked, "2026-08-24")
	MiniTest.expect.equality(result.start_time, "09:00")
	MiniTest.expect.equality(result.end_time, "11:00")
	MiniTest.expect.equality(result.text, "Deep work")
end

T["format_focus_block - works without an end time"] = function()
	local line = parser.format_focus_block({
		title = "Deep work",
		date = "2026-08-24",
		start_time = "09:00",
	})

	local result = parser.parse_headline(line)
	MiniTest.expect.equality(result.entry_type, "focus")
	MiniTest.expect.equality(result.start_time, "09:00")
	MiniTest.expect.equality(result.end_time, nil)
end

T["format_focus_block - supports custom heading level and extra tags"] = function()
	local line = parser.format_focus_block({
		title = "Deep work",
		date = "2026-08-24",
		start_time = "09:00",
		end_time = "11:00",
		level = 2,
		tags = { "work" },
	})

	MiniTest.expect.equality(line, "## Deep work <2026-08-24 Mon 09:00-11:00> :focus:work:")

	local result = parser.parse_headline(line)
	MiniTest.expect.equality(result.entry_type, "focus")
	MiniTest.expect.equality(result.tags[1], "focus")
	MiniTest.expect.equality(result.tags[2], "work")
end

T["format_focus_block - does not duplicate the focus tag if passed in tags"] = function()
	local line = parser.format_focus_block({
		title = "Deep work",
		date = "2026-08-24",
		start_time = "09:00",
		tags = { "focus" },
	})

	local result = parser.parse_headline(line)
	local focus_count = 0
	for _, tag in ipairs(result.tags) do
		if tag == "focus" then
			focus_count = focus_count + 1
		end
	end
	MiniTest.expect.equality(focus_count, 1)
end

return T
