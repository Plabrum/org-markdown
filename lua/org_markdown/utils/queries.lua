local config = require("org_markdown.config")

local M = {}

local function is_markdown(file)
	return file:match("%.md$") or file:match("%.markdown$")
end

--- Check if a filepath matches any of the given patterns
--- Supports exact filename matches and simple glob patterns with wildcards
--- @param filepath string Full path to check
--- @param patterns table Array of patterns to match against
--- @param is_exclude_mode boolean If true, empty patterns means exclude none; if false, include all
--- @return boolean true if file matches any pattern
local function matches_patterns(filepath, patterns, is_exclude_mode)
	if not patterns or #patterns == 0 then
		-- Empty patterns: include mode returns true, exclude mode returns false
		return not is_exclude_mode
	end

	-- Get just the filename for matching
	local filename = vim.fn.fnamemodify(filepath, ":t")
	-- Get relative path from home for path-based patterns
	local relative_path = vim.fn.fnamemodify(filepath, ":~:.")

	for _, pattern in ipairs(patterns) do
		-- Exact filename match
		if filename == pattern then
			return true
		end

		-- Substring match for simple patterns without wildcards
		if not pattern:match("[*]") and filename:match(pattern) then
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
---@param opts? { use_cwd?: boolean, include_patterns?: table, ignore_patterns?: table }
---@return string[] markdown_files
function M.find_markdown_files(opts)
	opts = opts or {}
	local use_cwd = opts.use_cwd or false
	local include_patterns = opts.include_patterns or {}
	local ignore_patterns = opts.ignore_patterns or config.refile_heading_ignore or {}

	local roots = {}
	if use_cwd then
		table.insert(roots, vim.uv.cwd())
	else
		for _, path in ipairs(config.refile_paths or {}) do
			local expanded = vim.fn.expand(path)
			table.insert(roots, expanded)
		end
	end

	local all_files = {}
	for _, root in ipairs(roots) do
		scan_dir_sync(root, all_files)
	end

	-- Step 1: Apply include filter (if patterns provided)
	local included_files = {}
	if #include_patterns > 0 then
		for _, filepath in ipairs(all_files) do
			if matches_patterns(filepath, include_patterns, false) then
				table.insert(included_files, filepath)
			end
		end
	else
		-- No include patterns means include all files
		included_files = all_files
	end

	-- Step 2: Apply exclude filter
	local filtered_files = {}
	for _, filepath in ipairs(included_files) do
		if not matches_patterns(filepath, ignore_patterns, true) then
			table.insert(filtered_files, filepath)
		end
	end

	return filtered_files
end

return M
