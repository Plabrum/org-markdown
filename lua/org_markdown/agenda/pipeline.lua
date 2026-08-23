-- Pure agenda compute pipeline: scan → filter → sort → group.
--
-- This module holds the vim-free core of the agenda system, lifted out of
-- `agenda.lua` so it runs identically in-editor and under the standalone CLI
-- (plain luajit, no `vim` global). It performs NO rendering and touches no UI:
-- `compute_view` returns a plain data structure that either the in-editor
-- renderer or the CLI's JSON encoder can consume.
--
-- All formerly-`vim.*` calls route through `compat` so nothing here depends on
-- the Neovim runtime.

local compat = require("org_markdown.compat.vim")
local config = require("org_markdown.config")
local queries = require("org_markdown.utils.queries")
local utils = require("org_markdown.utils.utils")
local document = require("org_markdown.utils.document")
local frontmatter = require("org_markdown.utils.frontmatter")
local datetime = require("org_markdown.utils.datetime")
local ingest = require("org_markdown.sync.ingest")

local M = {}

-- Returns table of agenda items grouped by source bucket.
-- @param file_patterns table|nil Optional patterns to filter files (passed as include_patterns)
-- @return table { tasks = {}, calendar = {}, all = {} }
function M.scan_files(file_patterns)
	-- Apply file patterns for early filtering. Ingestion logs drop out on top of
	-- `ignore_patterns`, so a source log stays out of every view whether or not
	-- the user's patterns happen to cover where it lives.
	local files = queries.find_markdown_files({
		include_patterns = file_patterns or {},
		ignore_patterns = config.agendas.ignore_patterns or {},
		ignore_files = ingest.log_paths(),
	})
	local agenda_items = { tasks = {}, calendar = {}, all = {} }

	for _, file in ipairs(files) do
		local lines = utils.read_lines(file)
		local display_name = frontmatter.get_display_name(file, lines)
		local root = document.parse(lines)

		-- Recursive helper to collect headings from document tree
		-- Builds hierarchical items with children array
		local function collect_headings(node, depth)
			depth = depth or 0

			if node.type == "heading" and node.parsed then
				local p = node.parsed
				local item = {
					title = p.text,
					state = p.state,
					priority = p.priority,
					date = p.tracked,
					start_time = p.start_time,
					end_time = p.end_time,
					all_day = p.all_day,
					line = node.start_line,
					file = file,
					tags = p.tags,
					source = display_name,
					-- Hierarchy fields
					children = {},
					depth = depth,
					node = node,
				}

				-- Recursively collect children
				for _, child in ipairs(node.children or {}) do
					local child_item = collect_headings(child, depth + 1)
					if child_item then
						table.insert(item.children, child_item)
					end
				end

				return item
			elseif node.type == "document" then
				-- Document root: collect all top-level headings
				local top_level_items = {}
				for _, child in ipairs(node.children or {}) do
					local item = collect_headings(child, 0)
					if item then
						table.insert(top_level_items, item)
					end
				end
				return top_level_items
			end
		end

		-- Collect top-level items from this file
		local file_items = collect_headings(root)

		-- Add only top-level items to arrays (children are preserved in item.children)
		for _, item in ipairs(file_items or {}) do
			-- Add to 'all' array for every heading
			table.insert(agenda_items.all, item)

			-- Add to 'tasks' array if it or any descendant has a state
			local function has_state_recursive(it)
				if it.state then
					return true
				end
				for _, child in ipairs(it.children or {}) do
					if has_state_recursive(child) then
						return true
					end
				end
				return false
			end

			if has_state_recursive(item) then
				table.insert(agenda_items.tasks, item)
			end

			-- Add to 'calendar' array if it or any descendant has a tracked date
			local function has_date_recursive(it)
				if it.date then
					return true
				end
				for _, child in ipairs(it.children or {}) do
					if has_date_recursive(child) then
						return true
					end
				end
				return false
			end

			if has_date_recursive(item) then
				table.insert(agenda_items.calendar, item)
			end
		end
	end

	return agenda_items
end

------------------core engine functions --------------------------

-- Helper: Parse date range filter
function M.parse_date_range(date_range_spec)
	if not date_range_spec then
		return nil
	end

	-- Delegate to datetime module for range calculation
	local start_date, end_date = datetime.calculate_range(date_range_spec)
	return { from = start_date, to = end_date }
end

-- Filter a single item based on filter specs
function M.filter_item(item, filters)
	if not filters then
		return true
	end

	-- State filter: only filter items that have a state
	-- Items without states (plain headings) pass through
	if filters.states and #filters.states > 0 then
		if item.state and not compat.tbl_contains(filters.states, item.state) then
			return false
		end
	end

	-- Priority filter: only filter items that have a priority
	-- Items without priorities (plain headings) pass through
	if filters.priorities and #filters.priorities > 0 then
		if item.priority and not compat.tbl_contains(filters.priorities, item.priority) then
			return false
		end
	end

	-- File filtering is done at the query stage via file_patterns
	-- (removed late file filtering for performance)

	-- Tag filter (any match)
	if filters.tags and #filters.tags > 0 then
		if not item.tags or #item.tags == 0 then
			return false
		end
		local has_match = false
		for _, tag in ipairs(item.tags or {}) do
			if compat.tbl_contains(filters.tags, tag) then
				has_match = true
				break
			end
		end
		if not has_match then
			return false
		end
	end

	-- Date range filter
	if filters.date_range then
		if not item.date then
			return false
		end
		local range = M.parse_date_range(filters.date_range)
		if range and (item.date < range.from or item.date > range.to) then
			return false
		end
	end

	return true
end

-- Recursively filter an item and its children
-- Returns filtered item with filtered children, or nil if item doesn't match
function M.filter_item_recursive(item, filters)
	if not filters then
		return item
	end

	-- Check if parent matches filter
	if not M.filter_item(item, filters) then
		-- Parent doesn't match: skip entire subtree (hide orphaned children)
		return nil
	end

	-- Parent matches: recursively filter children
	if item.children and #item.children > 0 then
		local filtered_children = {}
		for _, child in ipairs(item.children) do
			local filtered_child = M.filter_item_recursive(child, filters)
			if filtered_child then
				table.insert(filtered_children, filtered_child)
			end
		end

		-- Create copy of item with filtered children
		local filtered_item = compat.tbl_extend("force", {}, item)
		filtered_item.children = filtered_children
		return filtered_item
	end

	-- Leaf item that matches
	return item
end

-- Apply filters to a list of items
function M.apply_filters(items, filters)
	if not filters then
		return items
	end

	local filtered = {}
	for _, item in ipairs(items) do
		-- Use recursive filtering to handle hierarchy
		local filtered_item = M.filter_item_recursive(item, filters)
		if filtered_item then
			table.insert(filtered, filtered_item)
		end
	end
	return filtered
end

-- Compare two items for sorting
function M.compare_items(a, b, sort_spec)
	if not sort_spec or not sort_spec.by then
		return false
	end

	local field = sort_spec.by
	local ascending = sort_spec.order ~= "desc"

	-- Get the values to compare
	local val_a, val_b
	if field == "priority" then
		local rank = sort_spec.priority_rank or { A = 1, B = 2, C = 3, Z = 99 }
		local pa = a.priority or "Z"
		local pb = b.priority or "Z"
		val_a = rank[pa] or 99
		val_b = rank[pb] or 99
	elseif field == "date" then
		val_a = a.date or "9999-99-99"
		val_b = b.date or "9999-99-99"
	elseif field == "state" then
		val_a = a.state or ""
		val_b = b.state or ""
	elseif field == "title" then
		val_a = a.title or ""
		val_b = b.title or ""
	elseif field == "file" then
		val_a = a.source or ""
		val_b = b.source or ""
	else
		-- Unknown field, return false to maintain stability
		return false
	end

	-- Proper comparison that maintains strict weak ordering
	if ascending then
		return val_a < val_b
	else
		return val_b < val_a
	end
end

-- Apply sorting to a list of items
function M.apply_sort(items, sort_spec)
	if not sort_spec or not sort_spec.by then
		return items
	end

	local sorted = compat.deepcopy(items)
	table.sort(sorted, function(a, b)
		return M.compare_items(a, b, sort_spec)
	end)
	return sorted
end

-- Get group key for an item
function M.get_group_key(item, group_by)
	if group_by == "date" then
		return item.date or "No date"
	elseif group_by == "priority" then
		return item.priority or "No priority"
	elseif group_by == "state" then
		return item.state or "No state"
	elseif group_by == "file" then
		return item.source or "Unknown file"
	elseif group_by == "tags" then
		-- Use first tag or "No tags"
		return (item.tags and #item.tags > 0) and item.tags[1] or "No tags"
	else
		return "All items"
	end
end

-- Group items by specified field
function M.group_items(items, group_by)
	if not group_by then
		return { { key = nil, items = items } }
	end

	local grouped = {}
	local keys_order = {}

	for _, item in ipairs(items) do
		local key = M.get_group_key(item, group_by)

		if not grouped[key] then
			grouped[key] = {}
			table.insert(keys_order, key)
		end
		table.insert(grouped[key], item)
	end

	local result = {}
	for _, key in ipairs(keys_order) do
		table.insert(result, { key = key, items = grouped[key] })
	end

	-- Sort within date groups: timed events first (by time), then all-day
	if group_by == "date" then
		for _, group in ipairs(result) do
			table.sort(group.items, function(a, b)
				-- All-day events go last
				if a.all_day and not b.all_day then
					return false
				end
				if b.all_day and not a.all_day then
					return true
				end

				-- Both timed: sort by start time
				if a.start_time and b.start_time then
					return a.start_time < b.start_time
				end

				-- No specific order otherwise
				return false
			end)
		end
	end

	return result
end

-- Get source items based on view source spec
function M.get_source_items(all_data, source)
	if source == "tasks" then
		return all_data.tasks
	elseif source == "calendar" then
		return all_data.calendar
	elseif source == "all" then
		return all_data.all
	else
		return all_data.tasks -- Default fallback
	end
end

--- Run the full compute pipeline for a view, without rendering.
--- Mirrors the scan → filter → sort → group stages of the in-editor agenda.
---@param view_id string
---@param view_def table Resolved view definition (source, filters, sort, group_by, ...)
---@return { view_id: string, title: string|nil, groups: { key: any, items: table[] }[] }
function M.compute_view(view_id, view_def)
	-- 1. Get source data with early file filtering
	local file_patterns = view_def.filters and view_def.filters.file_patterns or nil
	local all_data = M.scan_files(file_patterns)
	local items = M.get_source_items(all_data, view_def.source or "tasks")

	-- 2. Filter → Sort → Group
	items = M.apply_filters(items, view_def.filters)
	items = M.apply_sort(items, view_def.sort)
	local groups = M.group_items(items, view_def.group_by)

	return {
		view_id = view_id,
		title = view_def.title,
		groups = groups,
	}
end

return M
