local config = require("org_markdown.config")
local M = {}

function M.cycle_checkbox()
	vim.notify("Cycle checkbox state", vim.log.levels.INFO)
	local line_num = vim.fn.line(".") - 1
	local line = vim.api.nvim_buf_get_lines(0, line_num, line_num + 1, false)[1]
	if not line then
		return
	end

	local pattern = "%- %[(.-)%]"
	local current = line:match(pattern)
	if not current then
		return
	end

	current = vim.trim(current)
	local states = config.checkbox_states
	local index = nil

	for i, state in ipairs(states) do
		if state == current then
			index = i
			break
		end
	end

	if not index then
		return
	end

	local next_state = states[(index % #states) + 1]
	local new_line = line:gsub("%- %[(.-)%]", "- [" .. next_state .. "]", 1)
	vim.api.nvim_buf_set_lines(0, line_num, line_num + 1, false, { new_line })
end

function M.setup_editing_keybinds(bufnr)
	vim.keymap.set("n", "<CR>", M.cycle_checkbox, {
		desc = "Cycle checkbox state",
		buffer = bufnr,
	})
end

return M
