-- Agenda view rendering and management
-- Responsibilities:
-- - Scan files for agenda items (tasks, calendar events, all headings)
-- - Filter, sort, and group items based on view configuration
-- - Render agenda views with hierarchical support
-- - Manage fold states for agenda items
-- - Handle agenda buffer keybindings and interactions

local config = require("org_markdown.config")
local utils = require("org_markdown.utils.utils")
local document = require("org_markdown.utils.document")
local queries = require("org_markdown.utils.queries")
local editing = require("org_markdown.utils.editing")
local agenda_formatters = require("org_markdown.agenda_formatters")
local datetime = require("org_markdown.utils.datetime")
local frontmatter = require("org_markdown.utils.frontmatter")
local preview = require("org_markdown.utils.preview")

local M = {}

-- Module-level state for agenda views
local state = {
	fold_states = {}, -- Fold states by view_id: { view_id = { "file:line" = is_folded } }
	current_view_id = nil, -- Currently displayed view
	line_to_item = {}, -- Current line_to_item mapping
}

-- Helper: Generate stable identifier for an item
local function get_item_id(item)
	return string.format("%s:%d", item.file, item.line)
end

-- Color palette mapping color names to hex values
local COLOR_PALETTE = {
	red = "#ff5f5f",
	yellow = "#f0c000",
	green = "#5fd75f",
	blue = "#5fafd7",
	orange = "#ff8700",
	purple = "#af87ff",
	gray = "#808080",
}

-- Setup dynamic highlight groups based on config
local function setup_highlight_groups()
	local status_colors = config.status_colors or {}

	for state, color_name in pairs(status_colors) do
		local hex_color = COLOR_PALETTE[color_name] or COLOR_PALETTE.red
		local hl_group_name = "OrgStatus_" .. state
		vim.api.nvim_set_hl(0, hl_group_name, { fg = hex_color, bold = true })
	end

	-- Keep OrgTitle for agenda view titles
	vim.api.nvim_set_hl(0, "OrgTitle", { fg = "#87afff", bold = true })
end

-- Initialize highlights
setup_highlight_groups()

-- Helper to find view by ID
local function find_view(view_id)
	if not config.agendas or not config.agendas.views then
		return nil
	end
	local view_def = config.agendas.views[view_id]
	if not view_def then
		return nil
	end
	-- Return with id field included
	local view = vim.deepcopy(view_def)
	view.id = view_id
	return view
end

-- Helper function to cycle TODO state in a file using document model
-- Returns new_line, new_state if successful, nil otherwise
-- Uses document model for status cycling to enable COMPLETED_AT handling
local function cycle_todo_in_file(item)
	local lines = utils.read_lines(item.file)
	local line = lines[item.line]
	if not line then
		return nil
	end

	-- Try checkbox first (simple line-based, no document model needed)
	local new_lines = editing.cycle_checkbox_inline(line, config.checkbox_states)
	if new_lines and new_lines[1] then
		lines[item.line] = new_lines[1]
		utils.write_lines(item.file, lines)
		return new_lines[1], nil -- Checkboxes don't have heading state
	end

	-- For status cycling, use document model (enables COMPLETED_AT)
	local root = document.parse(lines)
	local node = document.find_node_at_line(root, item.line)

	if not node or node.type ~= "heading" then
		return nil
	end

	local current_state = node.parsed and node.parsed.state
	if not current_state then
		return nil
	end

	-- Find next state in cycle
	local states = config.status_states
	local index = nil
	for i, state in ipairs(states) do
		if state == current_state then
			index = i
			break
		end
	end

	if not index then
		return nil
	end

	local next_state = states[(index % #states) + 1]

	-- Mutate node (this auto-handles COMPLETED_AT via node:set_state)
	node:set_state(next_state)

	-- Serialize and write
	document.write_to_file(item.file, root)

	-- Re-read the file to get the actual new heading line
	local updated_lines = utils.read_lines(item.file)
	local new_heading_line = updated_lines[item.line]

	return new_heading_line, next_state
end

local function highlight_states(buf, lines)
	local status_states = config.status_states

	for i, line in ipairs(lines) do
		-- Find the position of each configured state word and highlight it
		for _, state in ipairs(status_states) do
			local state_start, state_end = line:find(state)
			if state_start then
				local hl_group_name = "OrgStatus_" .. state
				vim.api.nvim_buf_add_highlight(buf, -1, hl_group_name, i - 1, state_start - 1, state_end)
			end
		end
	end
end

-- Returns table of agenda items
-- @param file_patterns table|nil Optional patterns to filter files (passed as include_patterns)
local function scan_files(file_patterns)
	-- Apply file patterns for early filtering
	local files = queries.find_markdown_files({
		include_patterns = file_patterns or {},
		ignore_patterns = config.agendas.ignore_patterns or {},
	})
	local agenda_items = { tasks = {}, calendar = {}, all = {} }

	for _, file in ipairs(files) do
		local lines = utils.read_lines(file)
		local display_name = frontmatter.get_display_name(file, lines)
		local root = document.parse(lines)

		-- Recursive helper to collect headings from document tree
		-- Now builds hierarchical items with children array
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
					-- NEW: Hierarchy fields
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
local function parse_date_range(date_range_spec)
	if not date_range_spec then
		return nil
	end

	-- Delegate to datetime module for range calculation
	local start_date, end_date = datetime.calculate_range(date_range_spec)
	return { from = start_date, to = end_date }
end

-- Filter a single item based on filter specs
local function filter_item(item, filters)
	if not filters then
		return true
	end

	-- State filter: only filter items that have a state
	-- Items without states (plain headings) pass through
	if filters.states and #filters.states > 0 then
		if item.state and not vim.tbl_contains(filters.states, item.state) then
			return false
		end
	end

	-- Priority filter: only filter items that have a priority
	-- Items without priorities (plain headings) pass through
	if filters.priorities and #filters.priorities > 0 then
		if item.priority and not vim.tbl_contains(filters.priorities, item.priority) then
			return false
		end
	end

	-- File filtering is now done at the query stage via file_patterns
	-- (removed late file filtering for performance)

	-- Tag filter (any match)
	if filters.tags and #filters.tags > 0 then
		if not item.tags or #item.tags == 0 then
			return false
		end
		local has_match = false
		for _, tag in ipairs(item.tags or {}) do
			if vim.tbl_contains(filters.tags, tag) then
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
		local range = parse_date_range(filters.date_range)
		if range and (item.date < range.from or item.date > range.to) then
			return false
		end
	end

	return true
end

-- Recursively filter an item and its children
-- Returns filtered item with filtered children, or nil if item doesn't match
local function filter_item_recursive(item, filters)
	if not filters then
		return item
	end

	-- Check if parent matches filter
	if not filter_item(item, filters) then
		-- Parent doesn't match: skip entire subtree (hide orphaned children)
		return nil
	end

	-- Parent matches: recursively filter children
	if item.children and #item.children > 0 then
		local filtered_children = {}
		for _, child in ipairs(item.children) do
			local filtered_child = filter_item_recursive(child, filters)
			if filtered_child then
				table.insert(filtered_children, filtered_child)
			end
		end

		-- Create copy of item with filtered children
		local filtered_item = vim.tbl_extend("force", {}, item)
		filtered_item.children = filtered_children
		return filtered_item
	end

	-- Leaf item that matches
	return item
end

-- Apply filters to a list of items
local function apply_filters(items, filters)
	if not filters then
		return items
	end

	local filtered = {}
	for _, item in ipairs(items) do
		-- Use recursive filtering to handle hierarchy
		local filtered_item = filter_item_recursive(item, filters)
		if filtered_item then
			table.insert(filtered, filtered_item)
		end
	end
	return filtered
end

-- Compare two items for sorting
local function compare_items(a, b, sort_spec)
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
local function apply_sort(items, sort_spec)
	if not sort_spec or not sort_spec.by then
		return items
	end

	local sorted = vim.deepcopy(items)
	table.sort(sorted, function(a, b)
		return compare_items(a, b, sort_spec)
	end)
	return sorted
end

-- Get group key for an item
local function get_group_key(item, group_by)
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
local function group_items(items, group_by)
	if not group_by then
		return { { key = nil, items = items } }
	end

	local grouped = {}
	local keys_order = {}

	for _, item in ipairs(items) do
		local key = get_group_key(item, group_by)

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

-- Formatter registry with built-in presets
local formatters = {
	blocks = {
		flat = function(item)
			return agenda_formatters.format_blocks(item, "")
		end,

		grouped = function(item)
			return agenda_formatters.format_blocks(item, "  ")
		end,

		group_header = function(group_key, group_by)
			if group_by == "date" then
				return "  " .. datetime.format_display(group_key)
			else
				return group_key
			end
		end,
	},

	timeline = {
		flat = function(item)
			return agenda_formatters.format_timeline(item, "")
		end,

		grouped = function(item)
			return agenda_formatters.format_timeline(item, "  ")
		end,

		group_header = function(group_key, group_by)
			if group_by == "date" then
				return datetime.format_display(group_key, "%a %d %b")
					.. " ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
			else
				return group_key
			end
		end,
	},
}

-- Render a view from grouped items
local function render_view(groups, view_def, view_id)
	local lines = {}
	local line_to_item = {}

	local format_name = (view_def.display and view_def.display.format) or "timeline"
	local fmt = formatters[format_name] or formatters.timeline

	-- Get fold states for this view (convert to ID-based lookup)
	state.fold_states[view_id] = state.fold_states[view_id] or {}
	local fold_states_by_id = state.fold_states[view_id]

	-- Build a lookup function for fold states using stable IDs
	local fold_lookup = {}
	setmetatable(fold_lookup, {
		__index = function(_, item)
			local item_id = get_item_id(item)
			return fold_states_by_id[item_id] or false
		end,
	})

	for _, group in ipairs(groups) do
		if group.key then
			-- Add group header
			table.insert(lines, fmt.group_header(group.key, view_def.group_by))
			-- Store file info for file group headers so Enter can jump to the file
			if view_def.group_by == "file" and #group.items > 0 then
				line_to_item[#lines] = { file = group.items[1].file, line = 1 }
			end
			if #group.items == 0 then
				table.insert(lines, "    (no entries)")
			end
		end

		-- Render items using tree formatter (hierarchical)
		for _, item in ipairs(group.items) do
			local tree_result = agenda_formatters.format_tree(item, {
				depth = 0,
				style = format_name,
				fold_states = fold_lookup,
			})

			for _, entry in ipairs(tree_result) do
				table.insert(lines, entry.line)
				-- Map line to the actual item it represents (could be parent or child)
				line_to_item[#lines] = entry.item
			end
		end

		if group.key then
			table.insert(lines, "")
		end
	end

	return lines, line_to_item
end

-- Get source items based on view source spec
local function get_source_items(all_data, source)
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

-- Process a view through the filter → sort → group → render pipeline
local function process_view(view_id, view_def)
	-- 1. Get source data with early file filtering
	local file_patterns = view_def.filters and view_def.filters.file_patterns or nil
	local all_data = scan_files(file_patterns)
	local items = get_source_items(all_data, view_def.source or "tasks")

	-- 2. Filter → Sort → Group
	items = apply_filters(items, view_def.filters)
	items = apply_sort(items, view_def.sort)
	local groups = group_items(items, view_def.group_by)

	-- 3. Render
	return render_view(groups, view_def, view_id)
end

-- Refresh the current view (re-process and re-render)
function M.refresh_current_view()
	if not state.current_view_id or not state.current_buf or not state.current_win then
		return
	end

	local view_id = state.current_view_id
	local view_def = find_view(view_id)
	if not view_def then
		return
	end

	-- Re-process the view
	local lines, line_to_item = process_view(view_id, view_def)

	-- Update state
	state.line_to_item = line_to_item

	-- Update buffer
	vim.bo[state.current_buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.current_buf, 0, -1, false, lines)
	highlight_states(state.current_buf, lines)
	vim.bo[state.current_buf].modifiable = false
end

-- Show full entry details in a floating window
local function show_entry_preview(item)
	if not item or not item.file or not item.line then
		return
	end
	preview.show_heading_preview(item.file, item.line)
end

-- Cycle fold state for item at cursor (or show preview for leaf items)
function M.cycle_agenda_fold()
	if not state.current_win or not state.current_buf then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(state.current_win)
	local line_num = cursor[1]
	local item = state.line_to_item[line_num]

	if not item then
		-- No item at cursor
		return
	end

	if not item.children or #item.children == 0 then
		-- Leaf item: show preview instead of folding
		show_entry_preview(item)
		return
	end

	-- Parent item: toggle fold state
	local view_id = state.current_view_id
	state.fold_states[view_id] = state.fold_states[view_id] or {}

	-- Use stable identifier instead of object reference
	local item_id = get_item_id(item)
	local is_folded = state.fold_states[view_id][item_id] or false
	state.fold_states[view_id][item_id] = not is_folded

	-- Re-render the view
	M.refresh_current_view()

	-- Restore cursor position (refresh might change line count)
	if vim.api.nvim_win_is_valid(state.current_win) then
		local new_line_count = vim.api.nvim_buf_line_count(state.current_buf)
		local new_line_num = math.min(line_num, new_line_count)
		vim.api.nvim_win_set_cursor(state.current_win, { new_line_num, 0 })
	end
end

-- Generic view function that works with any view definition
function M.show_view(view_id)
	local view_def = find_view(view_id)
	if not view_def then
		vim.notify("Unknown view: " .. view_id, vim.log.levels.ERROR)
		return
	end

	local lines, line_to_item = process_view(view_id, view_def)

	-- Store state for refresh and fold cycling
	state.current_view_id = view_id
	state.line_to_item = line_to_item

	local buf, win = utils.open_window({
		title = "Agenda - " .. (view_def.title or view_id),
		method = config.agendas.window_method,
		filetype = "markdown",
		footer = "<CR> cycle | <tab> fold | gf jump | q close",
	})

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	highlight_states(buf, lines)
	vim.bo[buf].modifiable = false

	-- Store buffer and window in state for refresh
	state.current_buf = buf
	state.current_win = win

	-- Configure line wrapping with indentation for continuation lines
	vim.wo[win].wrap = true
	vim.wo[win].breakindent = true
	vim.wo[win].breakindentopt = "shift:7"

	-- Add keymap to cycle task state
	vim.keymap.set("n", "<CR>", function()
		local cursor = vim.api.nvim_win_get_cursor(win)
		local line_num = cursor[1]
		local item = line_to_item[line_num]
		if item then
			local new_heading, new_state = cycle_todo_in_file(item)
			if new_heading then
				-- Update the line in-place without refreshing (preserves DONE items until agenda closes)
				local current_line = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)[1]
				-- Extract the prefix (indentation + formatting) and replace just the heading part
				local prefix = current_line:match("^(%s*)")
				local updated_line = prefix .. new_heading:match("^#*%s*(.*)$")

				vim.bo[buf].modifiable = true
				vim.api.nvim_buf_set_lines(buf, line_num - 1, line_num, false, { updated_line })

				-- Re-apply syntax highlighting to the updated line
				local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
				highlight_states(buf, lines)

				vim.bo[buf].modifiable = false

				-- Update the item state in the mapping for consistency
				if item then
					item.state = new_state
				end
			end
		end
	end, { buffer = buf, silent = true })

	-- Add keymap to jump to file
	vim.keymap.set("n", "gf", function()
		local cursor = vim.api.nvim_win_get_cursor(win)
		local line_num = cursor[1]
		local item = line_to_item[line_num]
		if item then
			-- Close the agenda window
			vim.api.nvim_win_close(win, true)
			-- Open the file and jump to the line
			vim.cmd("edit " .. vim.fn.fnameescape(item.file))
			vim.api.nvim_win_set_cursor(0, { item.line, 0 })
		end
	end, { buffer = buf, silent = true })

	-- Add keymap to cycle fold state
	vim.keymap.set("n", "<Tab>", function()
		M.cycle_agenda_fold()
	end, { buffer = buf, silent = true })
end

-- Tab cycling helper functions
local refresh_tab_content -- Forward declaration

refresh_tab_content = function(buf, win, tab_index, view_id)
	local view_def = find_view(view_id)
	if not view_def then
		vim.notify("View not found: " .. view_id, vim.log.levels.ERROR)
		return
	end

	local lines, line_to_item = process_view(view_id, view_def)

	-- Update module state for fold cycling
	state.current_view_id = view_id
	state.line_to_item = line_to_item
	state.current_buf = buf
	state.current_win = win

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	vim.b[buf].agenda_line_to_item = line_to_item

	highlight_states(buf, lines)

	if vim.api.nvim_win_is_valid(win) then
		-- Set cursor to line 1 or last line if buffer is shorter
		local line_count = vim.api.nvim_buf_line_count(buf)
		local target_line = math.min(1, line_count)
		vim.api.nvim_win_set_cursor(win, { target_line, 0 })
	end
end

function M.show_tabbed_agenda()
	-- Dynamic fill based on screen width
	local fill_width = vim.o.columns > 120 and 0.7 or 0.9
	local fill_height = 0.5

	local buf, win = utils.open_window({
		title = "Agenda",
		method = config.agendas.window_method,
		filetype = "markdown",
		footer = "Loading...",
		fill = fill_width,
		fill_height = fill_height,
	})

	vim.b[buf].agenda_current_tab = 1
	vim.b[buf].agenda_line_to_item = {}

	-- Configure line wrapping with indentation for continuation lines
	vim.wo[win].wrap = true
	vim.wo[win].breakindent = true
	vim.wo[win].breakindentopt = "shift:7"

	-- Setup cycler for tab navigation
	local cycler = require("org_markdown.utils.cycler")

	-- Extract view IDs in order (sorted by order field)
	local ordered_views = config.get_ordered_views()
	local view_ids = {}
	for _, view in ipairs(ordered_views) do
		table.insert(view_ids, view.id)
	end

	local cycle_instance = cycler.create(buf, win, {
		items = view_ids,
		get_index = function(buf)
			return vim.b[buf].agenda_current_tab or 1
		end,
		set_index = function(buf, index)
			vim.b[buf].agenda_current_tab = index
		end,
		on_cycle = function(buf, win, view_id, index, total)
			refresh_tab_content(buf, win, index, view_id)
			-- Update window title
			local view_def = find_view(view_id)
			local new_title = "Agenda - " .. (view_def.title or view_id)
			utils.set_window_title(win, new_title)
		end,
		get_footer = function(view_id, index, total)
			return string.format("Tab [%d/%d] | <CR> cycle | <tab> fold | ] agenda | gf jump | q close", index, total)
		end,
		memory_id = "agenda",
	})

	cycle_instance:setup()

	-- Add keymap to cycle task state
	vim.keymap.set("n", "<CR>", function()
		local cursor = vim.api.nvim_win_get_cursor(win)
		local line_num = cursor[1]
		local item = vim.b[buf].agenda_line_to_item[line_num]
		if item then
			local new_heading, new_state = cycle_todo_in_file(item)
			if new_heading then
				-- Update the line in-place without refreshing (preserves DONE items until agenda closes)
				local current_line = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)[1]
				-- Extract the prefix (indentation + formatting) and replace just the heading part
				local prefix = current_line:match("^(%s*)")
				local updated_line = prefix .. new_heading:match("^#*%s*(.*)$")

				vim.bo[buf].modifiable = true
				vim.api.nvim_buf_set_lines(buf, line_num - 1, line_num, false, { updated_line })

				-- Re-apply syntax highlighting to the updated line
				local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
				highlight_states(buf, lines)

				vim.bo[buf].modifiable = false

				-- Update the item state in the mapping for consistency
				if item then
					item.state = new_state
				end
			end
		end
	end, { buffer = buf, silent = true })

	-- Add keymap to jump to file
	vim.keymap.set("n", "gf", function()
		local cursor = vim.api.nvim_win_get_cursor(win)
		local line_num = cursor[1]
		local item = vim.b[buf].agenda_line_to_item[line_num]
		if item then
			vim.api.nvim_win_close(win, true)
			vim.cmd("edit " .. vim.fn.fnameescape(item.file))
			vim.api.nvim_win_set_cursor(0, { item.line, 0 })
		end
	end, { buffer = buf, silent = true })

	vim.keymap.set("n", "<Tab>", function()
		M.cycle_agenda_fold()
	end, { buffer = buf, silent = true })

	-- Load content for the current tab (after setup has restored the saved tab)
	local current_tab = vim.b[buf].agenda_current_tab or 1
	local current_view_id = ordered_views[current_tab].id
	local current_view_def = find_view(current_view_id)
	refresh_tab_content(buf, win, current_tab, current_view_id)

	-- Update title to match the restored tab
	if current_view_def then
		utils.set_window_title(win, "Agenda - " .. (current_view_def.title or current_view_id))
	end
end

-- Public API: Expose scan_files for use by notifications module
-- Returns { tasks = [], calendar = [], all = [] }
function M.scan_files(file_patterns)
	return scan_files(file_patterns)
end

return M
