-- Creating a link to a node, and following one.
--
-- The user picks a target — a file or a heading — and gets a durable link at
-- point. Minting is part of picking: `node/id.lua` gives the target an id the
-- first time anyone links to it, so the link that lands in the buffer names its
-- target by UUID and survives the target being renamed or refiled.
--
-- Following is the same trip in reverse: the id under the cursor is resolved
-- through `node/index.lua` to wherever that node lives now, which is why a link
-- still lands after its target moved.
--
-- Picking and the buffer edit are the editor's job, but `to_target` — mint,
-- then serialize — and `resolve` are not, so the CLI can build and follow the
-- same links.

local frontmatter = require("org_markdown.utils.frontmatter")
local id = require("org_markdown.node.id")
local node_index = require("org_markdown.node.index")
local parser = require("org_markdown.utils.parser")
local picker = require("org_markdown.utils.picker")
local platform = require("org_markdown.platform")
local queries = require("org_markdown.utils.queries")
local utils = require("org_markdown.utils.utils")

local M = {}

--- Every node that can be linked to: each markdown file in scope, followed by
--- each heading inside it.
--- @param opts? table Passed through to `queries.find_markdown_files`
--- @return table Items of `{ file, heading?, name, display, text }`
function M.targets(opts)
	local files = queries.find_markdown_files(opts)
	local targets = {}

	for _, file in ipairs(files) do
		local name = frontmatter.get_display_name(file)
		table.insert(targets, { file = file, name = name, display = name, text = name })
	end

	for _, heading in ipairs(utils.get_all_headings({ files = files })) do
		table.insert(targets, {
			file = heading.filepath,
			heading = heading.heading_text,
			name = heading.filename,
			display = heading.display,
			text = heading.text,
		})
	end

	return targets
end

--- The markdown link pointing at a target, minting the target's id when it has
--- none. The display text is the heading text, or the file's display name for a
--- file node.
--- @param target table `{ file, heading? }` as `M.targets` yields
--- @return string|nil link, string|nil err
function M.to_target(target)
	-- Pass the node on its own: a picker item also carries display fields that
	-- `id.ensure` would mistake for heading text.
	local node_id, err = id.ensure({ file = target.file, heading = target.heading })
	if not node_id then
		return nil, err
	end

	local text = target.heading or target.name or platform.path.basename(target.file)
	return parser.serialize_link({ id = node_id, text = text })
end

--- The link the cursor sits on, or the first link on the line when the cursor
--- sits outside every link — following from anywhere on a line with one link is
--- what a reader expects.
--- @param line string
--- @param col? number 1-based byte column of the cursor
--- @return table|nil link as `parser.parse_link` returns it
function M.link_at(line, col)
	local links = parser.parse_links(line)

	for _, link in ipairs(links) do
		if col and col >= link.from and col <= link.to then
			return link
		end
	end

	return links[1]
end

--- Where the node a link points at lives now. Pass an `index` to follow many
--- links without rescanning.
--- @param node_id string
--- @param index? table<string, table>
--- @return table|nil location, string|nil err
function M.resolve(node_id, index)
	local location = node_index.lookup(node_id, index)
	if not location then
		return nil, "No node with id " .. tostring(node_id) .. " in scope"
	end

	return location
end

--- Follow the link under the cursor to wherever its target lives now.
function M.follow()
	local _, col = unpack(vim.api.nvim_win_get_cursor(0))
	local link = M.link_at(vim.api.nvim_get_current_line(), col + 1)

	if not link then
		vim.notify("No link under the cursor", vim.log.levels.WARN)
		return
	end

	local location, err = M.resolve(link.id)
	if not location then
		vim.notify("Could not follow " .. link.text .. ": " .. err, vim.log.levels.WARN)
		return
	end

	vim.cmd.edit(vim.fn.fnameescape(location.file))
	if location.line then
		vim.api.nvim_win_set_cursor(0, { location.line, 0 })
		vim.cmd("normal! zz")
	end
end

--- Pick a node and insert a link to it at the cursor.
function M.insert()
	local targets = M.targets()

	if #targets == 0 then
		vim.notify("No markdown files found to link to", vim.log.levels.WARN)
		return
	end

	picker.pick(targets, {
		prompt = "Link to:",
		kind = "generic",
		format_item = function(item)
			-- Headings are placed by the file they live in, files by their path
			local context = item.heading and item.name or vim.fn.fnamemodify(item.file, ":~:.")
			return {
				{ item.display, "Directory" },
				{ "  (" .. context .. ")", "Comment" },
			}
		end,
		on_confirm = function(item)
			local link, err = M.to_target(item)
			if not link then
				vim.notify("Could not link to " .. item.display .. ": " .. err, vim.log.levels.ERROR)
				return
			end

			vim.api.nvim_put({ link }, "c", true, true)
		end,
	})
end

return M
