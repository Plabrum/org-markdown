-- Append-only ingestion: the sync mode for source logs.
--
-- The ordinary sync mode rewrites a plugin's file from scratch on every pull,
-- which is right for a mirror of an external source but wrong for ingestion: an
-- ingestion log accumulates what a source reported over time, and an entry that
-- has already landed must never move or be rewritten (a promotion sweep, and
-- the user, both edit those entries in place).
--
-- So entries are only ever appended, and re-running a pull must not duplicate
-- what is already there. Each entry carries a stable key on the line below its
-- heading:
--
--   ## TODO Send the deck <2026-08-23>
--   <!-- key: granola:9f21::Send the deck -->
--
-- The key is what a re-run compares against: keys already present in the file
-- are skipped, so an entry appears exactly once no matter how often the source
-- replays it. Plugins that have a stable id of their own supply it as
-- `item.key`; otherwise the key is derived from the fields that identify an
-- item to a human (title, date, time).
--
-- All IO goes through the platform shim, so ingestion works under the CLI too.

local compat = require("org_markdown.compat.vim")
local platform = require("org_markdown.platform")

local M = {}

--- Render the key marker line stamped under an entry's heading.
---@param key string
---@return string
function M.format_key(key)
	return string.format("<!-- key: %s -->", key)
end

--- Read a key marker back out of a line. Returns nil for any other line.
---@param line string
---@return string|nil key
function M.parse_key(line)
	if not line then
		return nil
	end
	return line:match("^%s*<!%-%- key: (.-) %-%->%s*$")
end

--- Format a date table as the `YYYY-MM-DD` part of a derived key.
---@param date table
---@return string
local function format_date(date)
	return string.format("%04d-%02d-%02d", date.year, date.month, date.day)
end

--- Stable identity of an item. A plugin-supplied `key` wins; otherwise the key
--- is built from the item's identifying fields. Whitespace is collapsed so the
--- key always fits on its marker line.
---@param item table
---@return string|nil key
function M.entry_key(item)
	if type(item) ~= "table" then
		return nil
	end

	local key = item.key
	if key == nil or key == "" then
		local parts = { item.title or "" }
		local date = item.start_date or item.due_date
		if date then
			parts[#parts + 1] = format_date(date)
		end
		if item.start_time then
			parts[#parts + 1] = item.start_time
		end
		key = table.concat(parts, "::")
	end

	key = compat.trim(tostring(key):gsub("%s+", " "))
	if key == "" then
		return nil
	end
	return key
end

--- Every key already recorded in an ingestion log. A missing file has none.
---@param path string
---@return table<string, boolean> keys
function M.existing_keys(path)
	local keys = {}

	local content = platform.fs.read_file(path)
	if not content then
		return keys
	end

	for line in content:gmatch("[^\n]+") do
		local key = M.parse_key(line)
		if key then
			keys[key] = true
		end
	end

	return keys
end

--- Append entries that are not already in the log, in one write. Each entry is
--- `{ key = <string>, lines = <markdown lines> }`; its key marker is stamped
--- under the heading. Entries already present, and repeats within the batch,
--- are skipped, so the operation is idempotent.
---@param path string
---@param entries { key: string, lines: string[] }[]
---@return string[]|nil appended, string|nil err
function M.append_entries(path, entries)
	local seen = M.existing_keys(path)

	local appended, lines = {}, {}
	for _, entry in ipairs(entries) do
		if entry.key and entry.key ~= "" and not seen[entry.key] then
			seen[entry.key] = true
			appended[#appended + 1] = entry.key

			-- The marker sits below the heading, so the entry still reads as an
			-- ordinary markdown block.
			lines[#lines + 1] = entry.lines[1]
			lines[#lines + 1] = M.format_key(entry.key)
			for i = 2, #entry.lines do
				lines[#lines + 1] = entry.lines[i]
			end
		end
	end

	if #appended == 0 then
		return appended
	end

	-- Start on a fresh line when the log doesn't already end on one, so an
	-- appended entry can never be glued onto the last line written.
	local content = platform.fs.read_file(path)
	local prefix = (content and content ~= "" and not content:match("\n$")) and "\n" or ""

	local ok, err = platform.fs.append_file(path, prefix .. table.concat(lines, "\n") .. "\n")
	if not ok then
		return nil, "could not append to " .. path .. ": " .. (err or "unknown error")
	end

	return appended
end

return M
