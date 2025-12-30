-- Pattern matching utilities for glob and path patterns
local M = {}

--- Convert a glob pattern to a Lua pattern
--- Supports:
---   * -> matches any characters except /
---   ** -> matches any characters including /
--- @param glob_pattern string Glob pattern (e.g., "~/org/**/*.md")
--- @return string Lua pattern
function M.glob_to_lua_pattern(glob_pattern)
	-- Escape special Lua pattern characters except * and ?
	local lua_pattern = glob_pattern:gsub("([%.%+%-%[%]%(%)%$%^%%%?])", "%%%1")

	-- Replace glob wildcards
	lua_pattern = lua_pattern:gsub("%*%*", "DOUBLESTAR") -- Protect ** first
	lua_pattern = lua_pattern:gsub("%*", "[^/]*") -- * matches anything except /
	lua_pattern = lua_pattern:gsub("DOUBLESTAR", ".*") -- ** matches anything including /

	-- Anchor to start of string
	lua_pattern = "^" .. lua_pattern

	return lua_pattern
end

--- Check if a file path matches any of the given patterns
--- @param filepath string Absolute file path to check
--- @param patterns table List of glob patterns
--- @return boolean True if filepath matches any pattern
function M.matches_any_pattern(filepath, patterns)
	if not patterns or #patterns == 0 then
		return false
	end

	-- Resolve symlinks to get canonical path
	local expanded_path = vim.fn.resolve(vim.fn.fnamemodify(filepath, ":p"))

	for _, pattern in ipairs(patterns) do
		-- Expand ~ but DON'T expand glob wildcards (* and **)
		-- gsub replaces ~ at start with home directory
		local expanded_pattern = pattern:gsub("^~", vim.fn.expand("~"))
		-- Make absolute path and resolve symlinks (e.g., ~/org → iCloud path)
		expanded_pattern = vim.fn.resolve(vim.fn.fnamemodify(expanded_pattern, ":p"))
		local lua_pattern = M.glob_to_lua_pattern(expanded_pattern)

		if expanded_path:match(lua_pattern) then
			return true
		end
	end

	return false
end

return M
