local async = require("org_markdown.async")
local queries = require("org_markdown.queries")
local picker = require("org_markdown.picker")
local utils = require("org_markdown.utils")

local M = {}

function M.open_file_picker()
	local files = queries.find_markdown_files()

	if #files == 0 then
		vim.notify("No Markdown files found", vim.log.levels.WARN)
		return
	end

	local items = vim.tbl_map(function(file)
		return { value = file, file = file }
	end, files)

	picker.pick(items, {
		prompt = "Open:",
		kind = "files",

		format_item = function(item)
			return {
				{ vim.fn.fnamemodify(item.value, ":~:."), "Directory" },
			}
		end,

		on_confirm = function(item)
			vim.cmd.edit(vim.fn.fnameescape(item.file))
		end,
	})
end

function M.read_lines(path)
	local ok, lines = pcall(vim.fn.readfile, path)
	return ok and lines or nil
end

return M
