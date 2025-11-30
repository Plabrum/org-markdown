local M = {}

-- Create temporary test file
function M.create_temp_file(content, extension)
	extension = extension or ".md"
	local temp_dir = vim.fn.tempname()
	vim.fn.mkdir(temp_dir, "p")

	local filepath = temp_dir .. "/test" .. extension
	local lines = type(content) == "table" and content or vim.split(content, "\n")

	local file = io.open(filepath, "w")
	file:write(table.concat(lines, "\n"))
	file:close()

	return filepath
end

-- Create temp directory with multiple files
function M.create_temp_workspace(files)
	local temp_dir = vim.fn.tempname()
	vim.fn.mkdir(temp_dir, "p")

	for filename, content in pairs(files) do
		local filepath = temp_dir .. "/" .. filename
		local dir = vim.fn.fnamemodify(filepath, ":h")
		vim.fn.mkdir(dir, "p")

		local lines = type(content) == "table" and content or vim.split(content, "\n")
		local file = io.open(filepath, "w")
		file:write(table.concat(lines, "\n"))
		file:close()
	end

	return temp_dir
end

-- Clean up temp files/dirs
function M.cleanup_temp(path)
	if vim.fn.isdirectory(path) == 1 then
		vim.fn.delete(path, "rf")
	elseif vim.fn.filereadable(path) == 1 then
		vim.fn.delete(path)
	end
end

-- Make file read-only for error testing
function M.make_readonly(filepath)
	vim.fn.setfperm(filepath, "r--r--r--")
end

-- Make file writable again
function M.make_writable(filepath)
	vim.fn.setfperm(filepath, "rw-r--r--")
end

-- Create buffer with content
function M.create_test_buffer(content, filetype)
	local buf = vim.api.nvim_create_buf(false, true)
	local lines = type(content) == "table" and content or vim.split(content, "\n")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	if filetype then
		vim.api.nvim_buf_set_option(buf, "filetype", filetype)
	end
	return buf
end

-- Assert buffer contents match expected
function M.assert_buffer_equals(buf, expected)
	local actual = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local expected_lines = type(expected) == "table" and expected or vim.split(expected, "\n")

	if not vim.deep_equal(actual, expected_lines) then
		error(string.format(
			"Buffer mismatch:\nExpected:\n%s\n\nActual:\n%s",
			table.concat(expected_lines, "\n"),
			table.concat(actual, "\n")
		))
	end
end

return M
