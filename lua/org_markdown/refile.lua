local utils = require("org_markdown.utils")
local config = require("org_markdown.config")

local M = {}

local function pick_item(items, prompt, on_select)
	if config.picker == "snacks" then
		local ok, snacks = pcall(require, "snacks")
		local select = ok and snacks and snacks.picker and snacks.picker.select
		if type(select) == "function" then
			select(items, {
				prompt = prompt,
				format_item = tostring,
				kind = "refile",
				preview = function(item)
					if type(item) == "string" and vim.fn.filereadable(item) == 1 then
						return vim.fn.readfile(item)
					else
						return { "No preview available" }
					end
				end,
			}, function(choice)
				if choice then
					on_select(choice)
				end
			end)
			return
		else
			vim.notify("snacks.picker.select not available, falling back to telescope", vim.log.levels.WARN)
		end
	end

	-- telescope fallback
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	pickers
		.new({}, {
			prompt_title = prompt,
			finder = finders.new_table({ results = items }),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(_, _)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(_)
					if selection and selection.value then
						on_select(selection.value)
					end
				end)
				return true
			end,
		})
		:find()
end

function M.to_file()
	-- 1. Try to resolve content under cursor first
	local selection = utils.get_refile_target()
	if not selection or not selection.lines then
		vim.notify("No bullet point or heading detected to refile", vim.log.levels.ERROR)
		return
	end

	-- 2. Ask user to pick destination
	local files = utils.find_markdown_files()
	pick_item(files, "Refile to file", function(target_path)
		-- 3. Cut + paste
		vim.api.nvim_buf_set_lines(0, selection.start_line, selection.end_line, false, {})
		utils.append_lines(target_path, selection.lines)
		vim.notify("Refiled to " .. target_path)
	end)
end

function M.to_heading()
	local files = utils.find_markdown_files()
	pick_item(files, "Select file", function(target_file)
		local lines = utils.read_lines(target_file)
		local headings = {}
		for _, line in ipairs(lines) do
			local level, text = line:match("^(#+)%s+(.-)%s*$")
			if level then
				table.insert(headings, text)
			end
		end

		if #headings == 0 then
			vim.notify("No headings found in " .. target_file, vim.log.levels.ERROR)
			return
		end

		pick_item(headings, "Select heading", function(heading)
			local selection = utils.get_refile_target()
			if not selection or not selection.lines then
				vim.notify("No content selected to refile", vim.log.levels.ERROR)
				return
			end

			vim.api.nvim_buf_set_lines(0, selection.start_line, selection.end_line, false, {})
			utils.insert_under_heading(target_file, heading, table.concat(selection.lines, "\n"))
			vim.notify("Refiled under " .. heading)
		end)
	end)
end

return M
