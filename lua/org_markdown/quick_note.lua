local utils = require("org_markdown.utils.utils")
local config = require("org_markdown.config")
local M = {}

function M.git_branch_note(opts)
	local cwd = (opts and opts.cwd) or vim.uv.cwd() or ""
	local branch_output = vim.fn.systemlist({ "git", "-C", cwd, "branch", "--show-current" })
	local branch = branch_output[1] or "no-branch"
	branch = branch:gsub("/", "__")

	local folder_name = vim.fn.fnamemodify(cwd, ":t") -- ":t" gets the tail of the path
	if folder_name == "" then
		folder_name = "unknown"
	end

	return folder_name .. "__" .. branch .. ".md"
end

---@return string
function M.daily_note(_)
	return tostring(os.date("journal_%Y-%m-%d.md"))
end

local function is_buffer_empty(lines)
	for _, line in ipairs(lines) do
		if line:match("%S") then
			return false
		end
	end
	return true
end

function M.open_quick_note(recipe_key)
	local recipe = M.recipes[recipe_key]
	if not recipe then
		vim.notify("Quicknote recipe not found: " .. recipe.title, vim.log.levels.ERROR)
		return
	end

	local quick_notes_dir = vim.fn.expand(config.quick_note_file) -- expand in case it contains '~'

	-- Expect handler to return just a filename or relative pathSS
	local note_filename = recipe.handler()
	local filepath = vim.fn.fnamemodify(quick_notes_dir .. note_filename, ":p")
	local dir = vim.fn.fnamemodify(filepath, ":h")

	local file_exists = vim.loop.fs_stat(filepath) ~= nil

	local content = ""
	if file_exists then
		content = table.concat(vim.fn.readfile(filepath), "\n")
	end
	local buf, win = utils.open_window({
		method = config.window_method,
		title = "Quick Note: " .. recipe.title,
		filetype = "markdown",
		footer = "Press q or <Esc> to save",
		on_close = function(buf_num)
			if vim.api.nvim_buf_is_valid(buf_num) then
				local lines = vim.api.nvim_buf_get_lines(buf_num, 0, -1, false)
				if not is_buffer_empty(lines) then
					vim.fn.mkdir(dir, "p")
					vim.fn.writefile(lines, filepath)
				end
			end
		end,
	})

	local lines = content ~= "" and vim.split(content, "\n") or { "" }
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	utils.set_cursor(win, 0, 0, "n")
end

M.recipes = {
	git_branch_note = {
		key = "z",
		title = "Git Branch Note",
		handler = M.git_branch_note,
	},
	journal_note = {
		key = "j",
		title = "Daily Journal",
		handler = M.daily_note,
	},
}

return M
