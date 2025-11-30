local MiniTest = require("mini.test")
local frontmatter = require("org_markdown.utils.frontmatter")

local T = MiniTest.new_set()

-- YAML frontmatter tests
T["parse_frontmatter - YAML with name"] = function()
	local lines = {
		"---",
		"name: Arive Engineering",
		"---",
		"# Content",
	}
	local result = frontmatter.parse_frontmatter(lines)
	MiniTest.expect.equality(result.name, "Arive Engineering")
end

T["parse_frontmatter - YAML with name and quotes"] = function()
	local lines = {
		"---",
		'name: "My Project"',
		"---",
		"# Content",
	}
	local result = frontmatter.parse_frontmatter(lines)
	MiniTest.expect.equality(result.name, "My Project")
end

T["parse_frontmatter - YAML with name and single quotes"] = function()
	local lines = {
		"---",
		"name: 'My Project'",
		"---",
		"# Content",
	}
	local result = frontmatter.parse_frontmatter(lines)
	MiniTest.expect.equality(result.name, "My Project")
end

T["parse_frontmatter - YAML with spaces around colon"] = function()
	local lines = {
		"---",
		"name : Test Project",
		"---",
		"# Content",
	}
	local result = frontmatter.parse_frontmatter(lines)
	MiniTest.expect.equality(result.name, "Test Project")
end

-- TOML frontmatter tests
T["parse_frontmatter - TOML with name"] = function()
	local lines = {
		"+++",
		"name = Arive Engineering",
		"+++",
		"# Content",
	}
	local result = frontmatter.parse_frontmatter(lines)
	MiniTest.expect.equality(result.name, "Arive Engineering")
end

T["parse_frontmatter - TOML with name and quotes"] = function()
	local lines = {
		"+++",
		'name = "My Project"',
		"+++",
		"# Content",
	}
	local result = frontmatter.parse_frontmatter(lines)
	MiniTest.expect.equality(result.name, "My Project")
end

-- No frontmatter tests
T["parse_frontmatter - no frontmatter"] = function()
	local lines = {
		"# Just a heading",
		"Some content",
	}
	local result = frontmatter.parse_frontmatter(lines)
	MiniTest.expect.equality(result, nil)
end

T["parse_frontmatter - empty file"] = function()
	local lines = {}
	local result = frontmatter.parse_frontmatter(lines)
	MiniTest.expect.equality(result, nil)
end

T["parse_frontmatter - frontmatter without name"] = function()
	local lines = {
		"---",
		"other_field: value",
		"---",
		"# Content",
	}
	local result = frontmatter.parse_frontmatter(lines)
	MiniTest.expect.equality(result, nil)
end

T["parse_frontmatter - unclosed frontmatter"] = function()
	local lines = {
		"---",
		"name: Test",
		"# Content without closing delimiter",
	}
	local result = frontmatter.parse_frontmatter(lines)
	MiniTest.expect.equality(result, nil)
end

-- get_display_name tests
T["get_display_name - with frontmatter"] = function()
	local lines = {
		"---",
		"name: Custom Name",
		"---",
		"# Content",
	}
	local result = frontmatter.get_display_name("/path/to/file.md", lines)
	MiniTest.expect.equality(result, "Custom Name")
end

T["get_display_name - without frontmatter fallback to filename"] = function()
	local lines = {
		"# Just content",
		"No frontmatter here",
	}
	local result = frontmatter.get_display_name("/path/to/myfile.md", lines)
	MiniTest.expect.equality(result, "myfile")
end

T["get_display_name - complex path"] = function()
	local lines = {
		"# Just content",
	}
	local result = frontmatter.get_display_name("/home/user/notes/work/project.md", lines)
	MiniTest.expect.equality(result, "project")
end

return T
