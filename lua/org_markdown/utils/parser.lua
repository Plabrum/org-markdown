local M = {}

local valid_states = {
	TODO = true,
	IN_PROGRESS = true,
	WAITING = true,
	CANCELLED = true,
	DONE = true,
	BLOCKED = true,
}

function M.parse_state(line)
	-- Match the full word after hash+space
	local candidate = line:match("^#+%s+([%u_]+)")
	if candidate and valid_states[candidate] then
		return candidate
	end
	return nil
end

function M.parse_priority(line)
	local raw = line:match("%[%#(%u)%]")
	return raw and "#" .. raw or nil
end

function M.parse_text(line)
	-- Remove leading '#' and whitespace
	local text = line:gsub("^#+%s*", "")

	-- Remove leading state if valid
	local state = text:match("^([%u_]+)%s+")
	if state and valid_states[state] then
		text = text:gsub("^" .. state .. "%s+", "")
	end
	-- Remove leading priority like [#A]
	text = text:gsub("%[%#.%]%s*", "")

	-- Remove all dates with optional day names, times, and ranges
	-- Handles: <YYYY-MM-DD>, <YYYY-MM-DD Mon>, <YYYY-MM-DD Mon 14:00>, <YYYY-MM-DD Mon 14:00-15:00>
	-- Also handles multi-day ranges: <YYYY-MM-DD Mon>--<YYYY-MM-DD Tue>
	text = text:gsub("<%d%d%d%d%-%d%d%-%d%d[^>]*>", "")
	text = text:gsub("%[%d%d%d%d%-%d%d%-%d%d[^%]]*%]", "")
	-- Remove double-dash between date ranges
	text = text:gsub("%-%-+%s*", "")

	-- Remove trailing tags like :tag:tag:
	text = text:gsub("%s+:[%w:_-]+:$", "")

	return vim.trim(text)
end

function M.extract_date(line)
	-- Match date with optional day name and time: <YYYY-MM-DD>, <YYYY-MM-DD Tue>, <YYYY-MM-DD Tue 14:00>
	local tracked = line:match("<(%d%d%d%d%-%d%d%-%d%d)")
	local untracked = line:match("%[(%d%d%d%d%-%d%d%-%d%d)")
	return tracked, untracked
end

function M.extract_times(line)
	-- Match multi-day time range: <YYYY-MM-DD Day HH:MM>--<YYYY-MM-DD Day HH:MM>
	local start_time = line:match("<[^>]*(%d%d:%d%d)>%-%-%<")
	if start_time then
		local end_time = line:match(">%-%-%<[^>]*(%d%d:%d%d)>")
		return start_time, end_time
	end

	-- Match same-day time range: <YYYY-MM-DD Day HH:MM-HH:MM>
	local end_time
	start_time, end_time = line:match("<[^>]*(%d%d:%d%d)%-(%d%d:%d%d)")
	if start_time then
		return start_time, end_time
	end

	-- Match single time: <YYYY-MM-DD Day HH:MM>
	start_time = line:match("<[^>]*(%d%d:%d%d)>")
	return start_time, nil
end

function M.extract_tags(line)
	local tags = {}
	local tag_block = line:match("(:[%w:_-]+:)$")
	if tag_block then
		for tag in tag_block:gmatch("([%w_-]+)") do
			table.insert(tags, tag)
		end
	end
	return tags
end

--- Parses an org heading line and extracts state, priority, text, and tags.
---
--- Expected format: `# STATE [#P] text :tag1:tag2:`
---
--- @param line string The line to parse (e.g., "# TODO [#A] Finish task :urgent:")
--- @return table|nil state The task state ("TODO" or "IN_PROGRESS"), or nil if invalid
function M.parse_headline(line)
	if not line:match("^#+%s") then
		return nil
	end
	local tracked, untracked = M.extract_date(line)
	local start_time, end_time = M.extract_times(line)

	return {
		state = M.parse_state(line),
		priority = M.parse_priority(line),
		tracked = tracked,
		untracked = untracked,
		start_time = start_time,
		end_time = end_time,
		all_day = start_time == nil,
		text = M.parse_text(line),
		tags = M.extract_tags(line),
	}
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
