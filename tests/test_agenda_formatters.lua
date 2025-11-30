local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local formatters = require("org_markdown.agenda_formatters")

-- Test blocks format
T["blocks - formats all-day events"] = function()
	local item = {
		title = "Birthday Party",
		all_day = true,
		tags = { "personal" },
	}

	local result = formatters.format_blocks(item, "")
	MiniTest.expect.no_equality(result:find("▓▓"), nil)
	MiniTest.expect.no_equality(result:find("Birthday Party"), nil)
	MiniTest.expect.no_equality(result:find("all%-day"), nil)
	MiniTest.expect.no_equality(result:find(":personal:"), nil)
end

T["blocks - formats all-day events with indentation"] = function()
	local item = {
		title = "Birthday Party",
		all_day = true,
		tags = { "personal" },
	}

	local result = formatters.format_blocks(item, "    ")
	MiniTest.expect.no_equality(result:find("^    ▓▓"), nil)
end

T["blocks - formats time range events"] = function()
	local item = {
		title = "Team Meeting",
		start_time = "14:00",
		end_time = "15:30",
		all_day = false,
		tags = { "work" },
	}

	local result = formatters.format_blocks(item, "")
	MiniTest.expect.no_equality(result:find("┌"), nil)
	MiniTest.expect.no_equality(result:find("14:00"), nil)
	MiniTest.expect.no_equality(result:find("15:30"), nil)
	MiniTest.expect.no_equality(result:find("Team Meeting"), nil)
	MiniTest.expect.no_equality(result:find(":work:"), nil)
end

T["blocks - formats simple time events"] = function()
	local item = {
		title = "Standup",
		start_time = "09:00",
		all_day = false,
		tags = {},
	}

	local result = formatters.format_blocks(item, "")
	MiniTest.expect.no_equality(result:find("09:00"), nil)
	MiniTest.expect.no_equality(result:find("Standup"), nil)
end

T["blocks - formats events without time"] = function()
	local item = {
		title = "Unscheduled Task",
		all_day = false,
		tags = { "todo" },
	}

	local result = formatters.format_blocks(item, "")
	MiniTest.expect.no_equality(result:find("Unscheduled Task"), nil)
	MiniTest.expect.no_equality(result:find(":todo:"), nil)
end

-- Test timeline format
T["timeline - formats task items with state and priority"] = function()
	local item = {
		title = "Fix bug",
		state = "TODO",
		priority = "A",
		start_time = "10:00",
		end_time = "11:00",
		all_day = false,
		tags = { "urgent" },
	}

	local result = formatters.format_timeline(item, "")
	MiniTest.expect.no_equality(result:find("TODO"), nil)
	MiniTest.expect.no_equality(result:find("%[A%]"), nil)
	MiniTest.expect.no_equality(result:find("Fix bug"), nil)
	MiniTest.expect.no_equality(result:find("10:00"), nil)
	MiniTest.expect.no_equality(result:find("11:00"), nil)
	MiniTest.expect.no_equality(result:find(":urgent:"), nil)
end

T["timeline - formats task items without priority"] = function()
	local item = {
		title = "Review PR",
		state = "IN_PROGRESS",
		all_day = false,
		tags = {},
	}

	local result = formatters.format_timeline(item, "")
	MiniTest.expect.no_equality(result:find("IN_PROGRESS"), nil)
	MiniTest.expect.no_equality(result:find("Review PR"), nil)
end

T["timeline - formats all-day calendar events"] = function()
	local item = {
		title = "Conference",
		all_day = true,
		tags = { "event" },
	}

	local result = formatters.format_timeline(item, "")
	MiniTest.expect.no_equality(result:find("ALL%-DAY"), nil)
	MiniTest.expect.no_equality(result:find("Conference"), nil)
	MiniTest.expect.no_equality(result:find(":event:"), nil)
end

T["timeline - formats timed calendar events"] = function()
	local item = {
		title = "Dentist Appointment",
		start_time = "14:00",
		end_time = "15:00",
		all_day = false,
		tags = {},
	}

	local result = formatters.format_timeline(item, "")
	MiniTest.expect.no_equality(result:find("14:00"), nil)
	MiniTest.expect.no_equality(result:find("15:00"), nil)
	MiniTest.expect.no_equality(result:find("Dentist Appointment"), nil)
end

T["timeline - applies indentation"] = function()
	local item = {
		title = "Task",
		state = "TODO",
		all_day = false,
		tags = {},
	}

	local result = formatters.format_timeline(item, "    ")
	MiniTest.expect.no_equality(result:find("^    "), nil)
end

-- Test format_item wrapper
T["format_item - delegates to blocks formatter"] = function()
	local item = {
		title = "Event",
		all_day = true,
		tags = {},
	}

	local result = formatters.format_item(item, { style = "blocks", indent = "" })
	MiniTest.expect.no_equality(result:find("▓▓"), nil)
end

T["format_item - delegates to timeline formatter"] = function()
	local item = {
		title = "Event",
		all_day = true,
		tags = {},
	}

	local result = formatters.format_item(item, { style = "timeline", indent = "" })
	MiniTest.expect.no_equality(result:find("ALL%-DAY"), nil)
end

T["format_item - uses default options"] = function()
	local item = {
		title = "Event",
		all_day = true,
		tags = {},
	}

	-- Should default to blocks style
	local result = formatters.format_item(item)
	MiniTest.expect.no_equality(result:find("▓▓"), nil)
end

T["format_item - errors on unknown style"] = function()
	local item = {
		title = "Event",
		all_day = true,
		tags = {},
	}

	local ok = pcall(formatters.format_item, item, { style = "invalid" })
	MiniTest.expect.equality(ok, false)
end

-- Test edge cases
T["edge_cases - handles empty tags array"] = function()
	local item = {
		title = "Event",
		all_day = true,
		tags = {},
	}

	local result = formatters.format_blocks(item, "")
	-- Should not have :: (empty tag marker)
	MiniTest.expect.equality(result:find("::"), nil)
end

T["edge_cases - handles multiple tags"] = function()
	local item = {
		title = "Event",
		all_day = true,
		tags = { "work", "urgent", "meeting" },
	}

	local result = formatters.format_blocks(item, "")
	MiniTest.expect.no_equality(result:find(":work:urgent:meeting:"), nil)
end

T["edge_cases - wraps long titles in blocks"] = function()
	local item = {
		title = "This is a very long title that should wrap to multiple lines when rendered in blocks format",
		start_time = "10:00",
		end_time = "11:00",
		all_day = false,
		tags = {},
	}

	local result = formatters.format_blocks(item, "")
	-- Should contain multiple lines (more than 2 newlines)
	local _, line_count = result:gsub("\n", "\n")
	MiniTest.expect.no_equality(line_count > 2, false)
end

return T
