local MiniTest = require("mini.test")
local utils = require("org_markdown.utils")
local T = MiniTest.new_set()

T["adjust_heading_levels - promotes headings correctly"] = function()
	local input = {
		"# Parent",
		"## Child",
		"Not a heading",
		"### Grandchild",
	}
	local expected = {
		"### Parent",
		"#### Child",
		"Not a heading",
		"##### Grandchild",
	}

	local result = utils.adjust_heading_levels(input, 2)
	MiniTest.expect.equality(result, expected)
end

T["adjust_heading_levels - leaves non-headings unchanged"] = function()
	local input = {
		"- list item",
		"Some text",
	}
	local expected = {
		"- list item",
		"Some text",
	}

	local result = utils.adjust_heading_levels(input, 3)
	MiniTest.expect.equality(result, expected)
end

T["find_heading_range - finds correct range and level"] = function()
	local lines = {
		"# Top",
		"## Target",
		"### Child 1",
		"### Child 2",
		"## Sibling",
	}

	local start_idx, level, end_idx = utils.find_heading_range(lines, "Target")
	MiniTest.expect.equality(start_idx, 2)
	MiniTest.expect.equality(level, 2)
	MiniTest.expect.equality(end_idx, 5) -- next ## starts at line 5
end

T["find_heading_range - returns end of file if no sibling heading"] = function()
	local lines = {
		"# Intro",
		"## Target",
		"### Child",
		"- list item",
		"Some text",
	}

	local start_idx, level, end_idx = utils.find_heading_range(lines, "Target")
	MiniTest.expect.equality(start_idx, 2)
	MiniTest.expect.equality(level, 2)
	MiniTest.expect.equality(end_idx, 6) -- end of file + 1
end

T["find_heading_range - returns nil if heading not found"] = function()
	local lines = {
		"# Something else",
		"## Unrelated",
	}

	local start_idx, level, end_idx = utils.find_heading_range(lines, "Target")
	MiniTest.expect.equality(start_idx, nil)
	MiniTest.expect.equality(level, nil)
	MiniTest.expect.equality(end_idx, nil)
end

return T
