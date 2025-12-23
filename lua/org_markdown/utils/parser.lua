local M = {}
local datetime = require("org_markdown.utils.datetime")
local tree = require("org_markdown.utils.tree")

-- Centralized patterns for org-markdown parsing
M.PATTERNS = {
	-- Structural
	heading = "^(#+)%s+",
	property = "^([A-Z_]+): %[(.+)%]$",

	-- Heading components
	state = "^#+%s+([%u_]+)",
	priority = "%[%#(%u)%]",

	-- Dates (tracked = agenda, untracked = reference only)
	tracked_date = "<(%d%d%d%d%-%d%d%-%d%d)",
	untracked_date = "%[(%d%d%d%d%-%d%d%-%d%d)",
	date_block_tracked = "<%d%d%d%d%-%d%d%-%d%d[^>]*>",
	date_block_untracked = "%[%d%d%d%d%-%d%d%-%d%d[^%]]*%]",
	iso_date = "(%d%d%d%d)%-(%d%d)%-(%d%d)",

	-- Tags
	tag_block = "(:[%w:_-]+:)$",
	tag_item = "([%w_-]+)",

	-- Misc
	priority_bracket = "%[%#.%]%s*",
	double_dash = "%-%-+%s*",
	trailing_tags = "%s+:[%w:_-]+:$",
}

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

function M.parse_state(line)
	local candidate = line:match(M.PATTERNS.state)
	if candidate and get_valid_states()[candidate] then
		return candidate
	end
	return nil
end

function M.parse_priority(line)
	return line:match(M.PATTERNS.priority)
end

function M.parse_text(line)
	-- Remove leading '#' and whitespace
	local text = line:gsub(M.PATTERNS.heading, "")

	-- Remove leading state if valid
	local state = text:match("^([%u_]+)%s+")
	if state and get_valid_states()[state] then
		text = text:gsub("^" .. state .. "%s+", "")
	end

	-- Remove priority, dates, and tags
	text = text:gsub(M.PATTERNS.priority_bracket, "")
	text = text:gsub(M.PATTERNS.date_block_tracked, "")
	text = text:gsub(M.PATTERNS.date_block_untracked, "")
	text = text:gsub(M.PATTERNS.double_dash, "")
	text = text:gsub(M.PATTERNS.trailing_tags, "")

	return vim.trim(text)
end

function M.extract_date(line)
	local tracked = line:match(M.PATTERNS.tracked_date)
	local untracked = line:match(M.PATTERNS.untracked_date)
	return tracked, untracked
end

function M.extract_times(line)
	return datetime.extract_times(line)
end

function M.extract_tags(line)
	local tags = {}
	local tag_block = line:match(M.PATTERNS.tag_block)
	if tag_block then
		for tag in tag_block:gmatch(M.PATTERNS.tag_item) do
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
