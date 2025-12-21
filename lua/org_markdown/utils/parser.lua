local M = {}
local datetime = require("org_markdown.utils.datetime")
local tree = require("org_markdown.utils.tree")

-- Build valid states from config dynamically
local function get_valid_states()
	local config = require("org_markdown.config")
	local states = config.status_states
	local valid = {}
	for _, state in ipairs(states) do
		valid[state] = true
	end
	return valid
end

-- Pre-defined patterns for single-pass parsing
local PATTERNS = {
	state = "^([A-Z_]+)%s+",
	priority = "%[#([A-Z])%]",
	tracked_date = "<([^>]+)>",
	untracked_date = "%[([^%]]+)%]",
	time = "(%d%d):(%d%d)",
	tag_block = ":([%w_-]+):",
}

function M.parse_state(line)
	-- Match the full word after hash+space
	local candidate = line:match("^#+%s+([%u_]+)")
	if candidate and get_valid_states()[candidate] then
		return candidate
	end
	return nil
end

function M.parse_priority(line)
	-- Return just the letter, not "#A"
	return line:match("%[%#(%u)%]")
end

function M.parse_text(line)
	-- Remove leading '#' and whitespace
	local text = line:gsub("^#+%s*", "")

	-- Remove leading state if valid
	local state = text:match("^([%u_]+)%s+")
	if state and get_valid_states()[state] then
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
	-- Extract both tracked and untracked dates independently
	-- (a line can have both, e.g., "TODO task <2025-06-22> [2025-06-23]")
	local tracked = line:match("<(%d%d%d%d%-%d%d%-%d%d)")
	local untracked = line:match("%[(%d%d%d%d%-%d%d%-%d%d)")
	return tracked, untracked
end

function M.extract_times(line)
	-- Wrapper: delegate to datetime module
	return datetime.extract_times(line)
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
--- @return table|nil Parsed headline data with priority as just letter (e.g., "A" not "#A")
function M.parse_headline(line)
	-- Quick check: is it a heading?
	if not tree.is_heading(line) then
		return nil
	end

	-- Extract all components
	local tracked, untracked = M.extract_date(line)
	local start_time, end_time = M.extract_times(line)

	return {
		state = M.parse_state(line),
		priority = M.parse_priority(line), -- Now returns just letter, not "#A"
		tracked = tracked,
		untracked = untracked,
		start_time = start_time,
		end_time = end_time,
		all_day = tracked ~= nil and start_time == nil, -- Only all-day if has date but no time
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

-- Validate time string (HH:MM format)
function M.validate_time(time_str)
	-- Wrapper: delegate to datetime module
	return datetime.validate_time(time_str)
end

return M
