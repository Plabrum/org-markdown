local config = require("org_markdown.config")
local utils = require("org_markdown.utils")
local parser = require("org_markdown.parser")

local M = {}

M.CAPTURE_TEMPLATE_CHARS = { "%", "^", "?" }

--
--- @param prompt_template string: The template string containing a placeholder like "%^{label}"
function M.extract_label_from_prompt_template(prompt_template)
	return prompt_template:match("^%%^{(.-)}$")
end

-- Insert a capture line under a specific heading in a file
local key_mapping = {
	["%n"] = "Phil Labrum",
	["%t"] = function()
		return os.date("%H:%M")
	end,
	["%Y"] = function()
		return os.date("%Y")
	end,
	["%m"] = function()
		return os.date("%m")
	end,
	["%d"] = function()
		return os.date("%d")
	end,
	["%^{.-}"] = function(key)
		local prompt_label = M.extract_label_from_prompt_template(key)
		print("Extracted label:", prompt_label)
		return utils.open_prompt(prompt_label)
	end,
}
local function capture_template_substitor(s, marker, repl, opts)
	local merged_opts = vim.tbl_deep_extend("force", { escape_chars = M.CAPTURE_TEMPLATE_CHARS }, opts or {})
	return parser.escaped_substitute(s, marker, repl, merged_opts)
end

-- Prompt and capture
function M.capture_template(name)
	name = name or config.default_capture
	local tpl = config.capture_templates[name]
	if not tpl then
		vim.notify("No capture template for: " .. name, vim.log.levels.ERROR)
		return
	end
	local template = type(tpl.template) == "function" and tpl.template() or tpl.template

	local populated_template = parser.substitute_dynamic_values(template, key_mapping, capture_template_substitor)
	local cleaned, row, col = parser.strip_marker_and_get_position(populated_template, "%?", capture_template_substitor)
	-- Open window for capture
	if row == nil or col == nil then
		-- short circuit if no %? found and submit capture
		M.insert_under_heading(vim.fn.expand(tpl.file), tpl.heading, populated_template)
		vim.notify("Captured to " .. name)
	else
		-- Locate %? for cursor placement and remove it
		local buf, win = utils.open_window({
			method = config.window_method,
			title = "Capture to " .. name,
			filetype = "markdown",
			footer = "Press <C-c><C-c> to save, <C-c><C-k> to cancel",
		})
		-- Set buffer content and cursor
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(cleaned, "\n"))
		vim.api.nvim_win_set_cursor(win, { row + 1, col })

		-- Map C-c C-c to save
		vim.keymap.set("n", "<C-c><C-c>", function()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			-- Remove trailing empty lines (optional)
			while #lines > 0 and lines[#lines]:match("^%s*$") do
				table.remove(lines)
			end
			M.insert_under_heading(vim.fn.expand(tpl.file), tpl.heading, lines)
			vim.api.nvim_win_close(win, true)

			vim.notify("Captured to " .. name)
		end, { buffer = buf })

		-- Map C-c C-k to cancel
		vim.keymap.set("n", "<C-c><C-k>", function()
			vim.api.nvim_win_close(win, true)
		end, { buffer = buf })
	end
end

return M
