local M = {}

--- Parse YAML or TOML frontmatter from lines
--- Supports both YAML (---) and TOML (+++) delimiters
--- @param lines table Array of file lines
--- @return table|nil Frontmatter data (currently just { name = "..." } if found)
function M.parse_frontmatter(lines)
	if not lines or #lines < 3 then
		return nil
	end

	local first_line = lines[1]
	local delimiter, format

	if first_line == "---" then
		delimiter = "---"
		format = "yaml"
	elseif first_line == "+++" then
		delimiter = "+++"
		format = "toml"
	else
		return nil
	end

	-- Find closing delimiter
	local end_idx = nil
	for i = 2, math.min(#lines, 50) do -- Limit search to first 50 lines
		if lines[i] == delimiter then
			end_idx = i
			break
		end
	end

	if not end_idx then
		return nil
	end

	-- Extract frontmatter content (between delimiters)
	local frontmatter = {}
	for i = 2, end_idx - 1 do
		local line = lines[i]

		-- Parse name field (works for both YAML and TOML)
		-- YAML: "name: Value" or "name : Value"
		-- TOML: "name = Value" or 'name = "Value"'
		local name_yaml = line:match("^name%s*:%s*(.+)$")
		local name_toml = line:match("^name%s*=%s*(.+)$")

		if name_yaml then
			-- Remove quotes if present
			frontmatter.name = name_yaml:match('^"(.-)"$') or name_yaml:match("^'(.-)'$") or name_yaml
			frontmatter.name = vim.trim(frontmatter.name)
		elseif name_toml then
			-- Remove quotes if present
			frontmatter.name = name_toml:match('^"(.-)"$') or name_toml:match("^'(.-)'$") or name_toml
			frontmatter.name = vim.trim(frontmatter.name)
		end
	end

	return frontmatter.name and frontmatter or nil
end

--- Get display name for a file (from frontmatter or filename fallback)
--- @param filepath string Absolute path to markdown file
--- @param lines table|nil Optional pre-read lines (for performance)
--- @return string Display name (frontmatter name or filename without extension)
function M.get_display_name(filepath, lines)
	-- Read file if lines not provided
	if not lines then
		local utils = require("org_markdown.utils.utils")
		lines = utils.read_lines(filepath)
	end

	-- Try frontmatter first
	local frontmatter = M.parse_frontmatter(lines)
	if frontmatter and frontmatter.name then
		return frontmatter.name
	end

	-- Fallback to filename without extension
	return vim.fn.fnamemodify(filepath, ":t:r")
end

return M
