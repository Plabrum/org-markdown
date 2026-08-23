-- Append-only ingestion: the sync mode for source logs.
--
-- The ordinary sync mode rewrites a plugin's file from scratch on every pull,
-- which is right for a mirror of an external source but wrong for ingestion: an
-- ingestion log accumulates what a source reported over time, and an entry that
-- has already landed must never move or be rewritten (a promotion sweep, and
-- the user, both edit those entries in place).
--
-- So entries are only ever appended, and re-running a pull must not duplicate
-- what is already there. Each entry carries a marker on the line below its
-- heading, holding a stable key and the entry's promotion status:
--
--   ## TODO Send the deck <2026-08-23>
--   <!-- key: granola:9f21::Send the deck status: new -->
--
-- The key is what a re-run compares against: keys already present in the file
-- are skipped, so an entry appears exactly once no matter how often the source
-- replays it. Plugins that have a stable id of their own supply it as
-- `item.key`; otherwise the key is derived from the fields that identify an
-- item to a human (title, date, time).
--
-- The status is what a promotion sweep compares against: an entry lands as
-- `new`, and the sweep marks it `promoted` once it has been moved into the
-- user's files or `rejected` once it has been dismissed. Either disposition
-- takes the entry out of what a later sweep proposes, and because the marker
-- lives in the log rather than in the sweep, it survives re-sync — the entry is
-- never re-appended, so its status is never reset.
--
-- All IO goes through the platform shim, so ingestion works under the CLI too.

local compat = require("org_markdown.compat.vim")
local platform = require("org_markdown.platform")
local tree = require("org_markdown.utils.tree")

local M = {}

--- The dispositions an ingested entry can carry.
M.STATUS = { NEW = "new", PROMOTED = "promoted", REJECTED = "rejected" }

--- Render the marker line stamped under an entry's heading.
---@param key string
---@param status string|nil Defaults to `new`
---@return string
function M.format_marker(key, status)
	return string.format("<!-- key: %s status: %s -->", key, status or M.STATUS.NEW)
end

--- Read a marker back out of a line. Returns nil for any other line.
---@param line string
---@return { key: string, status: string }|nil
function M.parse_marker(line)
	if not line then
		return nil
	end

	local body = line:match("^%s*<!%-%- key: (.-) %-%->%s*$")
	if not body then
		return nil
	end

	-- A log written before entries carried a status reads as untouched.
	local key, status = body:match("^(.-) status: ([%a]+)$")
	return { key = key or body, status = status or M.STATUS.NEW }
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

--- Every entry recorded in an ingestion log, in file order. A missing file has
--- none. `line` is where the entry's marker sits, so a caller can rewrite it,
--- and `heading` is the heading the marker was stamped under, so a caller
--- promoting the entry knows what it says. The heading is found by looking back
--- from the marker rather than assuming the line above it: minting the entry's
--- id (Epic B) puts a property line between the two.
---@param path string
---@return { key: string, status: string, line: integer, heading: string|nil, heading_line: integer|nil }[]
function M.entries(path)
	local entries = {}

	local content = platform.fs.read_file(path)
	if not content then
		return entries
	end

	local heading, heading_line = nil, nil
	for i, line in ipairs(compat.split(content, "\n")) do
		if tree.is_heading(line) then
			heading, heading_line = line, i
		end

		local marker = M.parse_marker(line)
		if marker then
			entries[#entries + 1] = {
				key = marker.key,
				status = marker.status,
				line = i,
				heading = heading,
				heading_line = heading_line,
			}
		end
	end

	return entries
end

--- The entry a key names, or nil when the log has never carried it.
---@param path string
---@param key string
---@return table|nil entry, string|nil err
function M.find(path, key)
	for _, entry in ipairs(M.entries(path)) do
		if entry.key == key then
			return entry
		end
	end
	return nil, "no ingested entry with key " .. tostring(key) .. " in " .. path
end

--- Every key already recorded in an ingestion log. A missing file has none.
---@param path string
---@return table<string, boolean> keys
function M.existing_keys(path)
	local keys = {}
	for _, entry in ipairs(M.entries(path)) do
		keys[entry.key] = true
	end
	return keys
end

--- The status recorded for a key, or nil if the log has never carried it.
---@param path string
---@param key string
---@return string|nil status
function M.status_of(path, key)
	local entry = M.find(path, key)
	return entry and entry.status or nil
end

--- The entries a sweep has yet to dispose of: everything still marked `new`.
---@param path string
---@return { key: string, status: string, line: integer }[]
function M.pending(path)
	local pending = {}
	for _, entry in ipairs(M.entries(path)) do
		if entry.status == M.STATUS.NEW then
			pending[#pending + 1] = entry
		end
	end
	return pending
end

--- Record a sweep's disposition of one entry by rewriting its marker in place.
--- Only that line changes, so the log's prior entries stay exactly as written.
---@param path string
---@param key string
---@param status string One of `M.STATUS`
---@return boolean|nil ok, string|nil err
function M.set_status(path, key, status)
	if not compat.tbl_contains({ M.STATUS.NEW, M.STATUS.PROMOTED, M.STATUS.REJECTED }, status) then
		return nil, "unknown ingestion status: " .. tostring(status)
	end

	local content = platform.fs.read_file(path)
	if not content then
		return nil, "could not read " .. path
	end

	local lines = compat.split(content, "\n")
	local found = false
	for i, line in ipairs(lines) do
		local marker = M.parse_marker(line)
		if marker and marker.key == key then
			lines[i] = M.format_marker(key, status)
			found = true
			break
		end
	end

	if not found then
		return nil, "no ingested entry with key " .. key .. " in " .. path
	end

	local ok, err = platform.fs.write_file(path, table.concat(lines, "\n"))
	if not ok then
		return nil, "could not write " .. path .. ": " .. (err or "unknown error")
	end

	return true
end

--- Append entries that are not already in the log, in one write. Each entry is
--- `{ key = <string>, lines = <markdown lines> }`; its marker is stamped under
--- the heading, with the entry landing as `new` for a sweep to pick up. Entries
--- already present — whatever status they now carry — and repeats within the
--- batch are skipped, so the operation is idempotent.
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
			lines[#lines + 1] = M.format_marker(entry.key)
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

	-- A source log usually lives in a directory of its own (`~/org/sources/`),
	-- which the first ingestion has to create.
	local dir = path:match("^(.*)/[^/]+$")
	if dir then
		platform.fs.mkdirp(dir)
	end

	local ok, err = platform.fs.append_file(path, prefix .. table.concat(lines, "\n") .. "\n")
	if not ok then
		return nil, "could not append to " .. path .. ": " .. (err or "unknown error")
	end

	return appended
end

return M
