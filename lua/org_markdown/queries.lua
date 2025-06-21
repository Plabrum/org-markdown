local M = {}

function M.get_refile_target()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local current = lines[row]
	current = current:match("^%s*(.*)")
	-- 1. Bullet match
	if current:match("^%s*[-*+] %[[ x%-]%)") or current:match("^%s*[-*+] ") then
		return {
			lines = { current },
			start_line = row,
			end_line = row + 1,
		}
	end

	-- 2. Heading match
	local heading_level, heading_text = current:match("^(#+)%s*(.*)")
	if heading_level then
		local start_line = row
		local end_line = start_line + 1
		local current_level = #heading_level

		while end_line <= #lines do
			local next_line = lines[end_line]
			local next_level = next_line:match("^(#+)")
			if next_level and #next_level <= current_level then
				break
			end
			end_line = end_line + 1
		end

		local range = {}
		for i = start_line, end_line - 1 do
			table.insert(range, lines[i])
		end

		return {
			lines = range,
			start_line = start_line,
			end_line = end_line,
		}
	end

	vim.notify("No bullet or heading detected to refile", vim.log.levels.ERROR)
	return nil
end

return M
