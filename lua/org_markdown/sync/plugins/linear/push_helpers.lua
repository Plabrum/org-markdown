-- =========================================================================
-- LINEAR PUSH HELPERS
-- =========================================================================
--
-- This module provides helper functions for the Linear push operation:
-- - Extracting Linear metadata from markdown
-- - Conflict detection
-- - Metadata updates in markdown files
-- - File scanning for push items

local M = {}

-- =========================================================================
-- EXTRACTION HELPERS
-- =========================================================================

--- Extract Linear ID from markdown body (HTML comment format)
--- @param lines table Array of lines
--- @param start_line number Line number to start searching from
--- @return string|nil Linear issue identifier (e.g., "IF-123")
function M.extract_linear_id_from_body(lines, start_line)
	if not lines or not start_line then
		return nil
	end

	-- Look ahead up to 10 lines for Linear ID comment
	for i = start_line, math.min(start_line + 9, #lines) do
		local line = lines[i]

		-- Stop at next heading
		local parser = require("org_markdown.utils.parser")
		if parser.parse_headline(line) then
			break
		end

		-- Match: <!-- Linear ID: IF-123 -->
		local linear_id = line:match("<!%-%- Linear ID: ([^%s]+) %-%->")
		if linear_id then
			return linear_id
		end
	end

	return nil
end

--- Extract Last Synced timestamp from markdown body
--- @param lines table Array of lines
--- @param start_line number Line number to start searching from
--- @return string|nil ISO timestamp
function M.extract_last_synced(lines, start_line)
	if not lines or not start_line then
		return nil
	end

	for i = start_line, math.min(start_line + 9, #lines) do
		local line = lines[i]

		local parser = require("org_markdown.utils.parser")
		if parser.parse_headline(line) then
			break
		end

		-- Match: <!-- Last Synced: 2025-12-20T14:30:00Z -->
		local timestamp = line:match("<!%-%- Last Synced: ([^%s]+) %-%->")
		if timestamp then
			return timestamp
		end
	end

	return nil
end

--- Extract Linear Updated timestamp from markdown body
--- @param lines table Array of lines
--- @param start_line number Line number to start searching from
--- @return string|nil ISO timestamp from Linear's updatedAt field
function M.extract_linear_updated(lines, start_line)
	if not lines or not start_line then
		return nil
	end

	for i = start_line, math.min(start_line + 9, #lines) do
		local line = lines[i]

		local parser = require("org_markdown.utils.parser")
		if parser.parse_headline(line) then
			break
		end

		-- Match: <!-- Linear Updated: 2025-12-19T10:00:00Z -->
		local timestamp = line:match("<!%-%- Linear Updated: ([^%s]+) %-%->")
		if timestamp then
			return timestamp
		end
	end

	return nil
end

--- Extract body content below heading, excluding metadata comments
--- @param lines table Array of all lines in file
--- @param heading_line number Line number of the heading
--- @return string Body content with metadata stripped
function M.extract_body_below_heading(lines, heading_line)
	if not lines or not heading_line then
		return ""
	end

	local parser = require("org_markdown.utils.parser")
	local body_lines = {}

	-- Start from line after heading
	for i = heading_line + 1, #lines do
		local line = lines[i]

		-- Stop at next heading
		if parser.parse_headline(line) then
			break
		end

		-- Skip metadata comments (Linear ID, timestamps)
		if not line:match("<!%-%- Linear") and not line:match("<!%-%- Last Synced") then
			table.insert(body_lines, line)
		end
	end

	-- Join lines and trim whitespace
	local body = table.concat(body_lines, "\n")
	return body:gsub("^%s+", ""):gsub("%s+$", "")
end

--- Extract clean description from body (strip Linear-specific metadata blocks)
--- @param body string Raw body content
--- @return string|nil Clean description suitable for Linear
function M.extract_description_from_body(body)
	if not body or body == "" then
		return nil
	end

	local lines = vim.split(body, "\n")
	local description_lines = {}

	for _, line in ipairs(lines) do
		-- Skip metadata lines that were added by pull sync
		if
			not line:match("^%*%*Assignee:%*%*")
			and not line:match("^%*%*Project:%*%*")
			and not line:match("^%*%*State:%*%*")
			and not line:match("^%*%*URL:%*%*")
			and not line:match("^%*%*ID:%*%*")
		then
			table.insert(description_lines, line)
		end
	end

	local clean_body = table.concat(description_lines, "\n")
	clean_body = clean_body:gsub("^%s+", ""):gsub("%s+$", "")

	return clean_body ~= "" and clean_body or nil
end

-- =========================================================================
-- CONFLICT DETECTION
-- =========================================================================

--- Parse ISO 8601 timestamp to comparable number
--- @param iso_str string ISO timestamp (e.g., "2025-12-20T14:30:00Z")
--- @return number|nil Unix timestamp
function M.parse_iso_timestamp(iso_str)
	if not iso_str or iso_str == "" then
		return nil
	end

	-- Match: YYYY-MM-DDTHH:MM:SSZ or YYYY-MM-DDTHH:MM:SS.SSSZ
	local year, month, day, hour, min, sec = iso_str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")

	if not year then
		return nil
	end

	return os.time({
		year = tonumber(year),
		month = tonumber(month),
		day = tonumber(day),
		hour = tonumber(hour),
		min = tonumber(min),
		sec = tonumber(sec),
	})
end

--- Check if item should be pushed (conflict detection)
--- Strategy: "Linear wins" - skip if Linear was modified after last sync
--- @param item table Item from markdown with last_synced and linear_updated
--- @param linear_issue table|nil Current issue from Linear API
--- @return boolean should_push
--- @return string reason Reason code: "create", "update", "conflict", "deleted"
function M.should_push_item(item, linear_issue)
	-- No Linear ID → CREATE
	if not item.linear_id then
		return true, "create"
	end

	-- Issue doesn't exist in Linear (deleted) → SKIP
	if not linear_issue then
		return false, "deleted"
	end

	-- No sync metadata → Assume safe to push (first push)
	if not item.last_synced then
		return true, "update"
	end

	-- Parse timestamps for comparison
	local last_synced_time = M.parse_iso_timestamp(item.last_synced)
	local linear_updated_time = M.parse_iso_timestamp(linear_issue.updatedAt)

	if not last_synced_time or not linear_updated_time then
		-- Can't compare timestamps → err on side of caution, allow push
		return true, "update"
	end

	-- Linear was modified after our last sync → CONFLICT (Linear wins)
	if linear_updated_time > last_synced_time then
		return false, "conflict"
	end

	-- Safe to push
	return true, "update"
end

-- =========================================================================
-- METADATA UPDATES
-- =========================================================================

--- Update markdown item with Linear metadata after push
--- Inserts or updates HTML comments with Linear ID and timestamps
--- @param file string File path
--- @param line_num number Heading line number
--- @param linear_id string Linear issue identifier (e.g., "IF-123")
--- @param updated_at string Linear's updatedAt timestamp
function M.update_item_with_linear_metadata(file, line_num, linear_id, updated_at)
	local utils = require("org_markdown.utils.utils")
	local parser = require("org_markdown.utils.parser")

	local lines = utils.read_lines(file)
	if not lines or not lines[line_num] then
		return
	end

	local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ") -- UTC ISO 8601

	-- Find insertion point (after heading, before next heading or body content)
	local insert_pos = line_num + 1
	local found_linear_id = false
	local found_last_synced = false
	local found_linear_updated = false

	-- Check if metadata already exists (within next 10 lines)
	for i = insert_pos, math.min(insert_pos + 9, #lines) do
		local line = lines[i]

		-- Stop at next heading
		if parser.parse_headline(line) then
			break
		end

		-- Check for existing metadata comments
		if line:match("<!%-%- Linear ID:") then
			lines[i] = string.format("<!-- Linear ID: %s -->", linear_id)
			found_linear_id = true
		elseif line:match("<!%-%- Last Synced:") then
			lines[i] = string.format("<!-- Last Synced: %s -->", timestamp)
			found_last_synced = true
		elseif line:match("<!%-%- Linear Updated:") then
			lines[i] = string.format("<!-- Linear Updated: %s -->", updated_at)
			found_linear_updated = true
		end
	end

	-- If metadata doesn't exist, insert it after heading
	if not (found_linear_id and found_last_synced and found_linear_updated) then
		local metadata_lines = {}

		-- Add blank line before metadata if heading has content after it
		if
			#lines >= insert_pos
			and lines[insert_pos]
			and lines[insert_pos] ~= ""
			and not lines[insert_pos]:match("^<!%-%-")
		then
			table.insert(metadata_lines, "")
		end

		-- Add missing metadata
		if not found_linear_id then
			table.insert(metadata_lines, string.format("<!-- Linear ID: %s -->", linear_id))
		end
		if not found_last_synced then
			table.insert(metadata_lines, string.format("<!-- Last Synced: %s -->", timestamp))
		end
		if not found_linear_updated then
			table.insert(metadata_lines, string.format("<!-- Linear Updated: %s -->", updated_at))
		end

		-- Insert metadata
		for i = #metadata_lines, 1, -1 do
			table.insert(lines, insert_pos, metadata_lines[i])
		end
	end

	utils.write_lines(file, lines)
end

--- Clear Linear metadata from markdown when issue is deleted
--- Removes HTML comments for Linear ID and timestamps
--- @param file string File path
--- @param line_num number Heading line number
function M.clear_linear_metadata(file, line_num)
	local utils = require("org_markdown.utils.utils")
	local parser = require("org_markdown.utils.parser")

	local lines = utils.read_lines(file)
	if not lines or not lines[line_num] then
		return
	end

	local insert_pos = line_num + 1
	local lines_to_remove = {}

	-- Find and mark metadata lines for removal (within next 10 lines)
	for i = insert_pos, math.min(insert_pos + 9, #lines) do
		local line = lines[i]

		-- Stop at next heading
		if parser.parse_headline(line) then
			break
		end

		-- Mark Linear metadata comments for removal
		if line:match("<!%-%- Linear ID:") or line:match("<!%-%- Last Synced:") or line:match("<!%-%- Linear Updated:") then
			table.insert(lines_to_remove, i)
		end
	end

	-- Remove marked lines (in reverse order to maintain indices)
	for i = #lines_to_remove, 1, -1 do
		table.remove(lines, lines_to_remove[i])
	end

	-- Remove any blank line that was before metadata
	if #lines_to_remove > 0 and insert_pos <= #lines and lines[insert_pos] == "" then
		-- Check if the next line after the blank is not a metadata comment (we removed all metadata)
		local next_line = lines[insert_pos + 1]
		if not next_line or not next_line:match("^<!%-%-") then
			table.remove(lines, insert_pos)
		end
	end

	utils.write_lines(file, lines)
end

-- =========================================================================
-- FILE SCANNING
-- =========================================================================

--- Scan staging file for items to push to Linear
--- Only reads from staging file to avoid duplicates in agenda
--- @param staging_file string Path to staging file
--- @return table items Array of items to push
--- @return table lines All lines from the file (for in-memory manipulation)
--- @return string expanded_file Expanded file path
function M.scan_files_for_push_items(staging_file)
	local parser = require("org_markdown.utils.parser")
	local utils = require("org_markdown.utils.utils")

	local items_to_push = {}

	-- Only scan the staging file
	if not staging_file then
		return items_to_push, {}, nil
	end

	local expanded_file = vim.fn.expand(staging_file)

	-- Create staging file if it doesn't exist
	if vim.fn.filereadable(expanded_file) ~= 1 then
		-- Create parent directory if needed
		local dir = vim.fn.fnamemodify(expanded_file, ":h")
		vim.fn.mkdir(dir, "p")

		-- Create empty file with header
		local initial_content = {
			"<!-- LINEAR STAGING FILE -->",
			"<!-- Add TODO items here to create Linear issues -->",
			"<!-- Items are automatically removed after successful push -->",
			"",
		}
		utils.write_lines(expanded_file, initial_content)
		return items_to_push, initial_content, expanded_file
	end

	local lines = utils.read_lines(expanded_file)
	if not lines then
		return items_to_push, {}, expanded_file
	end

	for i, line in ipairs(lines) do
		local heading = parser.parse_headline(line)

		if heading then
			-- Check if this item should be pushed:
			-- 1. Has a TODO state (TODO, IN_PROGRESS, etc.)
			-- 2. Has a Linear ID (existing issue for updates)
			local linear_id = M.extract_linear_id_from_body(lines, i + 1)

			if heading.state or linear_id then
				-- Find end of this item (line before next heading or end of file)
				local end_line = #lines
				for j = i + 1, #lines do
					if parser.parse_headline(lines[j]) then
						end_line = j - 1
						break
					end
				end

				-- Extract metadata and body
				local body = M.extract_body_below_heading(lines, i)
				local description = M.extract_description_from_body(body)
				local last_synced = M.extract_last_synced(lines, i + 1)
				local linear_updated = M.extract_linear_updated(lines, i + 1)

				-- Build item
				local item = {
					file = expanded_file,
					line = i,
					end_line = end_line,
					title = heading.text,
					status = heading.state,
					priority = heading.priority,
					tags = heading.tags,
					linear_id = linear_id,
					last_synced = last_synced,
					linear_updated = linear_updated,
					description = description,
				}

				-- Extract due date from tracked date
				if heading.tracked then
					local date = parser.extract_date(heading.tracked)
					if date then
						item.due_date = date
					end
				end

				table.insert(items_to_push, item)
			end
		end
	end

	return items_to_push, lines, expanded_file
end

--- Remove successful ranges from lines and write to file
--- @param file string File path to write to
--- @param lines table Array of lines (modified in place)
--- @param successful_ranges table Array of {start_line, end_line} ranges to remove
function M.remove_ranges_and_write(file, lines, successful_ranges)
	if not file or not lines or not successful_ranges or #successful_ranges == 0 then
		return
	end

	local utils = require("org_markdown.utils.utils")

	-- Sort ranges by start_line in descending order (remove from end first)
	table.sort(successful_ranges, function(a, b)
		return a.start_line > b.start_line
	end)

	-- Remove each range from lines (in reverse order so indices stay valid)
	for _, range in ipairs(successful_ranges) do
		for i = range.end_line, range.start_line, -1 do
			table.remove(lines, i)
		end
	end

	-- Remove any trailing blank lines
	while #lines > 0 and lines[#lines] == "" do
		table.remove(lines)
	end

	-- Write the modified lines back to file
	utils.write_lines(file, lines)
end

return M
