local config = require("org_markdown.config")
local async = require("org_markdown.async")

local M = {}

function M.is_markdown_file(filepath)
	return filepath:match("%.md$") or filepath:match("%.markdown$")
end

function M.read_lines(path)
	local f = io.open(path, "r")
	if not f then
		return {}
	end
	local lines = {}
	for line in f:lines() do
		table.insert(lines, line)
	end
	f:close()
	return lines
end

function M.write_lines(path, lines)
	path = vim.fn.expand(path)

	local dir = vim.fn.fnamemodify(path, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end

	local f, err = io.open(path, "w")
	if not f then
		vim.notify("Failed to write to " .. path .. ": " .. (err or "unknown error"), vim.log.levels.ERROR)
		return
	end

	for _, line in ipairs(lines) do
		f:write(line .. "\n")
	end
	f:close()
end

function M.open_prompt(label)
	return async.wrap(function(_, callback)
		vim.ui.input({ prompt = label .. ": " }, callback)
	end)()
end

-- used for turning a find result into a row/col position
--- @param text string: the text to search in
--- @param byte_index integer: the byte index to convert
--- @return integer, integer: row and column indices (0-based)
function M.byte_index_to_row_col(text, byte_index)
	local row, col = 0, 0
	local current_index = 1
	for line in text:gmatch("([^\n]*)\n?") do
		local line_len = #line + 1 -- include newline
		if byte_index < current_index + line_len then
			col = byte_index - current_index
			return row, col
		end
		current_index = current_index + line_len
		row = row + 1
	end
	return row, col
end

--- Move the cursor to (row, col) in the given window and optionally enter mode
--- @param win integer: window ID
--- @param row integer: 0-based row
--- @param col integer: 0-based column
--- @param mode string: 'n' for normal, 'i' for insert
function M.set_cursor(win, row, col, mode)
	vim.api.nvim_win_set_cursor(win, { row + 1, col })
	if mode == "i" then
		vim.cmd("startinsert!")
	elseif mode == "n" then
		vim.cmd("stopinsert")
	end
end

-- Shared: create reusable buffer
local function create_buffer(opts)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].filetype = opts.filetype or "markdown"
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	return buf
end

-- set close keymaps
local function set_close_keys(buf, win, opts)
	vim.keymap.set("n", "q", function()
		if opts.on_close then
			opts.on_close(buf)
		end
		if not opts.preseve_window then
			vim.api.nvim_win_close(win, true)
		end
	end, { buffer = buf, silent = true })

	vim.keymap.set("n", "<Esc>", function()
		if opts.on_close then
			opts.on_close(buf)
		end
		if not opts.preseve_window then
			vim.api.nvim_win_close(win, true)
		end
	end, { buffer = buf, silent = true })
end

-- inline prompt window
local function create_inline_prompt_window(buf, opts)
	local width = opts.width or 30
	local row = opts.row or 1
	local col = opts.col or 0

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "cursor",
		row = row,
		col = col,
		width = width,
		height = 1,
		style = "minimal",
		border = opts.border or "none",
		title = opts.title,
		title_pos = opts.title_pos or "center",
	})

	vim.bo[buf].buftype = "prompt"
	vim.fn.prompt_setprompt(buf, opts.prompt or "")

	if opts.on_submit then
		vim.fn.prompt_setcallback(buf, function(input)
			vim.api.nvim_win_close(win, true)
			opts.on_submit(input)
		end)
	end

	if opts.on_close then
		vim.api.nvim_buf_attach(buf, false, {
			on_detach = function()
				opts.on_close()
			end,
		})
	end

	set_close_keys(buf, win)

	vim.cmd.startinsert()

	return buf, win
end

-- Floating window
local function create_float_window(buf, opts)
	local fill = opts.fill or 0.6
	local width = math.floor(vim.o.columns * fill)
	local height = math.floor(vim.o.lines * fill)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = opts.title or "",
		title_pos = "center",
		footer = opts.footer or "", -- <-- new
		footer_pos = opts.footer_pos or "center",
	})

	set_close_keys(buf, win, opts)
	return buf, win
end

-- Horizontal bottom split
local function create_horizontal_window(buf, opts)
	vim.cmd("botright split")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_win_set_height(win, opts.height or math.floor(vim.o.lines * 0.3))

	if opts.title then
		vim.api.nvim_buf_set_lines(buf, 0, 0, false, {
			"# " .. opts.title,
			"", -- padding
		})
	end

	if opts.footer then
		local footer_text = type(opts.footer) == "table" and table.concat(opts.footer, " | ") or opts.footer
		vim.wo[win].statusline = footer_text
	end

	if not opts.preserve_focus then
		vim.api.nvim_set_current_win(win)
	end

	set_close_keys(buf, win, opts)
	return buf, win
end

local function create_vertical_window(buf, opts)
	vim.cmd("vsplit")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_win_set_width(win, opts.width or math.floor(vim.o.columns * 0.3))

	if opts.title then
		vim.api.nvim_buf_set_lines(buf, 0, 0, false, {
			"# " .. opts.title,
			"", -- padding
		})
	end

	if opts.footer then
		local footer_text = type(opts.footer) == "table" and table.concat(opts.footer, " | ") or opts.footer
		vim.wo[win].statusline = footer_text
	end

	if not opts.preserve_focus then
		vim.api.nvim_set_current_win(win)
	end

	set_close_keys(buf, win, opts)
	return buf, win
end

local function open_in_next_window(buf)
	local current_tab = vim.api.nvim_get_current_tabpage()
	local current_win = vim.api.nvim_get_current_win()

	-- Get only normal (non-floating) windows
	local all_wins = vim.api.nvim_tabpage_list_wins(current_tab)
	local wins = {}

	for _, win in ipairs(all_wins) do
		local cfg = vim.api.nvim_win_get_config(win)
		if cfg.relative == "" then
			table.insert(wins, win)
		end
	end

	if #wins == 1 then
		vim.cmd("vsplit")
		local new_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(new_win, buf)
		return buf, new_win
	else
		-- Find index of current normal window
		local index = nil
		for i, win in ipairs(wins) do
			if win == current_win then
				index = i
				break
			end
		end

		-- Fallback in case current_win was not found
		if not index then
			vim.api.nvim_win_set_buf(wins[1], buf)
			return buf, wins[1]
		end

		local next_index = (index % #wins) + 1
		local next_win = wins[next_index]
		vim.api.nvim_set_current_win(next_win)
		vim.api.nvim_win_set_buf(next_win, buf)
		return buf, next_win
	end
end

local function create_window_in_place(buf, opts)
	opts = opts or {}

	local _, win = open_in_next_window(buf)

	if opts.title then
		vim.api.nvim_buf_set_lines(buf, 0, 0, false, {
			"# " .. opts.title,
			"",
		})
	end

	if opts.footer then
		local footer_text = type(opts.footer) == "table" and table.concat(opts.footer, " | ") or opts.footer
		vim.wo[win].statusline = footer_text
	end

	if not opts.preserve_focus then
		vim.api.nvim_set_current_win(win)
	end

	-- Spread `opts` and inject `preserve_window = true` non-destructively
	set_close_keys(buf, win, vim.tbl_extend("force", opts, { preserve_window = true }))
	return buf, win
end

-- Public API
function M.open_window(opts)
	local method = opts.method or "float"
	local buf = create_buffer(opts)

	if method == "float" then
		return create_float_window(buf, opts)
	elseif method == "horizontal" then
		return create_horizontal_window(buf, opts)
	elseif method == "inline_prompt" then
		return create_inline_prompt_window(buf, opts)
	elseif method == "vertical" then
		return create_vertical_window(buf, opts)
	elseif method == "next_vertical" then
		return create_window_in_place(buf, opts)
	else
		error("Unknown window method: " .. method)
	end
end

function M.append_lines(filepath, lines)
	local buf_lines = M.read_lines(filepath)
	for _, line in ipairs(lines) do
		table.insert(buf_lines, line)
	end
	M.write_lines(filepath, buf_lines)
end

-- Helper: Adjust heading levels to be children of given base level
function M.adjust_heading_levels(lines, base_level)
	local adjusted = {}
	for _, line in ipairs(lines) do
		local hashes, title = line:match("^(#+)%s+(.*)")
		if hashes and title then
			local new_level = string.rep("#", base_level + #hashes)
			table.insert(adjusted, new_level .. " " .. title)
		else
			table.insert(adjusted, line)
		end
	end
	return adjusted
end

-- Helper: Find heading range (start line, heading level, end line of subtree)
function M.find_heading_range(lines, heading_text)
	for i, line in ipairs(lines) do
		local match = line:match("^(#+)%s+" .. vim.pesc(heading_text) .. "%s*$")
		if match then
			local base_level = #match
			local end_index = #lines + 1 -- default: end of file

			for j = i + 1, #lines do
				local next_heading = lines[j]:match("^(#+)")
				if next_heading and #next_heading <= base_level then
					end_index = j
					break
				end
			end

			return i, base_level, end_index
		end
	end
	return nil, nil, nil
end

-- Main function
function M.insert_under_heading(filepath, heading_text, content_lines)
	local lines = M.read_lines(filepath)

	local start_idx, base_level, insert_idx = M.find_heading_range(lines, heading_text)

	if start_idx and insert_idx then
		local adjusted_content = M.adjust_heading_levels(content_lines, base_level)

		-- Insert content before next sibling heading (or end of file)
		for i = #adjusted_content, 1, -1 do
			table.insert(lines, insert_idx, adjusted_content[i])
		end
	else
		-- Heading not found — add it at EOF
		table.insert(lines, "")
		table.insert(lines, "# " .. heading_text)
		vim.list_extend(lines, content_lines)
	end

	M.write_lines(filepath, lines)
end

--- Removes trailing empty or whitespace-only lines from a list of lines
--- @param lines string[]
--- @return string[]: a new table with trailing whitespace removed
function M.trim_trailing_whitespace(lines)
	-- Make a shallow copy to avoid mutating the original table
	local trimmed = vim.deepcopy(lines)

	while #trimmed > 0 and trimmed[#trimmed]:match("^%s*$") do
		table.remove(trimmed)
	end

	return trimmed
end

return M
