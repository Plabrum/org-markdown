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

function M.open_quick_note(recipe_key)
	local recipe = M.recipes[recipe_key]
	if not recipe then
		vim.notify("Quicknote recipe not found: " .. recipe_key, vim.log.levels.ERROR)
		return
	end

	local quick_notes_dir = vim.fn.expand(config.quick_note_file)
	local note_filename = recipe.handler()
	local filepath = vim.fn.fnamemodify(quick_notes_dir .. note_filename, ":p")
	local dir = vim.fn.fnamemodify(filepath, ":h")

	-- Validate filepath
	if filepath == "" or filepath:match('[<>:"|?*]') then
		vim.notify("Invalid quick note filename: " .. note_filename, vim.log.levels.ERROR)
		return
	end

	-- Ensure directory exists before creating buffer
	local mkdir_result = vim.fn.mkdir(dir, "p")
	if mkdir_result == 0 and vim.fn.isdirectory(dir) == 0 then
		vim.notify("Failed to create directory: " .. dir, vim.log.levels.ERROR)
		return
	end

	-- Open window with filepath - create_buffer will handle buffer creation/reuse
	local buf, win = utils.open_window({
		method = config.window_method,
		title = "Quick Note: " .. recipe.title,
		filetype = "markdown",
		footer = "Auto-saved on CursorHold/InsertLeave | Press q or <Esc> to close",
		filepath = filepath, -- This triggers normal file buffer creation
	})

	-- Set cursor to beginning of file
	utils.set_cursor(win, 0, 0, "n")

	-- Setup recipe cycling if multiple recipes exist
	local recipe_keys = vim.tbl_keys(M.recipes)
	table.sort(recipe_keys) -- Ensure consistent order

	if #recipe_keys > 1 then
		local cycler = require("org_markdown.utils.cycler")

		-- Find current recipe index
		local current_index = 1
		for i, key in ipairs(recipe_keys) do
			if key == recipe_key then
				current_index = i
				break
			end
		end

		vim.b[buf].quicknote_recipe_index = current_index

		local cycle_instance = cycler.create(buf, win, {
			items = recipe_keys,
			get_index = function(buf)
				return vim.b[buf].quicknote_recipe_index or 1
			end,
			set_index = function(buf, index)
				vim.b[buf].quicknote_recipe_index = index
			end,
			on_cycle = function(buf, win, new_recipe_key, index, total)
				-- Save current buffer before switching
				if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified then
					pcall(function()
						vim.api.nvim_buf_call(buf, function()
							vim.cmd("silent! write")
						end)
					end)
				end

				-- Close current window (use pcall to handle "last window" case)
				if vim.api.nvim_win_is_valid(win) then
					pcall(vim.api.nvim_win_close, win, true)
				end

				-- Open new quicknote
				M.open_quick_note(new_recipe_key)

				-- Return false to indicate buffer was closed, don't update footer
				return false
			end,
			get_footer = function(recipe_key, index, total)
				local r = M.recipes[recipe_key]
				return string.format("[%d/%d] %s | ] next | [ prev | Auto-saved | q close", index, total, r.title)
			end,
			memory_id = "quicknote",
		})

		cycle_instance:setup()
	end
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
