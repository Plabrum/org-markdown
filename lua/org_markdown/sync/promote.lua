-- Promotion: lifting one ingested entry out of a source log into a tracked file.
--
-- An ingestion log is raw source material — it sits outside the agenda's scope
-- (`sources/*` is ignored) precisely so an external system can't fill the
-- user's planning with items they never accepted. Promotion is the acceptance:
-- the entry becomes a tracked TODO in a file the agenda does scan, and the log
-- entry is stamped `promoted` so no later sweep proposes it again.
--
-- The promoted heading carries a by-ID link (Epic B) back to the log entry, so
-- the connection outlives both moves: the entry can be refiled and the heading
-- can be refiled, and the link still resolves. The link is what a later sync
-- follows to mirror the source's own state onto the heading.
--
-- This is the trigger-agnostic core: it takes an entry and a destination and
-- performs the promotion. Choosing which entries to promote, and asking the
-- user, belongs to whatever drives it. All IO goes through the platform shim
-- (and `capture/core.lua`), so promotion works under the CLI as well.

local capture_core = require("org_markdown.capture.core")
local config = require("org_markdown.config")
local datetime = require("org_markdown.utils.datetime")
local ingest = require("org_markdown.sync.ingest")
local link = require("org_markdown.node.link")
local parser = require("org_markdown.utils.parser")
local platform = require("org_markdown.platform")

local M = {}

-- What labels the back-link in a promoted heading's body.
M.SOURCE_LABEL = "**Source:**"

--- The markdown of the tracked TODO an entry becomes: the entry's own text,
--- carried over with its priority and tags, given the promoting status and a
--- tracked date so it lands in planning, and a back-link to where it came from.
--- The heading is written at level 1; `insert_under_heading` nests it under the
--- destination heading.
---@param headline table Parsed source entry heading
---@param back_link string Rendered by-ID link to the source entry
---@param opts table|nil `{ status = "TODO", date = <date table|string> }`
---@return string[] lines
function M.format_entry(headline, back_link, opts)
	opts = opts or {}
	local promotion = config.promotion or {}

	local parts = { "#", opts.status or promotion.status or "TODO" }
	if headline.priority then
		parts[#parts + 1] = "[#" .. headline.priority .. "]"
	end
	parts[#parts + 1] = headline.text
	parts[#parts + 1] = datetime.to_org_string(opts.date or datetime.today(true), { tracked = true })
	if headline.tags and #headline.tags > 0 then
		parts[#parts + 1] = ":" .. table.concat(headline.tags, ":") .. ":"
	end

	return {
		table.concat(parts, " "),
		"",
		M.SOURCE_LABEL .. " " .. back_link,
		"",
	}
end

--- Promote one ingested entry into a tracked file.
---
--- Minting the entry's id, writing the tracked TODO and stamping the entry are
--- one operation: the entry is only marked `promoted` once its TODO is on disk,
--- so a failure part-way leaves the entry pending rather than silently lost.
---@param source table `{ file = <source log>, key = <entry key> }`
---@param destination table|nil `{ file, heading? }`, defaulting to `config.promotion`
---@param opts table|nil `{ status, date }` as `M.format_entry` takes them
---@return table|nil promoted `{ key, text, file, heading, link, lines }`, string|nil err
function M.entry(source, destination, opts)
	destination = destination or {}
	local promotion = config.promotion or {}

	local log = platform.path.expand(source.file or "")
	local entry, err = ingest.find(log, source.key)
	if not entry then
		return nil, err
	end

	-- A disposed-of entry has already had its say; promoting it twice would put
	-- a second copy of the same item in the user's planning.
	if entry.status ~= ingest.STATUS.NEW then
		return nil, string.format("entry %s is already %s", entry.key, entry.status)
	end

	local headline = entry.heading and parser.parse_headline(entry.heading)
	if not headline or headline.text == "" then
		return nil, "entry " .. entry.key .. " has no heading to promote"
	end

	-- The back-link names the entry by id, which minting writes into the log.
	local back_link, link_err = link.to_target({ file = log, heading = headline.text })
	if not back_link then
		return nil, link_err
	end

	local file = platform.path.expand(destination.file or promotion.file)
	local heading = destination.heading or promotion.heading
	local lines = M.format_entry(headline, back_link, opts)

	local ok, write_err = capture_core.insert_under_heading(file, heading, lines)
	if not ok then
		return nil, "could not write " .. file .. ": " .. (write_err or "unknown error")
	end

	local stamped, status_err = ingest.set_status(log, entry.key, ingest.STATUS.PROMOTED)
	if not stamped then
		return nil, status_err
	end

	return {
		key = entry.key,
		text = headline.text,
		file = file,
		heading = heading,
		link = back_link,
		lines = lines,
	}
end

return M
