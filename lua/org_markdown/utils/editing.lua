local config = require("org_markdown.config")
local M = {}

function M.cycle_checkbox_in_line(line, states)
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
	return line:gsub(pattern, "- [" .. next_state .. "]", 1)
end

function M.edit_line_at_cursor(modifier_fn)
	local row = vim.fn.line(".") - 1
	local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]
	local new_line = modifier_fn(line)
	if new_line and new_line ~= line then
		vim.api.nvim_buf_set_lines(0, row, row + 1, false, { new_line })
	end
end

function M.setup_editing_keybinds(bufnr)
	vim.keymap.set("n", "<CR>", function()
		M.edit_line_at_cursor(function(line)
			return M.cycle_checkbox_in_line(line, config.checkbox_states)
		end)
	end, {
		desc = "Cycle checkbox state",
		buffer = bufnr,
	})
end

return M
