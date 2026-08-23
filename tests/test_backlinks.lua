local MiniTest = require("mini.test")
local helpers = require("helpers")

-- Covers backlinks: linking A to B and asking B what points at it lists A,
-- named by the node the link sits in, and derived by scanning rather than by
-- anything stored on B.

local backlinks = require("org_markdown.node.backlinks")
local config = require("org_markdown.config")
local id = require("org_markdown.node.id")
local link = require("org_markdown.node.link")

local workspace = nil
local original_paths = nil

--- Offer a workspace of `{ [relative path] = lines }` as the only refile path.
local function with_workspace(files)
	workspace = helpers.create_temp_workspace(files)
	original_paths = config.refile_paths
	config.refile_paths = { workspace }
	return workspace
end

--- Put a link to `target` on the given line of a file, as inserting one does.
local function link_from(file, line_number, target)
	local lines = vim.fn.readfile(file)
	lines[line_number] = lines[line_number] .. " " .. link.to_target(target)
	vim.fn.writefile(lines, file)
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

-- Listing --------------------------------------------------------------------

T["of - lists the heading that links to a node"] = function()
	local root = with_workspace({
		["a.md"] = { "# A", "## Planning", "see also:" },
		["b.md"] = { "# B", "## Write the report" },
	})
	local target = { file = root .. "/b.md", heading = "Write the report" }
	link_from(root .. "/a.md", 3, target)

	local references = backlinks.of(target)
	MiniTest.expect.equality(#references, 1)
	MiniTest.expect.equality(references[1].file, root .. "/a.md")
	MiniTest.expect.equality(references[1].heading, "Planning")
	MiniTest.expect.equality(references[1].text, "Planning")
	MiniTest.expect.equality(references[1].line, 3)
	MiniTest.expect.equality(references[1].id, id.get(target))
end

T["of - names the file when the link sits above every heading"] = function()
	local root = with_workspace({
		["a.md"] = { "---", "name: Project Apollo", "---", "intro" },
		["b.md"] = { "# B" },
	})
	local target = { file = root .. "/b.md", heading = "B" }
	link_from(root .. "/a.md", 4, target)

	local references = backlinks.of(target)
	MiniTest.expect.equality(references[1].heading, nil)
	MiniTest.expect.equality(references[1].text, "Project Apollo")
end

T["of - lists a link to a file node"] = function()
	local root = with_workspace({
		["a.md"] = { "# A", "see also:" },
		["b.md"] = { "# B" },
	})
	link_from(root .. "/a.md", 2, { file = root .. "/b.md" })

	local references = backlinks.of(root .. "/b.md")
	MiniTest.expect.equality(#references, 1)
	MiniTest.expect.equality(references[1].heading, "A")
end

T["of - lists every link pointing at the node"] = function()
	local root = with_workspace({
		["a.md"] = { "# A", "one:" },
		["c.md"] = { "# C", "two:" },
		["b.md"] = { "# B" },
	})
	local target = { file = root .. "/b.md", heading = "B" }
	link_from(root .. "/a.md", 2, target)
	link_from(root .. "/c.md", 2, target)

	local sources = {}
	for _, reference in ipairs(backlinks.of(target)) do
		table.insert(sources, reference.heading)
	end
	table.sort(sources)
	MiniTest.expect.equality(sources, { "A", "C" })
end

T["of - ignores links pointing at another node"] = function()
	local root = with_workspace({
		["a.md"] = { "# A", "elsewhere:" },
		["b.md"] = { "# B", "## Other" },
	})
	link_from(root .. "/a.md", 2, { file = root .. "/b.md", heading = "Other" })
	-- B is identified too, so the empty answer is about the link's target and
	-- not about B having no id.
	id.ensure({ file = root .. "/b.md", heading = "B" })

	MiniTest.expect.equality(#backlinks.of({ file = root .. "/b.md", heading = "B" }), 0)
end

T["of - reports a node nobody has linked to, without minting an id"] = function()
	local root = with_workspace({ ["b.md"] = { "# B" } })
	local target = { file = root .. "/b.md", heading = "B" }

	local references, err = backlinks.of(target)
	MiniTest.expect.equality(references, nil)
	MiniTest.expect.equality(err:match("no id yet") ~= nil, true)
	MiniTest.expect.equality(id.get(target), nil)
end

T["of - still lists the source after the target heading is renamed"] = function()
	local root = with_workspace({
		["a.md"] = { "# A", "see also:" },
		["b.md"] = { "# B", "## Write the report" },
	})
	link_from(root .. "/a.md", 2, { file = root .. "/b.md", heading = "Write the report" })

	local lines = vim.fn.readfile(root .. "/b.md")
	lines[2] = "## Draft the report"
	vim.fn.writefile(lines, root .. "/b.md")

	local references = backlinks.of({ file = root .. "/b.md", heading = "Draft the report" })
	MiniTest.expect.equality(#references, 1)
	MiniTest.expect.equality(references[1].heading, "A")
end

T["to - answers nothing for an id no file carries"] = function()
	with_workspace({ ["a.md"] = { "# A" } })

	MiniTest.expect.equality(#backlinks.to("11111111-1111-4111-8111-111111111111"), 0)
end

-- The node asked about ---------------------------------------------------

T["node_at - takes the heading the row belongs to"] = function()
	local lines = { "# A", "## Planning", "body text" }

	MiniTest.expect.equality(backlinks.node_at(lines, 3, "a.md").heading, "Planning")
	MiniTest.expect.equality(backlinks.node_at(lines, 1, "a.md").heading, "A")
end

T["node_at - falls back to the file above every heading"] = function()
	local node = backlinks.node_at({ "---", "name: A", "---", "# A" }, 2, "a.md")

	MiniTest.expect.equality(node.file, "a.md")
	MiniTest.expect.equality(node.heading, nil)
end

return T
