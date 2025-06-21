local config = require("org_markdown.config")

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

function M.safe_extend(base, more)
	return vim.list_extend(base or {}, more or {})
end

function M.open_prompt(label)
	local result = nil
	local done = false

	vim.ui.input({ prompt = label .. ": " }, function(input)
		result = input or ""
		done = true
	end)

	vim.wait(10000, function()
		return done
	end, 10)

	return result
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
local function set_close_keys(buf, win)
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf, silent = true })

	vim.keymap.set("n", "<Esc>", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf, silent = true })
end

-- Floating window
local function create_float_window(buf, opts)
	local fill = opts.fill or 0.8
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

	if opts.on_close then
		vim.api.nvim_buf_attach(buf, false, {
			on_detach = function()
				opts.on_close()
			end,
		})
	end
	set_close_keys(buf, win)
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

	set_close_keys(buf, win)
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

function M.insert_under_heading(filepath, heading_text, content_lines)
	local lines = M.read_lines(filepath)
	local out = {}
	local inserted = false

	for i, line in ipairs(lines) do
		table.insert(out, line)
		if not inserted and line:match("^#+%s+" .. vim.pesc(heading_text) .. "%s*$") then
			vim.list_extend(out, content_lines)
			inserted = true
		end
	end

	if not inserted then
		table.insert(out, "")
		table.insert(out, "# " .. heading_text)
		vim.list_extend(out, content_lines)
	end

	M.write_lines(filepath, out)
end

return M
