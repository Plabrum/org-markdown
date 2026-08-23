local MiniTest = require("mini.test")

-- Covers lazily minted node identity: a file keeps its id in frontmatter, a
-- heading keeps an ID property, and asking twice mints nothing the second time.

local id = require("org_markdown.node.id")

local UUID_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

local function write_file(lines)
	local path = vim.fn.tempname() .. ".md"
	local file = assert(io.open(path, "w"))
	file:write(table.concat(lines, "\n") .. "\n")
	file:close()
	return path
end

local function read_file(path)
	local file = assert(io.open(path, "r"))
	local content = file:read("*a")
	file:close()
	return content
end

local T = MiniTest.new_set()

-- File nodes ----------------------------------------------------------------

T["ensure - mints an id into a file without frontmatter"] = function()
	local path = write_file({ "# Notes", "", "Some text" })

	local minted = id.ensure(path)
	MiniTest.expect.equality(minted:match(UUID_PATTERN) ~= nil, true)
	MiniTest.expect.equality(read_file(path), table.concat({
		"---",
		"id: " .. minted,
		"---",
		"# Notes",
		"",
		"Some text",
	}, "\n") .. "\n")
end

T["ensure - adds an id to existing frontmatter, keeping other fields"] = function()
	local path = write_file({ "---", "name: Project", "---", "# Notes" })

	local minted = id.ensure(path)
	MiniTest.expect.equality(read_file(path), table.concat({
		"---",
		"name: Project",
		"id: " .. minted,
		"---",
		"# Notes",
	}, "\n") .. "\n")
end

T["ensure - a second call on a file returns the same id and writes nothing"] = function()
	local path = write_file({ "# Notes" })

	local minted = id.ensure(path)
	local after_mint = read_file(path)

	MiniTest.expect.equality(id.ensure(path), minted)
	MiniTest.expect.equality(read_file(path), after_mint)
end

T["ensure - reads an id that was already in frontmatter"] = function()
	local path = write_file({ "---", "id: 11111111-2222-4333-8444-555555555555", "---", "# Notes" })
	local before = read_file(path)

	MiniTest.expect.equality(id.ensure(path), "11111111-2222-4333-8444-555555555555")
	MiniTest.expect.equality(read_file(path), before)
end

-- Heading nodes -------------------------------------------------------------

T["ensure - mints an ID property under a heading"] = function()
	local path = write_file({ "# Notes", "## TODO Write the report", "Body text" })

	local minted = id.ensure({ file = path, heading = "Write the report" })
	MiniTest.expect.equality(minted:match(UUID_PATTERN) ~= nil, true)
	MiniTest.expect.equality(read_file(path), table.concat({
		"# Notes",
		"## TODO Write the report",
		"ID: [" .. minted .. "]",
		"Body text",
	}, "\n") .. "\n")
end

T["ensure - a second call on a heading returns the same id and writes nothing"] = function()
	local path = write_file({ "## TODO Write the report", "Body text" })
	local target = { file = path, heading = "Write the report" }

	local minted = id.ensure(target)
	local after_mint = read_file(path)

	MiniTest.expect.equality(id.ensure(target), minted)
	MiniTest.expect.equality(read_file(path), after_mint)
end

T["ensure - identifies a heading without touching its file's id"] = function()
	local path = write_file({ "# Notes", "## TODO Write the report" })

	local heading_id = id.ensure({ file = path, heading = "Write the report" })
	MiniTest.expect.no_equality(heading_id, nil)
	MiniTest.expect.equality(id.get(path), nil)
end

T["ensure - accepts an agenda-style item with title"] = function()
	local path = write_file({ "## TODO Write the report" })

	local minted = id.ensure({ file = path, title = "Write the report" })
	MiniTest.expect.equality(id.get({ file = path, heading = "Write the report" }), minted)
end

T["ensure - reports an unknown heading"] = function()
	local path = write_file({ "## TODO Write the report" })

	local minted, err = id.ensure({ file = path, heading = "Nope" })
	MiniTest.expect.equality(minted, nil)
	MiniTest.expect.equality(err:match("no heading matching") ~= nil, true)
end

-- Reading -------------------------------------------------------------------

T["get - returns nil for an unidentified node and writes nothing"] = function()
	local path = write_file({ "# Notes", "## TODO Write the report" })
	local before = read_file(path)

	MiniTest.expect.equality(id.get(path), nil)
	MiniTest.expect.equality(id.get({ file = path, heading = "Write the report" }), nil)
	MiniTest.expect.equality(read_file(path), before)
end

T["get - reports a missing file"] = function()
	local found, err = id.get("/no/such/org-markdown-file.md")
	MiniTest.expect.equality(found, nil)
	MiniTest.expect.equality(err:match("could not read") ~= nil, true)
end

T["get - reports a target with no file"] = function()
	local found, err = id.get({ heading = "Write the report" })
	MiniTest.expect.equality(found, nil)
	MiniTest.expect.equality(err, "target has no file")
end

return T
