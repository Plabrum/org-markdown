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

function M.open_heading_picker()
	-- Get all headings using shared utility
	local all_headings = utils.get_all_headings()

	if #all_headings == 0 then
		vim.notify("No headings found in any markdown files", vim.log.levels.WARN)
		return
	end

	-- Show single picker with all headings
	picker.pick(all_headings, {
		prompt = "Go to heading:",
		kind = "generic",
		format_item = function(item)
			-- Show as: "  Heading Name  (filename)"
			return {
				{ item.display, "Directory" },
				{ "  (" .. item.filename .. ")", "Comment" },
			}
		end,
		on_confirm = function(item)
			-- Open the file
			vim.cmd.edit(vim.fn.fnameescape(item.filepath))
			-- Jump to the heading line
			vim.api.nvim_win_set_cursor(0, { item.line_num, 0 })
			-- Center the line in the window
			vim.cmd("normal! zz")
		end,
	})
end

return M
