local async = require("org_markdown.utils.async")
local config = require("org_markdown.config")

local M = {}

local function is_markdown(file)
	return file:match("%.md$") or file:match("%.markdown$")
end

--- Check if a filepath should be ignored based on ignore patterns
--- Supports exact filename matches and simple glob patterns with wildcards
--- @param filepath string Full path to check
--- @param ignore_patterns table Array of patterns to match against
--- @return boolean true if file should be ignored
local function should_ignore(filepath, ignore_patterns)
	if not ignore_patterns or #ignore_patterns == 0 then
		return false
	end

	-- Get just the filename for matching
	local filename = vim.fn.fnamemodify(filepath, ":t")
	-- Get relative path from home for path-based patterns
	local relative_path = vim.fn.fnamemodify(filepath, ":~:.")

	for _, pattern in ipairs(ignore_patterns) do
		-- Exact filename match
		if filename == pattern then
			return true
		end

		-- Convert glob pattern to lua pattern
		-- Simple support for * wildcard
		local lua_pattern = pattern:gsub("%*", ".*"):gsub("%-", "%%-"):gsub("%.", "%%.")

		-- Match against filename
		if filename:match("^" .. lua_pattern .. "$") then
			return true
		end

		-- Match against relative path (for patterns like "archive/*")
		if relative_path:match(lua_pattern) then
			return true
		end
	end

	return false
end

local function scan_dir_sync(dir, collected)
	local handle = vim.uv.fs_scandir(dir)
	if not handle then
		return
	end

	while true do
		local name, type_ = vim.uv.fs_scandir_next(handle)
		if not name then
			break
		end

		local full_path = dir .. "/" .. name
		if type_ == "file" and is_markdown(name) then
			table.insert(collected, full_path)
		elseif type_ == "directory" then
			scan_dir_sync(full_path, collected)
		end
	end
end

--- Public sync markdown file finder
---@param opts? { use_cwd?: boolean, ignore_patterns?: table }
---@return string[] markdown_files
function M.find_markdown_files(opts)
	opts = opts or {}
	local use_cwd = opts.use_cwd or false
	local ignore_patterns = opts.ignore_patterns or config.refile_heading_ignore or {}

	local roots = {}
	if use_cwd then
		table.insert(roots, vim.uv.cwd())
	else
		for _, path in ipairs(config.refile_paths or {}) do
			table.insert(roots, vim.fn.expand(path))
		end
	end

	local all_files = {}
	for _, root in ipairs(roots) do
		scan_dir_sync(root, all_files)
	end

	-- Filter out ignored files
	local filtered_files = {}
	for _, filepath in ipairs(all_files) do
		if not should_ignore(filepath, ignore_patterns) then
			table.insert(filtered_files, filepath)
		end
	end

	return filtered_files
end

return M
