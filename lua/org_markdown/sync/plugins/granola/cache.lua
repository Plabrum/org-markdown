-- Reading meetings and their action items out of Granola's local cache.
--
-- Granola keeps everything it knows on disk in `cache-v3.json`: a JSON object
-- whose single `cache` key holds another JSON document *as a string*. Inside
-- that lives `state.documents` (one entry per meeting) and
-- `state.documentPanels` (the generated summary panels for each meeting).
--
-- Notes come in two shapes -- ProseMirror node trees and plain markdown -- so
-- everything is flattened to markdown-ish lines first and action items are
-- extracted from those lines, whichever shape they arrived in.

local compat = require("org_markdown.compat.vim")

local M = {}

-- Bullets, with or without a checkbox marker.
local BULLET = "^%s*[-*+]%s+(.+)$"
local CHECKBOX = "^%[([^%]])%]%s*(.+)$"

--- Decode a JSON string, tolerating the garbage a half-written cache can hold.
---@param str string
---@return table|nil
local function decode(str)
	local ok, value = pcall(vim.json.decode, str)
	if not ok or type(value) ~= "table" then
		return nil
	end
	return value
end

--- Treat JSON null (`vim.NIL`) as absent, so callers can test fields normally.
---@param value any
---@return any
local function present(value)
	if value == nil or value == vim.NIL then
		return nil
	end
	return value
end

--- Epoch seconds for an ISO-8601 timestamp. Granola writes both the `Z` and
--- the `+HH:MM` offset form; both are normalised to UTC.
---@param iso any
---@return number|nil
function M.parse_timestamp(iso)
	if type(iso) ~= "string" then
		return nil
	end

	local year, month, day, hour, min, sec = iso:match("^(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")
	if not year then
		return nil
	end

	local parts = {
		year = tonumber(year),
		month = tonumber(month),
		day = tonumber(day),
		hour = tonumber(hour),
		min = tonumber(min),
		sec = tonumber(sec),
		isdst = false,
	}

	-- os.time reads the table as local time; correct by the zone offset in
	-- force at that instant to get a UTC epoch.
	local as_local = os.time(parts)
	local utc = os.date("!*t", as_local)
	utc.isdst = false
	local epoch = as_local + os.difftime(as_local, os.time(utc))

	-- Then undo the timestamp's own offset, if it carries one.
	local sign, off_hour, off_min = iso:match("([+-])(%d%d):?(%d%d)$")
	if sign then
		local offset = tonumber(off_hour) * 3600 + tonumber(off_min) * 60
		epoch = epoch + (sign == "+" and -offset or offset)
	end

	return epoch
end

--- All text carried by a ProseMirror node and its descendants.
---@param node table
---@return string
local function text_of(node)
	if type(node) ~= "table" then
		return ""
	end
	if type(node.text) == "string" then
		return node.text
	end

	local parts = {}
	for _, child in ipairs(node.content or {}) do
		parts[#parts + 1] = text_of(child)
	end
	return table.concat(parts)
end

--- Flatten a ProseMirror node tree into markdown-ish lines: headings keep their
--- level, list items become bullets (carrying their checkbox state when they
--- have one), everything else becomes a plain line.
---@param node table|nil
---@param lines? string[]
---@param in_list? boolean
---@return string[] lines
function M.flatten(node, lines, in_list)
	lines = lines or {}
	if type(node) ~= "table" then
		return lines
	end

	local node_type = node.type
	local attrs = node.attrs or {}

	if node_type == "heading" then
		lines[#lines + 1] = string.rep("#", attrs.level or 1) .. " " .. text_of(node)
	elseif node_type == "paragraph" then
		local text = text_of(node)
		if text ~= "" then
			lines[#lines + 1] = in_list and ("- " .. text) or text
		end
	elseif node_type == "listItem" or node_type == "list_item" or node_type == "taskItem" then
		local marker = "- "
		if present(attrs.checked) ~= nil then
			marker = attrs.checked and "- [x] " or "- [ ] "
		end

		-- Only the item's own first line gets the bullet; nested blocks below it
		-- flatten as ordinary lines.
		local before = #lines
		for _, child in ipairs(node.content or {}) do
			M.flatten(child, lines, false)
		end
		if lines[before + 1] then
			lines[before + 1] = marker .. lines[before + 1]
		end
	else
		for _, child in ipairs(node.content or {}) do
			M.flatten(child, lines, in_list)
		end
	end

	return lines
end

--- Does a heading name an action-item section?
---@param text string
---@param headings string[]
---@return boolean
local function is_action_heading(text, headings)
	local normalized = text:lower()
	for _, heading in ipairs(headings) do
		if normalized:find(heading:lower(), 1, true) then
			return true
		end
	end
	return false
end

--- Extract the action items from a meeting's markdown lines. Two things count:
--- an unchecked checkbox anywhere in the notes, and any bullet under a heading
--- the config names as an action-item section -- which is where Granola's
--- generated summary puts them, unmarked. An item already ticked off in the
--- meeting is not an action item any more, so it is skipped.
---@param lines string[]
---@param headings string[] Heading texts that open an action-item section
---@return string[] items Item texts, in the order they appear
function M.action_items(lines, headings)
	local items, seen = {}, {}
	local in_section = false

	for _, line in ipairs(lines) do
		local hashes, heading_text = line:match("^(#+)%s+(.*)$")
		if hashes then
			in_section = is_action_heading(heading_text, headings)
		else
			local bullet = line:match(BULLET)
			if bullet then
				local box, text = bullet:match(CHECKBOX)
				local unchecked = box == " "
				if (box and unchecked) or (not box and in_section) then
					local item = compat.trim(text or bullet)
					if item ~= "" and not seen[item] then
						seen[item] = true
						items[#items + 1] = item
					end
				end
			end
		end
	end

	return items
end

--- The generated summary panels for a meeting, flattened to markdown lines.
---@param state table
---@param id string
---@return string[] lines
local function panel_lines(state, id)
	local lines = {}
	local panels = present((state.documentPanels or {})[id])
	if type(panels) ~= "table" then
		return lines
	end

	for _, panel in pairs(panels) do
		if type(panel) == "table" then
			M.flatten(present(panel.content), lines)
		end
	end

	return lines
end

--- A meeting's own notes, whichever shape Granola stored them in.
---@param doc table
---@return string[] lines
local function note_lines(doc)
	local markdown = present(doc.notes_markdown)
	if type(markdown) == "string" and markdown ~= "" then
		local lines = {}
		for line in (markdown .. "\n"):gmatch("(.-)\n") do
			lines[#lines + 1] = line
		end
		return lines
	end

	return M.flatten(present(doc.notes))
end

--- When a meeting finished: its calendar event's end time, or -- for a note
--- taken outside any event -- when it was last written to.
---@param doc table
---@return number|nil
local function ended_at(doc)
	local event = present(doc.google_calendar_event)
	if type(event) == "table" then
		local finish = present(event["end"])
		if type(finish) == "table" then
			local epoch = M.parse_timestamp(present(finish.dateTime) or present(finish.date))
			if epoch then
				return epoch
			end
		end
	end

	return M.parse_timestamp(present(doc.updated_at) or present(doc.created_at))
end

--- Every finished, undeleted meeting in the cache, oldest first. A meeting is
--- finished once its end time has passed -- notes are still being taken while
--- it runs, so ingesting earlier would capture a half-written list.
---@param state table Decoded cache state
---@param opts? { now?: number, since?: number }
---@return table[] meetings `{ id, title, date, ended_at, lines }`
function M.meetings(state, opts)
	opts = opts or {}
	local now = opts.now or os.time()

	local meetings = {}
	for id, doc in pairs(present(state.documents) or {}) do
		local finished = type(doc) == "table" and present(doc.deleted_at) == nil and ended_at(doc)
		if finished and finished <= now and (not opts.since or finished >= opts.since) then
			local started = M.parse_timestamp(present(doc.created_at)) or finished
			local date = os.date("*t", started)

			local lines = panel_lines(state, id)
			for _, line in ipairs(note_lines(doc)) do
				lines[#lines + 1] = line
			end

			meetings[#meetings + 1] = {
				id = id,
				title = present(doc.title) or "Untitled meeting",
				date = { year = date.year, month = date.month, day = date.day },
				ended_at = finished,
				lines = lines,
			}
		end
	end

	-- Oldest first, so the ingestion log reads in the order meetings happened.
	-- The cache is a map, so ties are broken by id to keep the order stable.
	table.sort(meetings, function(a, b)
		if a.ended_at == b.ended_at then
			return a.id < b.id
		end
		return a.ended_at < b.ended_at
	end)

	return meetings
end

--- Decode a cache file's contents. The outer document holds the real state as
--- a JSON string under `cache`; a state table passed straight through is
--- accepted too, so tests and future formats don't need the wrapper.
---@param content string
---@return table|nil state, string|nil err
function M.decode_cache(content)
	local outer = decode(content)
	if not outer then
		return nil, "could not decode Granola cache"
	end

	local inner = present(outer.cache)
	if type(inner) == "string" then
		outer = decode(inner)
		if not outer then
			return nil, "could not decode Granola cache"
		end
	elseif type(inner) == "table" then
		outer = inner
	end

	local state = present(outer.state) or outer
	if type(present(state.documents)) ~= "table" then
		return nil, "Granola cache holds no meetings"
	end

	return state
end

--- Read and decode the cache file.
---@param path string
---@return table|nil state, string|nil err
function M.load(path)
	local content = require("org_markdown.platform").fs.read_file(path)
	if not content then
		return nil, "Granola cache not found at " .. path
	end

	return M.decode_cache(content)
end

return M
