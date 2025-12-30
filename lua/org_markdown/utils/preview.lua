-- Preview window utilities for showing heading details
local utils = require("org_markdown.utils.utils")
local document = require("org_markdown.utils.document")

local M = {}

--- Reconstruct a heading line from parsed node data
--- @param node Node Heading node with parsed data
--- @return string Reconstructed heading line
local function reconstruct_heading(node)
	local parts = {}
	local p = node.parsed

	table.insert(parts, string.rep("#", node.level))

	if p.state then
		table.insert(parts, p.state)
	end

	if p.priority then
		table.insert(parts, string.format("[#%s]", p.priority))
	end

	if p.text and p.text ~= "" then
		table.insert(parts, p.text)
	end

	if p.tracked then
		local date_str = "<" .. p.tracked
		if p.start_time then
			date_str = date_str .. " " .. p.start_time
			if p.end_time then
				date_str = date_str .. "-" .. p.end_time
			end
		end
		date_str = date_str .. ">"
		table.insert(parts, date_str)
	end

	if p.untracked then
		table.insert(parts, "[" .. p.untracked .. "]")
	end

	if p.tags and #p.tags > 0 then
		table.insert(parts, ":" .. table.concat(p.tags, ":") .. ":")
	end

	return table.concat(parts, " ")
end

--- Show full entry details in a floating window
--- @param file string File path
--- @param line number Line number
function M.show_heading_preview(file, line)
	if not file or not line then
		return
	end

	-- Read the file and parse it
	local lines = utils.read_lines(file)
	local root = document.parse(lines)

	-- Find the node at the item's line
	local node = document.find_node_at_line(root, line)
	if not node or node.type ~= "heading" then
		vim.notify("Could not find heading in source file", vim.log.levels.WARN)
		return
	end

	-- Serialize just this node (heading + content, without children)
	local preview_lines = {}

	-- Add the heading (reconstruct if needed)
	local heading_line = node.dirty and node.parsed and reconstruct_heading(node) or node.raw_heading
	table.insert(preview_lines, heading_line)

	-- Add content lines
	for _, content_line in ipairs(node.content_lines) do
		table.insert(preview_lines, content_line)
	end

	-- Add properties (sorted)
	local keys = {}
	for key in pairs(node.properties) do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		table.insert(preview_lines, string.format("**%s:** %s", key, node.properties[key]))
	end

	-- Create floating window
	local preview_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, preview_lines)
	vim.bo[preview_buf].filetype = "markdown"
	vim.bo[preview_buf].modifiable = false

	-- Calculate window size
	local width = math.min(80, vim.o.columns - 4)
	local height = math.min(#preview_lines + 2, math.floor(vim.o.lines * 0.8))

	local opts = {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
		title = " Preview ",
		title_pos = "center",
	}

	local preview_win = vim.api.nvim_open_win(preview_buf, true, opts)
	vim.wo[preview_win].wrap = true
	vim.wo[preview_win].linebreak = true
	vim.wo[preview_win].foldenable = false

	-- Close on q or Esc
	local function close_preview()
		vim.api.nvim_win_close(preview_win, true)
	end

	vim.keymap.set("n", "q", close_preview, { buffer = preview_buf, silent = true })
	vim.keymap.set("n", "<Esc>", close_preview, { buffer = preview_buf, silent = true })
end

return M
