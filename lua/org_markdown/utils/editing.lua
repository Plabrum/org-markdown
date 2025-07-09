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

	return string.format("%s %s %s", hashes, next_state, rest)
end

function M.continue_todo(line)
	local pattern = "(%s*)%- %[.%](.*)"
	local current = { line:match(pattern) }

	-- early return if no checkbox found
	if #current == 0 then
		return nil
	end

	local spaces, contents = unpack(current)

	if contents == "" or contents == " " then
		return { "" }
	end

	return { line, spaces .. "- [ ] " }
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

function M.setup_editing_keybinds(bufnr)
	vim.keymap.set("n", "<CR>", function()
		M.edit_line_at_cursor(function(line)
			local new_lines = M.cycle_checkbox_inline(line, config.checkbox_states)
			if new_lines then
				return new_lines
			else
				return M.cycle_status_inline(line, config.status_states)
			end
		end)
	end, {
		desc = "Cycle checkbox state",
		buffer = bufnr,
	})

	vim.keymap.set("i", "<CR>", function()
		local edited = M.edit_line_at_cursor(M.continue_todo, true)

		if not edited then
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
		end
	end, {
		desc = "extend todo list entries",
		buffer = bufnr,
	})
end

return M
