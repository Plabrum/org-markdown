local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local parser = require("org_markdown.parser")

-- Heading Parsing
-- T["parse_heading - TODO with priority and tags"] = function()
-- 	local line = "# TODO [#A] Write tests :work:urgent:"
-- 	local state, pri, text, tags = parser.parse_heading(line)
-- 	MiniTest.expect.equality(state, "TODO")
-- 	MiniTest.expect.equality(pri, "#A")
-- 	MiniTest.expect.equality(text, "Write tests")
-- 	MiniTest.expect.equality(tags[1], "work")
-- 	MiniTest.expect.equality(tags[2], "urgent")
-- end
--
-- T["parse_heading - IN_PROGRESS without priority"] = function()
-- 	local line = "# IN_PROGRESS Refactor parser :dev:"
-- 	local state, pri, text, tags = parser.parse_heading(line)
-- 	MiniTest.expect.equality(state, "IN_PROGRESS")
-- 	MiniTest.expect.equality(pri, nil)
-- 	MiniTest.expect.equality(text, "Refactor parser")
-- 	MiniTest.expect.equality(tags[1], "dev")
-- end
--
-- T["parse_heading - ignored DONE heading"] = function()
-- 	local line = "# DONE [#B] Completed work :done:"
-- 	local state = parser.parse_heading(line)
-- 	MiniTest.expect.equality(state, nil)
-- end

-- Date Extraction
-- T["extract_date - tracked and untracked dates"] = function()
-- 	local line = "- [ ] TODO task <2025-06-22> [2025-06-23]"
-- 	local tracked, untracked = parser.extract_date(line)
-- 	MiniTest.expect.equality(tracked, "2025-06-22")
-- 	MiniTest.expect.equality(untracked, "2025-06-23")
-- end
--
-- T["extract_date - no date returns nil"] = function()
-- 	local line = "No date here"
-- 	local tracked, untracked = parser.extract_date(line)
-- 	MiniTest.expect.equality(tracked, nil)
-- 	MiniTest.expect.equality(untracked, nil)
-- end

-- Safe substitution (with capture characters)
local function capture_template_substitor(s, marker, repl)
	return parser.escaped_substitute(s, marker, repl, { escape_chars = { "^", "?", "%" } })
end

T["escaped_substitute - no match returns original string"] = function()
	local result = capture_template_substitor("No match here", "%notfound", "replacement")
	MiniTest.expect.equality(result, "No match here")
end

T["escaped_substitute - single match with string replacement"] = function()
	local result = capture_template_substitor("Hello %name, word", "%name", "John")
	MiniTest.expect.equality(result, "Hello John, word")
end

T["escaped_substitute - check ^ is escaped correctly"] = function()
	local result = capture_template_substitor("first %^{filler} third", "%^{filler}", "second")
	MiniTest.expect.equality(result, "first second third")
end

T["escaped_substitute - check dynamic substitution is escaped correctly"] = function()
	local result = capture_template_substitor("first %^{filler} third", "%^{.-}", "second")
	MiniTest.expect.equality(result, "first second third")
end

T["escaped_substitute - check cursor_swap %? is escaped correctly"] = function()
	local result = capture_template_substitor(">%?<", "%?", "")
	MiniTest.expect.equality(result, "><")
end

-- Substitute Static Values
T["substitute_dynamic_values "] = function()
	local template = "Task: %{task}, Time: %t Prompt: %^{open_a_prompt}"
	local result = parser.substitute_dynamic_values(template, {
		["%t"] = function()
			return "03:03"
		end,
		["%{task}"] = "Write tests",
		["%^{.-}"] = function()
			return "open_a_prompt"
		end,
	}, capture_template_substitor)

	local actual_template = "Task: Write tests, Time: 03:03 Prompt: open_a_prompt"

	MiniTest.expect.equality(result, actual_template)
end

-- Marker Stripping and Cursor Location
T["strip_marker_and_get_cursor - finds and removes %? marker"] = function()
	local input = "Line 1\nDo this %?now\nFinal"
	local cleaned, row, col = parser.strip_marker_and_get_position(input, "%?", capture_template_substitor)
	MiniTest.expect.equality(cleaned, "Line 1\nDo this now\nFinal")
	MiniTest.expect.equality(row, 1) -- zero-based
	MiniTest.expect.equality(col, 8)
end

T["strip_marker_and_get_cursor - no marker returns same string and nils"] = function()
	local input = "No markers here\nStill nothing"
	local cleaned, row, col = parser.strip_marker_and_get_position(input, "%?", capture_template_substitor)
	MiniTest.expect.equality(cleaned, input)
	MiniTest.expect.equality(row, nil)
	MiniTest.expect.equality(col, nil)
end

return T
