local async = require("org_markdown.utils.async")
local queries = require("org_markdown.utils.queries")
local picker = require("org_markdown.utils.picker")
local utils = require("org_markdown.utils.utils")
local frontmatter = require("org_markdown.utils.frontmatter")

local M = {}

function M.open_file_picker()
	local files = queries.find_markdown_files()

	if #files == 0 then
		vim.notify("No Markdown files found", vim.log.levels.WARN)
		return
	end

	local items = vim.tbl_map(function(file)
		local display_name = frontmatter.get_display_name(file)
		return { value = file, file = file, name = display_name }
	end, files)

	picker.pick(items, {
		prompt = "Open:",
		kind = "files",

		format_item = function(item)
			-- Show display name (from frontmatter or filename) with path as secondary info
			local path_hint = vim.fn.fnamemodify(item.value, ":~:.:h")
			if path_hint == "." then
				return { { item.name, "Directory" } }
			else
				return {
					{ item.name, "Directory" },
					{ " (" .. path_hint .. ")", "Comment" },
				}
			end
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
