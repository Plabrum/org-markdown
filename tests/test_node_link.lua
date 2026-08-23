local MiniTest = require("mini.test")
local helpers = require("helpers")

-- Covers linking to a node: the pickable targets are every file and heading in
-- scope, linking to one mints its id and renders a by-ID link, and following a
-- link resolves that id to wherever the node lives now.

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

-- Following ------------------------------------------------------------------

T["link_at - takes the link the cursor sits on"] = function()
	local line = "see [One](id:" .. string.rep("a", 8) .. "-aaaa-4aaa-8aaa-" .. string.rep("a", 12) .. ")"
	line = line .. " and [Two](id:" .. string.rep("b", 8) .. "-bbbb-4bbb-8bbb-" .. string.rep("b", 12) .. ")"

	local second = parser.parse_links(line)[2]
	MiniTest.expect.equality(link.link_at(line, second.from).text, "Two")
	MiniTest.expect.equality(link.link_at(line, 5).text, "One")
end

T["link_at - falls back to the only link on the line"] = function()
	local root = with_workspace({ ["notes.md"] = { "## TODO Write the report" } })
	local line = "trailing prose " .. link.to_target({ file = root .. "/notes.md", heading = "Write the report" })

	MiniTest.expect.equality(link.link_at(line, 1).text, "Write the report")
end

T["link_at - reports no link on a plain line"] = function()
	MiniTest.expect.equality(link.link_at("nothing to follow here", 1), nil)
end

T["resolve - finds the heading a link points at"] = function()
	local root = with_workspace({ ["notes.md"] = { "# Project", "## TODO Write the report" } })
	local target = { file = root .. "/notes.md", heading = "Write the report" }
	link.to_target(target)

	local location = link.resolve(id.get(target))
	MiniTest.expect.equality(location.file, root .. "/notes.md")
	MiniTest.expect.equality(location.heading, "Write the report")
end

T["resolve - reports an id no file in scope carries"] = function()
	with_workspace({ ["notes.md"] = { "# Notes" } })

	local location, err = link.resolve("11111111-1111-4111-8111-111111111111")
	MiniTest.expect.equality(location, nil)
	MiniTest.expect.equality(err:match("No node with id") ~= nil, true)
end

T["resolve - still lands after the target file is renamed"] = function()
	local root = with_workspace({ ["notes.md"] = { "# Notes" } })
	local node_id = parser.parse_link(link.to_target({ file = root .. "/notes.md" })).id

	os.rename(root .. "/notes.md", root .. "/renamed.md")

	MiniTest.expect.equality(link.resolve(node_id).file, root .. "/renamed.md")
end

T["resolve - still lands after the target heading is refiled elsewhere"] = function()
	local root = with_workspace({
		["notes.md"] = { "# Project", "## TODO Write the report" },
		["other.md"] = { "# Other" },
	})
	local node_id = parser.parse_link(link.to_target({
		file = root .. "/notes.md",
		heading = "Write the report",
	})).id

	-- Refile the heading block: everything from its heading line, ID property
	-- included, moves into the other file.
	local lines = vim.fn.readfile(root .. "/notes.md")
	local start = nil
	for index, line in ipairs(lines) do
		if line:match("^## TODO Write the report") then
			start = index
			break
		end
	end
	local moved = vim.list_slice(lines, start, #lines)
	vim.fn.writefile(vim.list_slice(lines, 1, start - 1), root .. "/notes.md")
	vim.fn.writefile(vim.list_extend(vim.fn.readfile(root .. "/other.md"), moved), root .. "/other.md")

	local location = link.resolve(node_id)
	MiniTest.expect.equality(location.file, root .. "/other.md")
	MiniTest.expect.equality(location.heading, "Write the report")
end

return T
