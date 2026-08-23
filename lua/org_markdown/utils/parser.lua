local M = {}
local compat = require("org_markdown.compat.vim")
local datetime = require("org_markdown.utils.datetime")
local patterns = require("org_markdown.utils.patterns")
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

	-- Links (by id, never by path — see utils/patterns.lua)
	link = patterns.LINK,

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

	return compat.trim(text)
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

--- Parse the first by-ID link in a line.
---
--- Expected format: `[display text](id:<uuid>)`
---
--- @param line string The line to scan (e.g., "see [Notes](id:2b7f...)")
--- @param init number|nil Byte offset to start scanning from (defaults to 1)
--- @return table|nil Link data `{ id, text, from, to }`, where `from`/`to` are
---   the byte range the link occupies, or nil when the line holds no link
function M.parse_link(line, init)
	local from, to, text, id = line:find(M.PATTERNS.link, init)
	if not from then
		return nil
	end

	return { id = id, text = text, from = from, to = to }
end

--- Collect every by-ID link in a line, in the order they appear.
---
--- @param line string
--- @return table List of link data as returned by `parse_link`
function M.parse_links(line)
	local links = {}
	local init = 1

	while true do
		local link = M.parse_link(line, init)
		if not link then
			return links
		end
		table.insert(links, link)
		init = link.to + 1
	end
end

--- Render a link back into its markdown form. Inverse of `parse_link`.
---
--- @param link table Link data `{ id = <uuid>, text = <display text> }`
--- @return string
function M.serialize_link(link)
	return string.format("[%s](%s%s)", link.text or "", patterns.LINK_SCHEME, link.id)
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
