local config = require("org_markdown.config")
local utils = require("org_markdown.utils.utils")
local parser = require("org_markdown.utils.parser")
local async = require("org_markdown.utils.async")
local datetime = require("org_markdown.utils.datetime")

local M = {}

M.CAPTURE_TEMPLATE_CHARS = { "%", "^", "?", "<", ">" }

--
--- @param prompt_template string: The template string containing a placeholder like "%^{label}"
function M.extract_label_from_prompt_template(prompt_template)
	local label = prompt_template:match("^%%^{(.-)}$")
	return label
end

local function escape_capture_template_marker(marker)
	return parser.escape_marker(marker, M.CAPTURE_TEMPLATE_CHARS)
end

function M.capture_template_substitute(template, marker, replacement, replacement_count)
	local escaped_marker = escape_capture_template_marker(marker)
	return template:gsub(escaped_marker, replacement, replacement_count)
end

function M.capture_template_match(template, marker)
	return template:match(escape_capture_template_marker(marker))
end

--- @return integer, integer: row and column indices (0-based)
function M.capture_template_find(template, marker)
	local escaped_marker = escape_capture_template_marker(marker)
	local s, _ = template:find(escaped_marker)
	return utils.byte_index_to_row_col(template, s)
end

function M.open_capture_buffer_async(content, cursor_row, cursor_col, tpl)
	return async.promise(function(resolve, _)
		-- Submit buffer
		local function submit_buffer(buf)
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local trimmed_lines = utils.trim_trailing_whitespace(lines)
			return table.concat(trimmed_lines, "\n")
		end

		local filename = "Capture template: " .. tpl.name
		local buf, win = utils.open_window({
			method = config.captures.window_method,
			title = filename,
			filename = filename,
			filetype = "markdown",
			footer = "Press <C-c><C-c>, <leader><CR> to save, <C-c><C-k> to cancel",
			on_close = function(buf, win, close_key)
				if close_key == "q" then
					resolve("")
				else
					resolve(submit_buffer(buf))
				end
			end,
		})

		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
		utils.set_cursor(win, cursor_row, cursor_col, "i")

		-- Setup template cycling if multiple templates exist
		local template_names = vim.tbl_keys(config.captures.templates)
		table.sort(template_names) -- Ensure consistent order

		if #template_names > 1 then
			local cycler = require("org_markdown.utils.cycler")

			-- Find current template index
			local current_index = 1
			for i, name in ipairs(template_names) do
				if name == tpl.name then
					current_index = i
					break
				end
			end

			vim.b[buf].capture_template_index = current_index

			local cycle_instance = cycler.create(buf, win, {
				items = template_names,
				get_index = function(buf)
					return vim.b[buf].capture_template_index or 1
				end,
				set_index = function(buf, index)
					vim.b[buf].capture_template_index = index
				end,
				on_cycle = function(buf, win, template_name, index, total)
					-- Close current capture buffer
					if vim.api.nvim_win_is_valid(win) then
						vim.api.nvim_win_close(win, true)
					end

					-- Cancel the current promise by resolving with empty string
					resolve("")

					-- Open new capture with the new template
					M.capture_template(template_name)

					-- Return false to indicate buffer was closed, don't update footer
					return false
				end,
				get_footer = function(template_name, index, total)
					return string.format(
						"[%d/%d] %s | ] next | [ prev | <C-c><C-c> save | <C-c><C-k> cancel",
						index,
						total,
						template_name
					)
				end,
				memory_id = "capture",
			})

			cycle_instance:setup()
		end

		-- TODO PAL: Refactor open_window so it can take, close_key and quit_keys and a callback for on_close and on_quit
		vim.keymap.set("n", "<C-c><C-c>", function()
			local joined = submit_buffer(buf)
			vim.api.nvim_win_close(win, true)
			resolve(joined)
		end, { buffer = buf })
		vim.keymap.set("n", "<leader><CR>", function()
			local joined = submit_buffer(buf)
			vim.api.nvim_win_close(win, true)
			resolve(joined)
		end, { buffer = buf })

		-- Jump to next %?
		vim.keymap.set("n", "<Tab>", function()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local text = table.concat(lines, "\n")

			local row, col = M.capture_template_find(text, "%?")
			if row and col then
				text = M.capture_template_substitute(text, "%?", "", 1)
				local updated_lines = vim.split(text, "\n")
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, updated_lines)
				utils.set_cursor(win, row, col, "i")
			end
		end, { buffer = buf })

		-- Cancel buffer
		vim.keymap.set("n", "<C-c><C-k>", function()
			vim.api.nvim_win_close(win, true)
			resolve("")
		end, { buffer = buf })
	end)
end

-- Insert a capture line under a specific heading in a file
local key_mapping = {
	-- %t: <YYYY-MM-DD Day>
	{
		pattern = "%t",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, datetime.capture_format("%Y-%m-%d %a", "<"))
		end,
	},
	-- %T: <YYYY-MM-DD Day HH:MM>
	{
		pattern = "%T",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, datetime.capture_format("%Y-%m-%d %a %H:%M", "<"))
		end,
	},
	-- %u: [YYYY-MM-DD Day]
	{
		pattern = "%u",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, datetime.capture_format("%Y-%m-%d %a", "["))
		end,
	},
	-- %U: [YYYY-MM-DD Day HH:MM]
	{
		pattern = "%U",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, datetime.capture_format("%Y-%m-%d %a %H:%M", "["))
		end,
	},
	-- %n: Author name (from config, git, or system user)
	{
		pattern = "%n",
		handler = function(text, matched_target, _)
			local name = config.captures.author_name
			if not name or name == "" then
				-- Fallback to git config
				name = vim.fn.system("git config user.name"):gsub("\n", "")
			end
			if not name or name == "" then
				-- Fallback to system user
				name = vim.env.USER or "User"
			end
			return M.capture_template_substitute(text, matched_target, name)
		end,
	},
	-- %H: Time only (HH:MM) - renamed from %t to avoid conflict
	{
		pattern = "%H",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, datetime.capture_format("%H:%M"))
		end,
	},
	{
		pattern = "%Y",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, datetime.capture_format("%Y"))
		end,
	},
	{
		pattern = "%m",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, datetime.capture_format("%m"))
		end,
	},
	{
		pattern = "%d",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, datetime.capture_format("%d"))
		end,
	},
	{
		pattern = "%f",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, vim.fn.expand("%"))
		end,
	},
	{
		pattern = "%F",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, vim.fn.expand("%:p"))
		end,
	},
	{
		pattern = "%a",
		handler = function(text, matched_target, tpl)
			local filepath = vim.fn.expand("%:p")
			local linenr = vim.fn.line(".")
			local loc = string.format("[[file:%s +%d]]", filepath, linenr)
			return M.capture_template_substitute(text, matched_target, loc)
		end,
	},
	{
		pattern = "%<.-%>",
		handler = function(text, matched_target, _)
			local fmt = matched_target:match("%<(.-)%>")
			if fmt then
				return M.capture_template_substitute(text, matched_target, datetime.capture_format(fmt))
			else
				return text
			end
		end,
	},
	{
		pattern = "%x",
		handler = function(text, matched_target, _)
			local clip = vim.fn.getreg("+")
			return M.capture_template_substitute(text, matched_target, clip)
		end,
	},
	{
		pattern = "%^{.-}",
		handler = function(text, matched_target, _)
			local prompt_label = M.extract_label_from_prompt_template(matched_target) or "filler"
			local prompt_response = utils.open_prompt(prompt_label):await()
			-- If user canceled, return empty string to cancel capture entirely
			if prompt_response == nil then
				return ""
			end
			return M.capture_template_substitute(text, matched_target, prompt_response)
		end,
	},
	{
		pattern = "%?",
		handler = function(text, matched_target, tpl)
			local row, col = M.capture_template_find(text, matched_target)
			local cleaned = M.capture_template_substitute(text, matched_target, "", 1)
			if row and col then
				local buffer_result = M.open_capture_buffer_async(cleaned, row, col, tpl):await()
				return buffer_result
			else
				return text
			end
		end,
	},
}
-- Prompt and capture
function M.capture_template(name)
	async.run(function()
		-- If no name provided, use saved preference or default
		if not name then
			local cycler = require("org_markdown.utils.cycler")
			local saved_index = cycler.get_memory("capture")
			if saved_index then
				local template_names = vim.tbl_keys(config.captures.templates)
				table.sort(template_names)
				name = template_names[saved_index] or config.captures.default_template
			else
				name = config.captures.default_template
			end
		end

		local tpl = config.captures.templates[name]
		if not tpl then
			vim.notify("No capture template for: " .. name, vim.log.levels.ERROR)
			return
		end
		tpl.name = name

		local template = type(tpl.template) == "function" and tpl.template() or tpl.template
		local text = template

		for _, entry in ipairs(key_mapping) do
			local pattern = entry.pattern
			local handler = entry.handler
			local matched_target = M.capture_template_match(text, pattern)
			if matched_target then
				text = handler(text, matched_target, tpl)
			end
		end
		if text ~= "" then
			utils.insert_under_heading(vim.fn.expand(tpl.filename), tpl.heading, vim.split(text, "\n"))
			vim.notify("Captured to " .. tpl.filename .. " under heading " .. tpl.heading)
		end
	end)
end

return M
