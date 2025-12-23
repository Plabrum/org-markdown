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
-- NODE-BASED EXTRACTION HELPERS (using document model)
-- =========================================================================

--- Extract Linear ID from node property
--- @param node table Document node
--- @return string|nil Linear issue identifier (e.g., "IF-123")
function M.extract_linear_id_from_node(node)
	return node:get_property("LINEAR_ID")
end

--- Extract Last Synced timestamp from node property
--- @param node table Document node
--- @return string|nil ISO timestamp
function M.extract_last_synced_from_node(node)
	return node:get_property("LINEAR_LAST_SYNCED")
end

--- Extract Linear Updated timestamp from node property
--- @param node table Document node
--- @return string|nil ISO timestamp
function M.extract_linear_updated_from_node(node)
	return node:get_property("LINEAR_UPDATED")
end

--- Extract body content from node
--- @param node table Document node
--- @return string Body content
function M.extract_body_from_node(node)
	if not node.content_lines or #node.content_lines == 0 then
		return ""
	end
	return table.concat(node.content_lines, "\n")
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

--- Update markdown item with Linear metadata after push using document model
--- Stores metadata as node properties
--- @param file string File path
--- @param line_num number Heading line number
--- @param linear_id string Linear issue identifier (e.g., "IF-123")
--- @param updated_at string Linear's updatedAt timestamp
function M.update_item_with_linear_metadata(file, line_num, linear_id, updated_at)
	local document = require("org_markdown.utils.document")

	local root = document.read_from_file(file)
	local node = document.find_node_at_line(root, line_num)

	if not node or node.type ~= "heading" then
		return
	end

	local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ") -- UTC ISO 8601

	-- Set metadata as node properties (new format)
	node:set_property("LINEAR_ID", linear_id)
	node:set_property("LINEAR_LAST_SYNCED", timestamp)
	node:set_property("LINEAR_UPDATED", updated_at)

	-- Write back to file
	document.write_to_file(file, root)
end

--- Clear Linear metadata from markdown when issue is deleted using document model
--- Removes Linear properties from node
--- @param file string File path
--- @param line_num number Heading line number
function M.clear_linear_metadata(file, line_num)
	local document = require("org_markdown.utils.document")

	local root = document.read_from_file(file)
	local node = document.find_node_at_line(root, line_num)

	if not node or node.type ~= "heading" then
		return
	end

	-- Clear Linear properties
	node:set_property("LINEAR_ID", nil)
	node:set_property("LINEAR_LAST_SYNCED", nil)
	node:set_property("LINEAR_UPDATED", nil)

	-- Write back to file
	document.write_to_file(file, root)
end

-- =========================================================================
-- FILE SCANNING
-- =========================================================================

--- Collect push items from a document tree recursively
--- @param node table Document node
--- @param file string File path
--- @param items table Output array to append to
local function collect_push_items_from_tree(node, file, items)
	local parser = require("org_markdown.utils.parser")

	if node.type == "heading" then
		local linear_id = M.extract_linear_id_from_node(node)
		local has_state = node.parsed and node.parsed.state

		if has_state or linear_id then
			local body = M.extract_body_from_node(node)
			local description = M.extract_description_from_body(body)
			local last_synced = M.extract_last_synced_from_node(node)
			local linear_updated = M.extract_linear_updated_from_node(node)

			local item = {
				file = file,
				line = node.start_line,
				end_line = node.end_line,
				title = node.parsed and node.parsed.text or "",
				status = node.parsed and node.parsed.state,
				priority = node.parsed and node.parsed.priority,
				tags = node.parsed and node.parsed.tags,
				linear_id = linear_id,
				last_synced = last_synced,
				linear_updated = linear_updated,
				description = description,
			}

			-- Extract due date from tracked date
			if node.parsed and node.parsed.tracked then
				local date = parser.extract_date(node.parsed.tracked)
				if date then
					item.due_date = date
				end
			end

			table.insert(items, item)
		end
	end

	-- Recurse into children
	for _, child in ipairs(node.children or {}) do
		collect_push_items_from_tree(child, file, items)
	end
end

--- Scan staging file for items to push to Linear using document model
--- Only reads from staging file to avoid duplicates in agenda
--- @param staging_file string Path to staging file
--- @return table items Array of items to push
--- @return table lines All lines from the file (for in-memory manipulation)
--- @return string expanded_file Expanded file path
function M.scan_files_for_push_items(staging_file)
	local document = require("org_markdown.utils.document")
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

	-- Read lines for backward compat return value
	local lines = utils.read_lines(expanded_file)
	if not lines then
		return items_to_push, {}, expanded_file
	end

	-- Parse with document model and collect items
	local root = document.parse(lines)
	collect_push_items_from_tree(root, expanded_file, items_to_push)

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
