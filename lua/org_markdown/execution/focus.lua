-- Focus blocks: time reserved on the calendar for work not yet named.
--
-- The calendar holds two kinds of thing. A meeting is an appointment: it is what
-- it says it is. A focus block is a commitment to work at a time, made before
-- deciding what the work is -- it carries no task until it begins, when one is
-- bound to it (that binding is the commencement step, not this module).
--
-- REPRESENTATION: an ordinary calendar heading -- a tracked date, usually with a
-- time span -- tagged with the focus tag and carrying no task state:
--
--   # Focus <2026-08-23 Sun 09:00-11:00> :focus:
--
-- The tag is what makes a block a block, so it stays a first-class calendar
-- entry: it lands in calendar views, notifications and the CLI's projection like
-- any other dated heading, with no parallel store to keep in step. The absence
-- of a state is what makes it task-less: a block that reads as TODO would be
-- work, and a block is a container for work rather than work itself. `kind()`
-- reads all of this back, so a caller can tell block from meeting from task
-- without re-deriving the convention.
--
-- Everything here is vim-free and writes through the platform shim, so blocks
-- can be created and read under the CLI as well as in-editor.

local capture_core = require("org_markdown.capture.core")
local config = require("org_markdown.config")
local datetime = require("org_markdown.utils.datetime")
local pipeline = require("org_markdown.agenda.pipeline")
local platform = require("org_markdown.platform")

local M = {}

M.FOCUS = "focus"
M.MEETING = "meeting"
M.TASK = "task"

--- The tag marking a heading as a focus block.
---@return string
function M.tag()
	return (config.focus or {}).tag or M.FOCUS
end

--- The fields `kind` reads, from either an agenda item (`title`, `date`) or a
--- parsed headline (`text`, `tracked`), so both pass through unchanged.
---@param item table
---@return table `{ title, date, state, tags }`
local function fields(item)
	return {
		title = item.title or item.text,
		date = item.date or item.tracked,
		state = item.state,
		tags = item.tags or {},
	}
end

---@param tags string[]
---@param tag string
---@return boolean
local function has_tag(tags, tag)
	for _, candidate in ipairs(tags) do
		if candidate == tag then
			return true
		end
	end
	return false
end

--- What a heading is, as the calendar means it: a focus block, a meeting, a
--- task, or nothing calendar-shaped at all (nil for an undated, stateless
--- heading). A dated task stays a task -- it is work with a date on it, not an
--- appointment.
---@param item table agenda item or parsed headline
---@return string|nil kind one of `M.FOCUS`, `M.MEETING`, `M.TASK`
function M.kind(item)
	local f = fields(item)

	if f.date and not f.state and has_tag(f.tags, M.tag()) then
		return M.FOCUS
	end
	if f.state then
		return M.TASK
	end
	if f.date then
		return M.MEETING
	end

	return nil
end

--- Whether a heading is a focus block.
---@param item table
---@return boolean
function M.is_focus(item)
	return M.kind(item) == M.FOCUS
end

--- Whether a heading is a meeting -- a dated calendar entry that is not a block.
---@param item table
---@return boolean
function M.is_meeting(item)
	return M.kind(item) == M.MEETING
end

--- Read a time span written the way a user says one: `09:00-11:00`, or a bare
--- `09:00` for a block with no stated end.
---@param text string
---@return string|nil start_time, string|nil end_time_or_err
function M.parse_span(text)
	local start_time, end_time = text:match("^%s*(%d%d:%d%d)%s*%-%s*(%d%d:%d%d)%s*$")
	if not start_time then
		start_time = text:match("^%s*(%d%d:%d%d)%s*$")
	end

	if not start_time or not datetime.validate_time(start_time) then
		return nil, "`" .. text .. "` is not a time span (HH:MM or HH:MM-HH:MM)"
	end
	if end_time and not datetime.validate_time(end_time) then
		return nil, "`" .. text .. "` is not a time span (HH:MM or HH:MM-HH:MM)"
	end

	return start_time, end_time
end

--- The markdown one focus block is: a titled heading with a tracked date, its
--- time span, and the focus tag -- and deliberately no state. Written at level
--- 1; `insert_under_heading` nests it under a destination heading.
---@param block table `{ title?, date?, start_time?, end_time? }`
---@return string[] lines
function M.format(block)
	local focus = config.focus or {}
	local parts = { "#", block.title or focus.title or "Focus" }

	parts[#parts + 1] = datetime.to_org_string(block.date or datetime.today(true), {
		tracked = true,
		time = block.start_time,
		end_time = block.end_time,
	})
	parts[#parts + 1] = ":" .. M.tag() .. ":"

	return { table.concat(parts, " "), "" }
end

--- Create a focus block on the calendar.
---@param block table `{ title?, date?, start_time?, end_time? }`, date defaulting to today
---@param destination table|nil `{ file, heading? }`, defaulting to `config.focus`
---@return table|nil created `{ title, date, start_time, end_time, file, heading, lines }`, string|nil err
function M.create(block, destination)
	block = block or {}
	destination = destination or {}
	local focus = config.focus or {}

	for _, time in ipairs({ block.start_time or false, block.end_time or false }) do
		if time and not datetime.validate_time(time) then
			return nil, "`" .. tostring(time) .. "` is not a time (HH:MM)"
		end
	end

	-- An end with no start has nothing to bound, and would render as a date with
	-- a stray time hanging off it.
	if block.end_time and not block.start_time then
		return nil, "a focus block with an end time needs a start time"
	end

	local file = platform.path.expand(destination.file or focus.file)
	local heading = destination.heading or focus.heading
	local lines = M.format(block)

	local ok, err = capture_core.insert_under_heading(file, heading, lines)
	if not ok then
		return nil, "could not write " .. file .. ": " .. (err or "unknown error")
	end

	return {
		title = block.title or focus.title or "Focus",
		date = datetime.to_iso_string(block.date or datetime.today(true)),
		start_time = block.start_time,
		end_time = block.end_time,
		file = file,
		heading = heading,
		lines = lines,
	}
end

--- Every focus block in scope, read back off the calendar, earliest first. A
--- block nested under another heading counts like any other calendar entry, so
--- children are walked too.
---@param opts table|nil `{ date = <ISO date>, file_patterns = string[] }`
---@return table[] blocks agenda items
function M.blocks(opts)
	opts = opts or {}
	local found = {}

	local function collect(item)
		if M.is_focus(item) and (not opts.date or item.date == opts.date) then
			table.insert(found, item)
		end
		for _, child in ipairs(item.children or {}) do
			collect(child)
		end
	end

	for _, item in ipairs(pipeline.scan_files(opts.file_patterns).calendar) do
		collect(item)
	end

	table.sort(found, function(a, b)
		if a.date ~= b.date then
			return a.date < b.date
		end
		return (a.start_time or "99:99") < (b.start_time or "99:99")
	end)

	return found
end

--- Reserve a focus block from the editor, asking for the span when none was
--- given, and reporting the block that was written.
---@param span string|nil time span as `M.parse_span` reads it, e.g. "09:00-11:00"
function M.add(span)
	if not span or span == "" then
		vim.ui.input({ prompt = "Focus block (HH:MM-HH:MM): " }, function(input)
			if input and input ~= "" then
				M.add(input)
			end
		end)
		return
	end

	local start_time, end_time = M.parse_span(span)
	if not start_time then
		vim.notify(end_time, vim.log.levels.WARN)
		return
	end

	local created, err = M.create({ start_time = start_time, end_time = end_time })
	if not created then
		vim.notify(err, vim.log.levels.WARN)
		return
	end

	vim.notify(created.lines[1]:gsub("^#%s+", ""), vim.log.levels.INFO)
end

return M
