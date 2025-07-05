local config = require("org_markdown.config")
local utils = require("org_markdown.utils.utils")
local parser = require("org_markdown.utils.parser")
local async = require("org_markdown.utils.async")

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

function M.open_capture_buffer(content, cursor_row, cursor_col, tpl)
	return async.promise(function(resolve, _)
		local filename = "Capture template: " .. tpl.name
		local buf, win = utils.open_window({
			method = config.captures.window_method,
			title = filename,
			filename = filename,
			filetype = "markdown",
			footer = "Press <C-c><C-c>, <leader><CR> to save, <C-c><C-k> to cancel",
		})

		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
		utils.set_cursor(win, cursor_row, cursor_col, "i")

		-- Submit buffer
		local function submit_buffer()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local trimmed_lines = utils.trim_trailing_whitespace(lines)
			local joined = table.concat(trimmed_lines, "\n")
			vim.api.nvim_win_close(win, true)
			resolve(joined)
		end
		vim.keymap.set("n", "<C-c><C-c>", submit_buffer, { buffer = buf })
		vim.keymap.set("n", "<leader><CR>", submit_buffer, { buffer = buf })

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

local function format_date(fmt)
	return os.date(fmt)
end

local function inactive_date(fmt)
	return "[" .. os.date(fmt) .. "]"
end

local function active_date(fmt)
	return "<" .. os.date(fmt) .. ">"
end

-- Insert a capture line under a specific heading in a file
local key_mapping = {
	-- %t: <YYYY-MM-DD Day>
	{
		pattern = "%t",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, active_date("%Y-%m-%d %a"))
		end,
	},
	-- %T: <YYYY-MM-DD Day HH:MM>
	{
		pattern = "%T",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, active_date("%Y-%m-%d %a %H:%M"))
		end,
	},
	-- %u: [YYYY-MM-DD Day]
	{
		pattern = "%u",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, inactive_date("%Y-%m-%d %a"))
		end,
	},
	-- %U: [YYYY-MM-DD Day HH:MM]
	{
		pattern = "%U",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, inactive_date("%Y-%m-%d %a %H:%M"))
		end,
	},
	{
		pattern = "%n",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, "Phil Labrum")
		end,
	},
	{
		pattern = "%t",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, os.date("%H:%M"))
		end,
	},
	{
		pattern = "%Y",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, os.date("%Y"))
		end,
	},
	{
		pattern = "%m",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, os.date("%m"))
		end,
	},
	{
		pattern = "%d",
		handler = function(text, matched_target, _)
			return M.capture_template_substitute(text, matched_target, os.date("%d"))
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
				return M.capture_template_substitute(text, matched_target, os.date(fmt))
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
				local buffer_result = M.open_capture_buffer(cleaned, row, col, tpl):await()
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
		name = name or config.captures.default_template
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
