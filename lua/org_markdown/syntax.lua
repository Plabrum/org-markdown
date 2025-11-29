-- org_markdown/syntax.lua
-- Sets up syntax highlighting for status keywords in markdown files

local M = {}

-- Define highlight groups (same as used in agenda.lua)
local function setup_highlight_groups()
	vim.api.nvim_set_hl(0, "OrgTodo", { fg = "#ff5f5f", bold = true })
	vim.api.nvim_set_hl(0, "OrgInProgress", { fg = "#f0c000", bold = true })
	vim.api.nvim_set_hl(0, "OrgDone", { fg = "#5fd75f", bold = true })
end

-- Namespace for our extmarks
local ns_id = vim.api.nvim_create_namespace("org_markdown_status")

-- Highlight status keywords in visible lines using extmarks
local function highlight_status_keywords(bufnr)
	-- Clear previous highlights
	vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

	-- Get all lines in buffer
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Status patterns with their highlight groups
	local patterns = {
		{ pattern = "^(%s*#+%s+)(TODO)(%s+.*)$", group = "OrgTodo" },
		{ pattern = "^(%s*#+%s+)(IN_PROGRESS)(%s+.*)$", group = "OrgInProgress" },
		{ pattern = "^(%s*#+%s+)(WAITING)(%s+.*)$", group = "OrgTodo" },
		{ pattern = "^(%s*#+%s+)(DONE)(%s+.*)$", group = "OrgDone" },
		{ pattern = "^(%s*#+%s+)(CANCELLED)(%s+.*)$", group = "OrgDone" },
		{ pattern = "^(%s*#+%s+)(BLOCKED)(%s+.*)$", group = "OrgTodo" },
	}

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
