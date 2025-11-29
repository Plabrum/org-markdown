local config = require("org_markdown.config")
local M = {}

function M.cycle_checkbox_inline(line, states)
	local pattern = "%- %[(.)%]"
	local current = line:match(pattern)

	-- early return if no checkbox found
	if not current then
		return nil
	end

	local index
	for i, state in ipairs(states) do
		if state == current then -- compare raw
			index = i
			break
		end
	end

	if not index then
		return nil
	end

	local next_state = states[(index % #states) + 1]
	return { (line:gsub(pattern, "- [" .. next_state .. "]", 1)) }
end

function M.cycle_status_inline(line, states)
	local heading_pattern = "^(#+)%s+(%u[%u_%-]*)%s+(.*)$"
	local hashes, current, rest = line:match(heading_pattern)

	if not (hashes and current and rest) then
		return nil
	end

	local index
	for i, state in ipairs(states) do
		if state == current then
			index = i
			break
		end
	end

	if not index then
		return nil
	end

	local next_state = states[(index % #states) + 1]

	return { string.format("%s %s %s", hashes, next_state, rest) }
end

function M.continue_todo(line)
	-- Try checkbox pattern first
	local checkbox_pattern = "(%s*)%- %[.%](.*)"
	local spaces, contents = line:match(checkbox_pattern)

	if spaces then
		-- Found a checkbox bullet
		if contents == "" or contents == " " then
			return { "" } -- Remove empty checkbox bullet
		end
		return { line, spaces .. "- [ ] " }
	end

	-- Try plain bullet pattern
	local plain_pattern = "(%s*)%- (.*)"
	spaces, contents = line:match(plain_pattern)

	if spaces then
		-- Found a plain bullet
		if contents == "" or contents == " " then
			return { "" } -- Remove empty plain bullet
		end
		return { line, spaces .. "- " }
	end

	-- Not a bullet line
	return nil
end

function M.edit_line_at_cursor(modifier_fn, update_cursor)
	local row = vim.fn.line(".") - 1
	local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]
	local new_lines = modifier_fn(line)

	if new_lines then
		vim.api.nvim_buf_set_lines(0, row, row + 1, false, new_lines)
		if update_cursor then
			vim.api.nvim_win_set_cursor(0, { row + #new_lines, #new_lines[#new_lines] })
		end
		return true
	else
		return false
	end
end

local function already_set(buf)
	return vim.b[buf].org_markdown_keys_set == true
end

local function mark_set(buf)
	vim.b[buf].org_markdown_keys_set = true
end
function M.setup_editing_keybinds(bufnr)
	bufnr = bufnr or 0
	if already_set(bufnr) then
		return
	end

	-- NORMAL: <CR> cycles checkbox/status, else fall back to default <CR>
	vim.keymap.set("n", "<CR>", function()
		local did = M.edit_line_at_cursor(function(line)
			return M.cycle_checkbox_inline(line, config.checkbox_states)
				or M.cycle_status_inline(line, config.status_states)
		end)
		if not did then
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
		end
	end, { desc = "org-markdown: cycle or enter", buffer = bufnr })

	-- INSERT: <CR> continues todos, else default <CR>
	vim.keymap.set("i", "<CR>", function()
		local edited = M.edit_line_at_cursor(M.continue_todo, true)
		if not edited then
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
		end
	end, { desc = "org-markdown: continue todo", buffer = bufnr })

	mark_set(bufnr)
end

return M
