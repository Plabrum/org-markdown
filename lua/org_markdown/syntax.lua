-- org_markdown/syntax.lua
-- Sets up syntax highlighting for status keywords in markdown files

local M = {}

-- Color palette mapping color names to hex values
local COLOR_PALETTE = {
	red = "#ff5f5f",
	yellow = "#f0c000",
	green = "#5fd75f",
	blue = "#5fafd7",
	orange = "#ff8700",
	purple = "#af87ff",
	gray = "#808080",
}

-- Define highlight groups dynamically based on config
local function setup_highlight_groups()
	local config = require("org_markdown.config")
	local status_colors = config.status_colors or {}

	for state, color_name in pairs(status_colors) do
		local hex_color = COLOR_PALETTE[color_name] or COLOR_PALETTE.red -- fallback to red
		local hl_group_name = "OrgStatus_" .. state
		vim.api.nvim_set_hl(0, hl_group_name, { fg = hex_color, bold = true })
	end
end

-- Namespace for our extmarks
local ns_id = vim.api.nvim_create_namespace("org_markdown_status")

-- Highlight status keywords in visible lines using extmarks
local function highlight_status_keywords(bufnr)
	-- Clear previous highlights
	vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

	-- Get all lines in buffer
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Build status patterns dynamically from config
	local config = require("org_markdown.config")
	local status_states = config.status_states

	local patterns = {}
	for _, state in ipairs(status_states) do
		local hl_group_name = "OrgStatus_" .. state
		table.insert(patterns, {
			pattern = "^(%s*#+%s+)(" .. state .. ")(%s+.*)$",
			group = hl_group_name,
		})
	end

	-- Iterate through each line
	for line_num, line in ipairs(lines) do
		for _, item in ipairs(patterns) do
			local prefix, keyword, rest = line:match(item.pattern)
			if keyword then
				local keyword_start = #prefix
				local keyword_end = keyword_start + #keyword

				-- Highlight the status keyword
				vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num - 1, keyword_start, {
					end_col = keyword_end,
					hl_group = item.group,
					priority = 200,
				})

				-- Override the rest of the line with normal text highlighting
				if rest and #rest > 0 then
					vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num - 1, keyword_end, {
						end_col = keyword_end + #rest,
						hl_group = "Normal",
						priority = 200,
					})
				end

				break -- Found a match, move to next line
			end
		end
	end
end

-- Set up syntax highlighting for a buffer
function M.setup_buffer_syntax(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- Ensure highlight groups are defined
	setup_highlight_groups()

	-- Apply initial highlighting
	highlight_status_keywords(bufnr)

	-- Re-highlight on text changes
	local group = vim.api.nvim_create_augroup("OrgMarkdownSyntax_" .. bufnr, { clear = true })
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufEnter" }, {
		group = group,
		buffer = bufnr,
		callback = function()
			highlight_status_keywords(bufnr)
		end,
	})

	-- Clean up autocmds when buffer is deleted
	vim.api.nvim_create_autocmd("BufDelete", {
		buffer = bufnr,
		callback = function()
			pcall(vim.api.nvim_del_augroup_by_name, "OrgMarkdownSyntax_" .. bufnr)
		end,
	})
end

return M
