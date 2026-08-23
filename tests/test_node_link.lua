local MiniTest = require("mini.test")
local helpers = require("helpers")

-- Covers linking to a node: the pickable targets are every file and heading in
-- scope, and linking to one mints its id and renders a by-ID link.

local config = require("org_markdown.config")
local id = require("org_markdown.node.id")
local link = require("org_markdown.node.link")
local parser = require("org_markdown.utils.parser")

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

-- Targets --------------------------------------------------------------------

T["targets - offers every file and every heading in scope"] = function()
	local root = with_workspace({
		["notes.md"] = { "# Project", "## TODO Write the report" },
	})

	local targets = link.targets()
	MiniTest.expect.equality(#targets, 3)
	MiniTest.expect.equality(targets[1].file, root .. "/notes.md")
	MiniTest.expect.equality(targets[1].heading, nil)
	MiniTest.expect.equality(targets[2].heading, "Project")
	MiniTest.expect.equality(targets[3].heading, "Write the report")
end

T["targets - names a file by its frontmatter name"] = function()
	with_workspace({
		["notes.md"] = { "---", "name: Project Apollo", "---", "# Notes" },
	})

	MiniTest.expect.equality(link.targets()[1].name, "Project Apollo")
end

-- Linking --------------------------------------------------------------------

T["to_target - links to a heading, minting its id"] = function()
	local root = with_workspace({
		["notes.md"] = { "## TODO Write the report" },
	})
	local target = { file = root .. "/notes.md", heading = "Write the report" }

	local rendered = link.to_target(target)
	local parsed = parser.parse_link(rendered)
	MiniTest.expect.equality(parsed.text, "Write the report")
	MiniTest.expect.equality(parsed.id, id.get(target))
end

T["to_target - links to a file, minting its id"] = function()
	local root = with_workspace({
		["notes.md"] = { "---", "name: Project Apollo", "---", "# Notes" },
	})
	local target = link.targets()[1]

	local parsed = parser.parse_link(link.to_target(target))
	MiniTest.expect.equality(parsed.text, "Project Apollo")
	MiniTest.expect.equality(parsed.id, id.get(target.file))
end

T["to_target - falls back to the filename when a file has no name"] = function()
	local root = with_workspace({ ["notes.md"] = { "# Notes" } })

	local parsed = parser.parse_link(link.to_target({ file = root .. "/notes.md" }))
	MiniTest.expect.equality(parsed.text, "notes.md")
end

T["to_target - linking twice reuses the id already minted"] = function()
	local root = with_workspace({
		["notes.md"] = { "## TODO Write the report" },
	})
	local target = { file = root .. "/notes.md", heading = "Write the report" }

	MiniTest.expect.equality(link.to_target(target), link.to_target(target))
end

T["to_target - reports a target that cannot be identified"] = function()
	local root = with_workspace({ ["notes.md"] = { "# Notes" } })

	local rendered, err = link.to_target({ file = root .. "/notes.md", heading = "Nope" })
	MiniTest.expect.equality(rendered, nil)
	MiniTest.expect.equality(err:match("no heading matching") ~= nil, true)
end

return T
