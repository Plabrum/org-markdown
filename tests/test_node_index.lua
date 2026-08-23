local MiniTest = require("mini.test")
local helpers = require("helpers")

-- Covers the id-to-location index: scanning refile_paths turns minted ids into
-- current locations, so a lookup finds a file node and a heading node wherever
-- they now live.

local config = require("org_markdown.config")
local id = require("org_markdown.node.id")
local index = require("org_markdown.node.index")

local workspace = nil
local original_paths = nil

--- Scan a workspace of `{ [relative path] = lines }` as the only refile path.
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

T["lookup - finds a file node by its frontmatter id"] = function()
	local root = with_workspace({
		["notes.md"] = { "---", "id: 11111111-2222-4333-8444-555555555555", "---", "# Notes" },
	})

	local location = index.lookup("11111111-2222-4333-8444-555555555555")
	MiniTest.expect.equality(location.file, root .. "/notes.md")
	MiniTest.expect.equality(location.heading, nil)
end

T["lookup - finds a heading node by its ID property"] = function()
	local root = with_workspace({
		["tasks.md"] = {
			"# Project",
			"## TODO Write the report",
			"ID: [aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee]",
			"Body text",
		},
	})

	local location = index.lookup("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
	MiniTest.expect.equality(location.file, root .. "/tasks.md")
	MiniTest.expect.equality(location.heading, "Write the report")
	MiniTest.expect.equality(location.line, 2)
end

T["lookup - resolves nodes across files from one scan"] = function()
	local root = with_workspace({
		["one.md"] = { "---", "id: 11111111-1111-4111-8111-111111111111", "---", "# One" },
		["nested/two.md"] = {
			"## TODO Nested task",
			"ID: [22222222-2222-4222-8222-222222222222]",
		},
	})

	local built = index.build()
	MiniTest.expect.equality(index.lookup("11111111-1111-4111-8111-111111111111", built).file, root .. "/one.md")

	local nested = index.lookup("22222222-2222-4222-8222-222222222222", built)
	MiniTest.expect.equality(nested.file, root .. "/nested/two.md")
	MiniTest.expect.equality(nested.heading, "Nested task")
end

T["lookup - finds ids that were minted lazily"] = function()
	local root = with_workspace({
		["refile.md"] = { "# Inbox", "## TODO Buy milk" },
	})

	local file_id = id.ensure(root .. "/refile.md")
	local heading_id = id.ensure({ file = root .. "/refile.md", heading = "Buy milk" })

	local built = index.build()
	MiniTest.expect.equality(index.lookup(file_id, built).file, root .. "/refile.md")
	MiniTest.expect.equality(index.lookup(heading_id, built).heading, "Buy milk")
end

T["lookup - follows a node that moved to another file"] = function()
	local root = with_workspace({
		["inbox.md"] = { "## TODO Buy milk", "ID: [33333333-3333-4333-8333-333333333333]" },
	})

	MiniTest.expect.equality(index.lookup("33333333-3333-4333-8333-333333333333").file, root .. "/inbox.md")

	-- Refile the heading into another file, and rebuild.
	local file = assert(io.open(root .. "/inbox.md", "w"))
	file:write("# Inbox\n")
	file:close()
	file = assert(io.open(root .. "/errands.md", "w"))
	file:write("## TODO Buy milk\nID: [33333333-3333-4333-8333-333333333333]\n")
	file:close()

	MiniTest.expect.equality(index.lookup("33333333-3333-4333-8333-333333333333").file, root .. "/errands.md")
end

T["lookup - indexes nested headings"] = function()
	local root = with_workspace({
		["deep.md"] = {
			"# Project",
			"## Area",
			"### TODO Deep task",
			"ID: [44444444-4444-4444-8444-444444444444]",
		},
	})

	local location = index.lookup("44444444-4444-4444-8444-444444444444")
	MiniTest.expect.equality(location.file, root .. "/deep.md")
	MiniTest.expect.equality(location.heading, "Deep task")
	MiniTest.expect.equality(location.line, 3)
end

T["lookup - returns nil for an unknown or empty id"] = function()
	with_workspace({ ["notes.md"] = { "# Notes" } })

	MiniTest.expect.equality(index.lookup("99999999-9999-4999-8999-999999999999"), nil)
	MiniTest.expect.equality(index.lookup(""), nil)
	MiniTest.expect.equality(index.lookup(nil), nil)
end

return T
