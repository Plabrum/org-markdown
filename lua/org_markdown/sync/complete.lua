-- Mirroring a source's completion onto the heading promoted from it.
--
-- The external system owns the state of its own items: when Granola's action
-- item is ticked off, or a tracker closes an issue, that item is done whatever
-- the user's markdown still says. Promotion (`sync/promote.lua`) copied the
-- item into planning, so without this the copy lingers as an open TODO long
-- after the thing it names was finished.
--
-- The connection back is the promoted heading's `**Source:**` link, which names
-- the log entry by id. Reading it the other way round -- the backlinks of the
-- entry -- is what finds the heading, so the completion still lands after the
-- heading has been refiled or the entry has moved. Nothing is stored to make
-- this work: the link is the only record.
--
-- DONE in place: the heading is marked DONE and stamped with a completion date,
-- exactly as cycling its status would, and archiving takes it from there.
--
-- All IO goes through the platform shim, so a sync run under the CLI completes
-- headings too.

local backlinks = require("org_markdown.node.backlinks")
local compat = require("org_markdown.compat.vim")
local document = require("org_markdown.utils.document")
local id = require("org_markdown.node.id")
local ingest = require("org_markdown.sync.ingest")
local parser = require("org_markdown.utils.parser")
local platform = require("org_markdown.platform")
local promote = require("org_markdown.sync.promote")

local M = {}

-- The states in which a source reports an item as finished. Both land the
-- heading on DONE: org has one completed state, and an item the source has
-- closed is off the user's plate either way.
M.DONE_STATES = { DONE = true, CANCELLED = true }

--- Whether a pulled item says its source considers it finished.
---@param item table
---@return boolean
function M.reports_done(item)
	if type(item) ~= "table" then
		return false
	end
	return item.done == true or M.DONE_STATES[item.status] == true
end

--- The completion date stamped on a heading, in the org format the rest of the
--- plugin writes properties in (`2026-08-23 Sun`).
---@param date table|nil `{ year, month, day }`, defaulting to today
---@return string
local function completed_at(date)
	local at = date and os.time({ year = date.year, month = date.month, day = date.day, hour = 12 }) or os.time()
	---@diagnostic disable-next-line: return-type-mismatch
	return os.date("%Y-%m-%d %a", at)
end

--- Read a file into lines, dropping the empty field a trailing newline yields.
---@param path string
---@return string[]|nil lines, string|nil err
local function read_lines(path)
	local content, err = platform.fs.read_file(path)
	if not content then
		return nil, "could not read " .. path .. ": " .. (err or "unknown error")
	end

	local lines = compat.split(content, "\n")
	if lines[#lines] == "" then
		table.remove(lines)
	end
	return lines
end

--- Mark one heading DONE and stamp its completion date, leaving the rest of the
--- file as written. A heading already DONE keeps the date it was completed on.
---@param file string
---@param heading string Heading text
---@param date table|nil Completion date, defaulting to today
---@return boolean|nil changed, string|nil err
local function mark_done(file, heading, date)
	local lines, read_err = read_lines(file)
	if not lines then
		return nil, read_err
	end

	local root = document.parse(lines)
	local node = document.find_heading_by_text(root, heading)
	if not node then
		return nil, "no heading matching '" .. heading .. "' in " .. file
	end

	if node:has_state("DONE") then
		return false
	end

	node:set_state("DONE")
	-- `set_state` only stamps a date while archiving is on; a completion the
	-- source reported carries one either way, so the heading can be archived
	-- later and so the user can see when it closed.
	if not node:get_completed_at() then
		node:set_property("COMPLETED_AT", completed_at(date))
	end

	local ok, write_err = platform.fs.write_file(file, table.concat(document.serialize(root), "\n") .. "\n")
	if not ok then
		return nil, "could not write " .. file .. ": " .. (write_err or "unknown error")
	end

	return true
end

--- Complete whatever was promoted out of one ingested entry.
---
--- Only a promoted entry has anything to complete, and only the heading holding
--- that entry's `**Source:**` link counts -- an incidental link to the entry is
--- someone referring to it, not a copy of it in planning.
---@param source table `{ file = <source log>, key = <entry key> }`
---@param opts table|nil `{ date = <completion date>, scan = <queries opts> }`
---@return table[]|nil completed `{ file, heading, line }` per heading marked DONE, string|nil err
function M.entry(source, opts)
	opts = opts or {}

	local log = platform.path.expand(source.file or "")
	local entry, err = ingest.find(log, source.key)
	if not entry then
		return nil, err
	end

	if entry.status ~= ingest.STATUS.PROMOTED then
		return nil, string.format("entry %s is %s, so nothing was promoted from it", entry.key, entry.status)
	end

	local headline = entry.heading and parser.parse_headline(entry.heading)
	if not headline or headline.text == "" then
		return nil, "entry " .. entry.key .. " has no heading"
	end

	-- Promotion minted the entry's id when it wrote the back-link, so reading it
	-- is enough -- an entry with no id has never been linked to.
	local node_id, id_err = id.get({ file = log, heading = headline.text })
	if not node_id then
		return nil, id_err or "entry " .. entry.key .. " has no id"
	end

	local completed = {}
	for _, reference in ipairs(backlinks.to(node_id, opts.scan)) do
		if reference.heading and reference.context:sub(1, #promote.SOURCE_LABEL) == promote.SOURCE_LABEL then
			local changed, mark_err = mark_done(reference.file, reference.heading, opts.date)
			if changed == nil then
				return nil, mark_err
			elseif changed then
				table.insert(completed, { file = reference.file, heading = reference.heading, line = reference.line })
			end
		end
	end

	return completed
end

--- Complete the promoted headings of every item a pull reports as done.
---
--- An item whose entry the log never carried, or never had promoted out of it,
--- has nothing to complete -- that is the ordinary case for an item the source
--- closed before the user ever accepted it, so it is passed over rather than
--- reported as a failure.
---@param path string Source log the items were ingested into
---@param items table[] Items from a plugin's pull
---@param opts table|nil As `M.entry` takes them
---@return table[] completed
function M.sweep(path, items, opts)
	local completed = {}

	for _, item in ipairs(items) do
		if M.reports_done(item) then
			local key = ingest.entry_key(item)
			local marked = key and M.entry({ file = path, key = key }, opts)
			for _, heading in ipairs(marked or {}) do
				table.insert(completed, heading)
			end
		end
	end

	return completed
end

return M
