local config = require("org_markdown.config")
local utils = require("org_markdown.utils")

local M = {}

-- Insert a capture line under a specific heading in a file
local function insert_under_heading(filepath, heading_text, content)
	local lines = utils.read_lines(filepath)
	local out = {}
	local inserted = false

	for i, line in ipairs(lines) do
		table.insert(out, line)
		if not inserted and line:match("^#+%s+" .. vim.pesc(heading_text) .. "%s*$") then
			table.insert(out, content)
			inserted = true
		end
	end

	if not inserted then
		table.insert(out, "")
		table.insert(out, "# " .. heading_text)
		table.insert(out, content)
	end

	utils.write_lines(filepath, out)
end

local function extract_prompts(template)
	local prompts = {}
	for key in template:gmatch("%^%{(.-)%}") do
		if not vim.tbl_contains(prompts, key) then
			table.insert(prompts, key)
		end
	end
	return prompts
end

local function fill_prompts(template, prompts, callback)
	local values = {}
	local i = 1

	local function prompt_next()
		local key = prompts[i]
		if not key then
			local final = template
			for name, value in pairs(values) do
				final = final:gsub("%^%{" .. name .. "%}", value)
			end
			callback(final)
			return
		end

		vim.ui.input({ prompt = key .. ": " }, function(input)
			if not input then
				return
			end
			values[key] = input
			i = i + 1
			prompt_next()
		end)
	end

	prompt_next()
end

local function expand_template(template, input, expand_prompt)
	local result = template
		:gsub("%%t", os.date("%H:%M"))
		:gsub("%%Y", os.date("%Y"))
		:gsub("%%m", os.date("%m"))
		:gsub("%%d", os.date("%d"))

	return result:gsub("%%%" .. "?", "@@CURSOR@@")
end

-- Prompt and capture
function M.capture_template(name)
	name = name or config.default_capture
	local tpl = config.capture_templates[name]
	if not tpl then
		vim.notify("No capture template for: " .. name, vim.log.levels.ERROR)
		return
	end
	local template = tpl.template
	local heading = tpl.heading
	local prompt_fields = extract_prompts(template)

	if #prompt_fields > 0 then
		-- Prompt first, then insert directly
		fill_prompts(template, prompt_fields, function(filled)
			insert_under_heading(vim.fn.expand(tpl.file), tpl.heading, filled)
			vim.notify("Captured to " .. name)
		end)
		return
	end

	-- fallback: open float buffer with %t, %Y, %? tokens
	local buf, win = utils.open_window({
		method = config.window_method,
		title = "Capture to " .. name,
		filetype = "markdown",
		footer = "Press <C-c><C-c> to save, <C-c><C-k> to cancel",
	})

	-- Expand everything except the prompt (%?)
	local initial_line = expand_template(tpl.template, nil, false)

	-- Find @@CURSOR@@ position
	local cursor_row, cursor_col = 0, 0
	local processed_lines = {}
	for i, line in ipairs(vim.split(initial_line, "\n")) do
		local col = line:find("@@CURSOR@@")
		if col then
			cursor_row = i - 1
			cursor_col = col - 1
			line = line:gsub("@@CURSOR@@", "")
		end
		table.insert(processed_lines, line)
	end
	table.insert(processed_lines, "")

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, processed_lines)
	vim.api.nvim_win_set_cursor(win, { cursor_row + 1, cursor_col })
	-- Find @@CURSOR@@ position

	-- Map C-c C-c to save
	vim.keymap.set("n", "<C-c><C-c>", function()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local line = table.concat(lines, " "):gsub("%s+$", "")

		insert_under_heading(vim.fn.expand(tpl.file), tpl.heading, line)
		vim.api.nvim_win_close(win, true)
		vim.notify("Captured to " .. name)
	end, { buffer = buf })

	-- Map C-c C-k to cancel
	vim.keymap.set("n", "<C-c><C-k>", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf })
end

return M
