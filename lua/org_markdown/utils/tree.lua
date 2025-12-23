--- Tree utilities for markdown heading hierarchy operations
--- Provides primitives for structural parsing (level, children, block boundaries)
--- Separate from parser.lua which handles semantic parsing (state, priority, tags, dates)
local M = {}

-- Import patterns from parser (lazy to avoid circular dependency)
local function get_patterns()
	return require("org_markdown.utils.parser").PATTERNS
end

-- ============================================================================
-- Primitives (work with single lines)
-- ============================================================================

--- Get heading level from a line
--- @param line string
--- @return number|nil Level (1-6), or nil if not a heading
function M.get_level(line)
	local hashes = line:match(get_patterns().heading)
	return hashes and #hashes or nil
end

--- Check if a line is a heading
--- @param line string
--- @return boolean
function M.is_heading(line)
	return M.get_level(line) ~= nil
end

-- ============================================================================
-- Structural Operations (work with line arrays)
-- ============================================================================

--- Find where a heading's content ends
--- @param lines table Array of lines
--- @param start_line number Starting line (1-indexed)
--- @param level number Heading level
--- @return number End line (1-indexed, inclusive)
function M.find_end(lines, start_line, level)
	for i = start_line + 1, #lines do
		local line_level = M.get_level(lines[i])
		if line_level and line_level <= level then
			return i - 1
		end
	end
	return #lines
end

--- Find direct children of a heading
--- @param lines table Array of lines
--- @param start_line number Parent heading line (1-indexed)
--- @param level number Parent heading level
--- @return table Array of {line=number, level=number} for direct children
function M.find_children(lines, start_line, level)
	local children = {}
	local end_line = M.find_end(lines, start_line, level)

	for i = start_line + 1, end_line do
		local child_level = M.get_level(lines[i])
		if child_level == level + 1 then
			table.insert(children, { line = i, level = child_level })
		end
	end

	return children
end

--- Get heading block range (heading + all content + sub-headings)
--- @param lines table Array of lines
--- @param start_line number Heading line (1-indexed)
--- @param level number|nil Heading level (will detect if not provided)
--- @return number, number Start line, end line (1-indexed, inclusive)
function M.get_block(lines, start_line, level)
	level = level or M.get_level(lines[start_line])
	if not level then
		return start_line, start_line -- Not a heading
	end

	local end_line = M.find_end(lines, start_line, level)
	return start_line, end_line
end

--- Extract heading block as line array (convenience wrapper)
--- @param lines table Source array of lines
--- @param start_line number Heading line (1-indexed)
--- @param level number|nil Heading level (will detect if not provided)
--- @return table Array of lines in the block
function M.extract_block(lines, start_line, level)
	local start_idx, end_idx = M.get_block(lines, start_line, level)
	local block = {}
	for i = start_idx, end_idx do
		table.insert(block, lines[i])
	end
	return block
end

-- ============================================================================
-- Search Operations
-- ============================================================================

--- Find a heading by text
--- @param lines table Array of lines
--- @param text string Heading text to match (exact match)
--- @return number|nil, number|nil, number|nil line, level, end_line (or nil if not found)
function M.find_heading(lines, text)
	local pattern = "^(#+)%s+" .. vim.pesc(text) .. "%s*$"

	for i, line in ipairs(lines) do
		local hashes = line:match(pattern)
		if hashes then
			local level = #hashes
			local end_line = M.find_end(lines, i, level)
			return i, level, end_line
		end
	end

	return nil, nil, nil
end

return M
