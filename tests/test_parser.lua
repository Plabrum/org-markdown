local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local parser = require("org_markdown.utils.parser")

-- Heading Parsing
T["parse_heading - TODO with priority and tags"] = function()
	local line = "# TODO [#A] Write tests :work:urgent:"
	local result = parser.parse_headline(line)
	local tags = parser.extract_tags(line)
	MiniTest.expect.equality(result.state, "TODO")
	MiniTest.expect.equality(result.priority, "A")
	MiniTest.expect.equality(result.text, "Write tests")
	MiniTest.expect.equality(tags[1], "work")
	MiniTest.expect.equality(tags[2], "urgent")
end

T["parse_heading - IN_PROGRESS without priority"] = function()
	local line = "# IN_PROGRESS Refactor parser :dev:"
	local result = parser.parse_headline(line)
	local tags = parser.extract_tags(line)
	MiniTest.expect.equality(result.state, "IN_PROGRESS")
	MiniTest.expect.equality(result.priority, nil)
	MiniTest.expect.equality(result.text, "Refactor parser")
	MiniTest.expect.equality(tags[1], "dev")
end

T["parse_heading - ignored DONE heading"] = function()
	local line = "# DONE [#B] Completed work :done:"
	local result = parser.parse_headline(line)
	MiniTest.expect.equality(result.state, "DONE") -- parser no longer filters these
	MiniTest.expect.equality(result.priority, "B")
	MiniTest.expect.equality(result.text, "Completed work")
end

-- Date Extraction
T["extract_date - tracked and untracked dates"] = function()
	local line = "- [ ] TODO task <2025-06-22> [2025-06-23]"
	local tracked, untracked = parser.extract_date(line)
	MiniTest.expect.equality(tracked, "2025-06-22")
	MiniTest.expect.equality(untracked, "2025-06-23")
end

T["extract_date - no date returns nil"] = function()
	local line = "No date here"
	local tracked, untracked = parser.extract_date(line)
	MiniTest.expect.equality(tracked, nil)
	MiniTest.expect.equality(untracked, nil)
end

T["extract_date - date with day name and time"] = function()
	local line = "# Event <2025-12-01 Mon 17:30>"
	local tracked, untracked = parser.extract_date(line)
	MiniTest.expect.equality(tracked, "2025-12-01")
	MiniTest.expect.equality(untracked, nil)
end

T["extract_date - date with day name and time range"] = function()
	local line = "# Event <2025-12-01 Mon 17:30-18:00>"
	local tracked, untracked = parser.extract_date(line)
	MiniTest.expect.equality(tracked, "2025-12-01")
	MiniTest.expect.equality(untracked, nil)
end

T["extract_date - multi-day date range"] = function()
	local line = "# Event <2025-12-01 Mon 17:30>--<2025-12-02 Tue 01:10>"
	local tracked, untracked = parser.extract_date(line)
	MiniTest.expect.equality(tracked, "2025-12-01")
	MiniTest.expect.equality(untracked, nil)
end
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
