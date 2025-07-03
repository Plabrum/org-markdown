local config = require("org_markdown.config")
local async = require("org_markdown.async")
local editing = require("org_markdown.editing")

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
	vim.bo[buf].buftype = opts.buftype or "acwrite"
	vim.bo[buf].bufhidden = opts.bufhidden or "wipe"
	vim.bo[buf].modifiable = true
	vim.bo[buf].swapfile = false
	if opts.name then
		vim.api.nvim_buf_set_name(buf, opts.name)
	else
		vim.api.nvim_buf_set_name(buf, "org-markdown")
	end

	editing.setup_editing_keybinds(buf)
	return buf
end

local function get_active_windows()
	local active = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local cfg = vim.api.nvim_win_get_config(win)

		if cfg.relative == "" then
			local name = vim.api.nvim_buf_get_name(buf)
			local ft = vim.api.nvim_get_option_value("filetype", { buf = buf })
			local bt = vim.api.nvim_get_option_value("buftype", { buf = buf })

			if name ~= "" and ft ~= "" and bt == "" then
				table.insert(active, win)
			end
		end
	end
	return active
end

local function set_close_keys(buf, win, opts)
	local function try_close()
		if opts.on_close then
			opts.on_close(buf)
		end

		if opts.persist_window then
			if opts._previous_buf and vim.api.nvim_buf_is_valid(opts._previous_buf) then
				vim.bo[buf].modified = false
				vim.api.nvim_win_set_buf(win, opts._previous_buf)
			end
		else
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end

		if vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) == 0 then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end

	vim.keymap.set("n", "q", try_close, { buffer = buf, silent = true })
	vim.keymap.set("n", "<Esc>", try_close, { buffer = buf, silent = true })
	--
	-- vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
	-- 	buffer = buf,
	-- 	callback = try_close,
	-- })
	--
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			if opts.on_close then
				opts.on_close(buf)
			end
			vim.bo[buf].modified = false
		end,
	})

	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = try_close,
	})
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

local function create_vsplit(buf, opts)
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

local function create_vertical_window(buf, opts)
	opts = opts or {}
	opts._previous_buf = vim.api.nvim_get_current_buf()

	local win

	if vim.o.columns > 120 then
		local windows = get_active_windows()

		if windows[2] then
			-- Use the second active code window
			win = windows[2]
		else
			-- Otherwise, create a vertical split and grab the new window
			local before = get_active_windows()
			vim.cmd("vsplit")
			opts.persist_window = true
			local after = get_active_windows()

			for _, w in ipairs(after) do
				if not vim.tbl_contains(before, w) then
					win = w
					break
				end
			end

			-- fallback in case we can't detect the new window
			if not win then
				win = vim.api.nvim_get_current_win()
				opts.persist_window = true
			end
		end

		vim.api.nvim_win_set_buf(win, buf)
	else
		win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(win, buf)
		opts.persist_window = true
	end

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

	set_close_keys(buf, win, opts)
	return buf, win
end

-- Public API
function M.open_window(opts)
	local method = opts.method or config.window_method
	local buf = create_buffer(opts)

	if method == "float" then
		return create_float_window(buf, opts)
	elseif method == "horizontal" then
		return create_horizontal_window(buf, opts)
	elseif method == "inline_prompt" then
		return create_inline_prompt_window(buf, opts)
	elseif method == "vsplit" then
		return create_vsplit(buf, opts)
	elseif method == "vertical" then
		return create_vertical_window(buf, opts)
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
