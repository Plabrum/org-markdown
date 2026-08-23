-- The links pointing at a node, read the other way round.
--
-- A backlink is never stored: nothing is written into the node being linked to,
-- so the answer to "what points at me?" is derived by scanning the files in
-- scope for links whose target is this node's id. That is the same derivation
-- `node/index.lua` does for "where does this id live?", just keyed by the link
-- rather than by the identity.
--
-- A reference names the node the link sits in — the heading it belongs to, or
-- the file itself for a link outside every heading — because that is the node a
-- user means when they say "A links to B".
--
-- Scanning and reading stay buffer-free and go through the platform shim, so the
-- CLI can list backlinks too; only `show` touches the editor.

local compat = require("org_markdown.compat.vim")
local frontmatter = require("org_markdown.utils.frontmatter")
local heading = require("org_markdown.execution.heading")
local id = require("org_markdown.node.id")
local parser = require("org_markdown.utils.parser")
local picker = require("org_markdown.utils.picker")
local platform = require("org_markdown.platform")
local queries = require("org_markdown.utils.queries")
local tree = require("org_markdown.utils.tree")

local M = {}

--- Collect the references to `node_id` in one file's lines, tracking the
--- heading each link falls under so a reference can name its source node.
---@param file string
---@param lines string[]
---@param node_id string
---@param references table[]
local function collect_file(file, lines, node_id, references)
	local current = nil

	for line_number, line in ipairs(lines) do
		if tree.is_heading(line) then
			current = parser.parse_text(line)
		end

		for _, link in ipairs(parser.parse_links(line)) do
			if link.id == node_id then
				table.insert(references, {
					id = node_id,
					file = file,
					line = line_number,
					heading = current,
					text = current or frontmatter.get_display_name(file, lines),
					context = compat.trim(line),
				})
			end
		end
	end
end

--- Every link in scope pointing at `node_id`, in the order the files are
--- scanned and the lines are read.
---@param node_id string
---@param opts? table Passed through to `queries.find_markdown_files`
---@return table[] references `{ id, file, line, heading?, text, context }`
function M.to(node_id, opts)
	local references = {}
	if not node_id or node_id == "" then
		return references
	end

	for _, file in ipairs(queries.find_markdown_files(opts)) do
		local content = platform.fs.read_file(file)
		if content then
			local lines = compat.split(content, "\n")
			if lines[#lines] == "" then
				table.remove(lines)
			end
			collect_file(file, lines, node_id, references)
		end
	end

	return references
end

--- The backlinks of a node named by target rather than by id. A node nobody has
--- ever linked to has no id yet, and no backlinks either -- reading them never
--- mints one.
---@param target string|table `{ file, heading? }`, or a file path
---@param opts? table Passed through to `queries.find_markdown_files`
---@return table[]|nil references, string|nil err
function M.of(target, opts)
	local node_id, err = id.get(target)
	if not node_id then
		return nil, err or "this node has no id yet, so nothing links to it"
	end

	return M.to(node_id, opts)
end

--- The node a row belongs to: the heading at or above it, or the file itself
--- when the row sits above every heading.
---@param lines string[]
---@param row number 1-based line number
---@param file string
---@return table node `{ file, heading? }`
function M.node_at(lines, row, file)
	local task = heading.task_at(lines, row, file)
	return { file = file, heading = task and task.text or nil }
end

--- List what links to the node under the cursor, jumping to the chosen one.
function M.show()
	local buf = vim.api.nvim_get_current_buf()
	local file = vim.api.nvim_buf_get_name(buf)

	if file == "" then
		vim.notify("Backlinks need a file on disk", vim.log.levels.WARN)
		return
	end

	local row = vim.api.nvim_win_get_cursor(0)[1]
	local node = M.node_at(vim.api.nvim_buf_get_lines(buf, 0, -1, false), row, file)
	local name = node.heading or vim.fn.fnamemodify(file, ":t")

	local references, err = M.of(node)
	if not references then
		vim.notify("No backlinks for " .. name .. ": " .. err, vim.log.levels.WARN)
		return
	end

	if #references == 0 then
		vim.notify("Nothing links to " .. name, vim.log.levels.INFO)
		return
	end

	picker.pick(references, {
		prompt = "Backlinks to " .. name .. ":",
		kind = "generic",
		format_item = function(item)
			return {
				{ item.text, "Directory" },
				{ "  (" .. vim.fn.fnamemodify(item.file, ":~:.") .. ":" .. item.line .. ")", "Comment" },
			}
		end,
		on_confirm = function(item)
			vim.cmd.edit(vim.fn.fnameescape(item.file))
			vim.api.nvim_win_set_cursor(0, { item.line, 0 })
			vim.cmd("normal! zz")
		end,
	})
end

return M
