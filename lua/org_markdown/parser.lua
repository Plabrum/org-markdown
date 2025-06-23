local M = {}

--- Parses an org heading line and extracts state, priority, text, and tags.
---
--- Expected format: `# STATE [#P] text :tag1:tag2:`
---
--- @param line string The line to parse (e.g., "# TODO [#A] Finish task :urgent:")
--- @return table|nil state The task state ("TODO" or "IN_PROGRESS"), or nil if invalid
--- @return string|nil priority The priority (e.g., "#A"), or nil if not present
--- @return string|nil text The main heading text without tags or status, or nil if not matched
--- @return string[] tags A list of tag strings (e.g., {"urgent", "work"})
function M.parse_heading(line)
	local state, priority, text = line:match("^#+%s+(%u+)%s+(%[%#%u%])?%s*(.-)%s*$")
	-- if not state or (state ~= "TODO" and state ~= "IN_PROGRESS") then
	-- 	return nil
	-- end
	local tags = {}
	for tag in line:gmatch(":([%w_-]+):") do
		table.insert(tags, tag)
	end
	local pri = priority and priority:match("%[(#%u)%]") or nil
	return state, pri, text, tags
end

function M.extract_date(line)
	local tracked = line:match("<(%d%d%d%d%-%d%d%-%d%d)>")
	local untracked = line:match("%[(%d%d%d%d%-%d%d%-%d%d)%]")
	return tracked, untracked
end

function M.escape_marker(marker, escape_chars)
	if not escape_chars or #escape_chars == 0 then
		return marker
	end

	-- Convert list to lookup table for O(1) access
	local escape_set = {}
	for _, c in ipairs(escape_chars) do
		escape_set[c] = true
	end

	local result = {}
	for i = 1, #marker do
		local c = marker:sub(i, i)
		if escape_set[c] then
			table.insert(result, "%" .. c)
		else
			table.insert(result, c)
		end
	end

	return table.concat(result)
end

return M
