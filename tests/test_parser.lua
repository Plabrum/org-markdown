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
local function capture_template_escape(marker)
	return parser.escape_marker(marker, { "^", "?", "%" })
end

T["escaped_substitute - no match returns original string"] = function()
	local cp = capture_template_escape("%notfound")
	local result = ("No match here"):gsub(capture_template_escape("%notfound"), "replacement")
	MiniTest.expect.equality(result, "No match here")
end

T["escaped_substitute - single match with string replacement"] = function()
	local result = ("Hello %name, word"):gsub(capture_template_escape("%name"), "John")
	MiniTest.expect.equality(result, "Hello John, word")
end

T["escaped_substitute - check ^ is escaped correctly"] = function()
	local result = ("first %^{filler} third"):gsub(capture_template_escape("%^{filler}"), "second")
	MiniTest.expect.equality(result, "first second third")
end

T["escaped_substitute - check dynamic substitution is escaped correctly"] = function()
	local result = ("first %^{filler} third"):gsub(capture_template_escape("%^{.-}"), "second")
	MiniTest.expect.equality(result, "first second third")
end

T["escaped_substitute - check cursor_swap %? is escaped correctly"] = function()
	local result = (">%?<"):gsub(capture_template_escape("%?"), "")
	MiniTest.expect.equality(result, "><")
end

return T
