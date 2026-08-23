local compat = require("org_markdown.compat.vim")
local platform = require("org_markdown.platform")

local M = {}

local DELIMITERS = { ["---"] = "yaml", ["+++"] = "toml" }

--- Strip surrounding quotes and whitespace from a raw field value
--- @param value string
--- @return string
local function clean_value(value)
	return compat.trim(value:match('^"(.-)"$') or value:match("^'(.-)'$") or value)
end

--- Locate the frontmatter block a file opens with
--- @param lines table|nil Array of file lines
--- @return table|nil { format = "yaml"|"toml", delimiter = string, first = number, last = number }
local function find_block(lines)
	if not lines or #lines < 3 then
		return nil
	end

	local delimiter = lines[1]
	local format = DELIMITERS[delimiter]
	if not format then
		return nil
	end

	-- Find closing delimiter
	for i = 2, math.min(#lines, 50) do -- Limit search to first 50 lines
		if lines[i] == delimiter then
			return { format = format, delimiter = delimiter, first = 2, last = i }
		end
	end

	return nil
end

--- Pattern matching a scalar assignment for a key
--- YAML: "key: Value" or "key : Value"
--- TOML: "key = Value" or 'key = "Value"'
--- @param key string
--- @param format string "yaml" or "toml"
--- @return string
local function field_pattern(key, format)
	local separator = format == "toml" and "=" or ":"
	return "^" .. compat.pesc(key) .. "%s*" .. separator .. "%s*(.+)$"
end

--- Parse YAML or TOML frontmatter from lines
--- Supports both YAML (---) and TOML (+++) delimiters
--- @param lines table Array of file lines
--- @return table|nil Frontmatter data (currently just { name = "..." } if found)
function M.parse_frontmatter(lines)
	local name = M.get_field(lines, "name")
	return name and { name = name } or nil
end

--- Read a scalar field from the frontmatter block
--- @param lines table Array of file lines
--- @param key string Field name
--- @return string|nil Field value, nil when absent
function M.get_field(lines, key)
	local block = find_block(lines)
	if not block then
		return nil
	end

	local pattern = field_pattern(key, block.format)
	for i = block.first, block.last - 1 do
		local value = lines[i]:match(pattern)
		if value then
			return clean_value(value)
		end
	end

	return nil
end

--- Set a scalar field in the frontmatter block, returning new lines
--- Replaces the field in place when present, appends it to an existing block
--- otherwise, and opens a YAML block when the file has no frontmatter at all
--- @param lines table Array of file lines
--- @param key string Field name
--- @param value string Field value
--- @return table New array of file lines
function M.set_field(lines, key, value)
	local block = find_block(lines)
	local result = {}
	for i, line in ipairs(lines) do
		result[i] = line
	end

	if not block then
		table.insert(result, 1, "---")
		table.insert(result, 2, string.format("%s: %s", key, value))
		table.insert(result, 3, "---")
		return result
	end

	-- TOML values are quoted; YAML scalars need no quoting for our field values
	local rendered = block.format == "toml" and string.format('%s = "%s"', key, value)
		or string.format("%s: %s", key, value)

	local pattern = field_pattern(key, block.format)
	for i = block.first, block.last - 1 do
		if result[i]:match(pattern) then
			result[i] = rendered
			return result
		end
	end

	table.insert(result, block.last, rendered)
	return result
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
	local base = platform.path.basename(filepath)
	return (base:gsub("%.[^.]*$", ""))
end

return M
