local utils = require("org_markdown.utils.utils")
local queries = require("org_markdown.utils.queries")
local config = require("org_markdown.config")
local picker = require("org_markdown.utils.picker")
local async = require("org_markdown.utils.async")

local M = {}

function M.get_refile_target()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local current = lines[row]
	current = current:match("^%s*(.*)")
	-- 1. Bullet match
	if current:match("^%s*[-*+] %[[ x%-]%)") or current:match("^%s*[-*+] ") then
		return {
			lines = { current },
			start_line = row,
			end_line = row + 1,
		}
	end

	-- 2. Heading match
	local heading_level, heading_text = current:match("^(#+)%s*(.*)")
	if heading_level then
		local start_line = row
		local end_line = start_line + 1
		local current_level = #heading_level

		while end_line <= #lines do
			local next_line = lines[end_line]
			local next_level = next_line:match("^(#+)")
			if next_level and #next_level <= current_level then
				break
			end
			end_line = end_line + 1
		end

		local range = {}
		for i = start_line, end_line - 1 do
			table.insert(range, lines[i])
		end

		return {
			lines = range,
			start_line = start_line,
			end_line = end_line,
		}
	end

	vim.notify("No bullet or heading detected to refile", vim.log.levels.ERROR)
	return nil
end

function M.to_file()
	-- 1. Try to resolve content under cursor first
	local selection = M.get_refile_target()
	if not selection or not selection.lines then
		vim.notify("No bullet point or heading detected to refile", vim.log.levels.ERROR)
		return
	end
	-- 2. Ask user to pick destination file
	local files = queries.find_markdown_files()

	local items = vim.tbl_map(function(file)
		return { value = file, file = file }
	end, files)

	picker.pick(items, {
		prompt = "Refile to file:",
		kind = "files",
		format_item = function(item)
			return {
				{ vim.fn.fnamemodify(item.value, ":~:."), "Directory" },
			}
		end,
		on_confirm = function(item)
			vim.api.nvim_buf_set_lines(0, selection.start_line, selection.end_line, false, {})
			utils.append_lines(item.value, selection.lines)
			vim.notify("Refiled to " .. item.value)
		end,
	})
end

return M
