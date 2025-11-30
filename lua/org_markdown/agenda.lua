-- org_markdown/agenda/calendar.lua + tasks.lua
local config = require("org_markdown.config")
local utils = require("org_markdown.utils.utils")
local parser = require("org_markdown.utils.parser")
local formatter = require("org_markdown.utils.formatter")
local queries = require("org_markdown.utils.queries")
local editing = require("org_markdown.utils.editing")
local agenda_formatters = require("org_markdown.agenda_formatters")
local datetime = require("org_markdown.utils.datetime")
local frontmatter = require("org_markdown.utils.frontmatter")

local M = {}
vim.api.nvim_set_hl(0, "OrgTodo", { fg = "#ff5f5f", bold = true })
vim.api.nvim_set_hl(0, "OrgInProgress", { fg = "#f0c000", bold = true })
vim.api.nvim_set_hl(0, "OrgDone", { fg = "#5fd75f", bold = true })
vim.api.nvim_set_hl(0, "OrgTitle", { fg = "#87afff", bold = true })

-- Helper to find view by ID
local function find_view(view_id)
	for _, view in ipairs(config.agendas.views) do
		if view.id == view_id then
			return view
		end
	end
	return nil
end

-- Helper function to cycle TODO state in a file
local function cycle_todo_in_file(item)
	local lines = utils.read_lines(item.file)
	local line = lines[item.line]
	if not line then
		return false
	end

	-- Try to cycle the line
	local new_lines = editing.cycle_checkbox_inline(line, config.checkbox_states)
		or editing.cycle_status_inline(line, config.status_states)

	if new_lines and new_lines[1] then
		lines[item.line] = new_lines[1]
		utils.write_lines(item.file, lines)
		return true
	end

	return false
end

local function highlight_states(buf, lines)
	for i, line in ipairs(lines) do
		-- Find the position of each state word and highlight only that word
		local todo_start, todo_end = line:find("TODO")
		if todo_start then
			vim.api.nvim_buf_add_highlight(buf, -1, "OrgTodo", i - 1, todo_start - 1, todo_end)
		end

		local inprog_start, inprog_end = line:find("IN_PROGRESS")
		if inprog_start then
			vim.api.nvim_buf_add_highlight(buf, -1, "OrgInProgress", i - 1, inprog_start - 1, inprog_end)
		end

		local done_start, done_end = line:find("DONE")
		if done_start then
			vim.api.nvim_buf_add_highlight(buf, -1, "OrgDone", i - 1, done_start - 1, done_end)
		end
	end
end

-- Returns table of agenda items
local function scan_files()
	local files = queries.find_markdown_files()
	local agenda_items = { tasks = {}, calendar = {} }

	for _, file in ipairs(files) do
		local lines = utils.read_lines(file)
		local display_name = frontmatter.get_display_name(file, lines)

		for i, line in ipairs(lines) do
			local heading = parser.parse_headline(line)
			if heading and heading.state then
				table.insert(agenda_items.tasks, {
					title = heading.text,
					state = heading.state,
					priority = heading.priority,
					date = heading.tracked,
					start_time = heading.start_time,
					end_time = heading.end_time,
					all_day = heading.all_day,
					line = i,
					file = file,
					tags = heading.tags,
					source = display_name,
				})
			end
			if heading and heading.tracked then
				table.insert(agenda_items.calendar, {
					title = heading.text,
					state = heading.state,
					priority = heading.priority,
					date = heading.tracked,
					start_time = heading.start_time,
					end_time = heading.end_time,
					all_day = heading.all_day,
					line = i,
					file = file,
					tags = heading.tags,
					source = display_name,
				})
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

	-- State filter
	if filters.states and #filters.states > 0 then
		if not item.state or not vim.tbl_contains(filters.states, item.state) then
			return false
		end
	end

	-- Priority filter
	if filters.priorities and #filters.priorities > 0 then
		local priority_letter = item.priority
		if not priority_letter or not vim.tbl_contains(filters.priorities, priority_letter) then
			return false
		end
	end

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

-- Apply filters to a list of items
local function apply_filters(items, filters)
	if not filters then
		return items
	end

	local filtered = {}
	for _, item in ipairs(items) do
		if filter_item(item, filters) then
			table.insert(filtered, item)
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
			return agenda_formatters.format_blocks(item, "    ")
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
			return agenda_formatters.format_timeline(item, "    ")
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
local function render_view(groups, view_def)
	local lines = {}
	local line_to_item = {}

	local format_name = (view_def.display and view_def.display.format) or "timeline"
	local fmt = formatters[format_name] or formatters.timeline

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

		for _, item in ipairs(group.items) do
			local item_line = group.key and fmt.grouped(item) or fmt.flat(item)
			-- For multi-line formatters, split and add each line
			for line in item_line:gmatch("[^\n]+") do
				table.insert(lines, line)
				-- Only store item on first line
				if not line_to_item[#lines - 1] or line_to_item[#lines - 1] ~= item then
					line_to_item[#lines] = item
				end
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
		-- Combine both, removing duplicates
		local combined = {}
		local seen = {}
		for _, item in ipairs(all_data.tasks) do
			local key = item.file .. ":" .. item.line
			if not seen[key] then
				table.insert(combined, item)
				seen[key] = true
			end
		end
		for _, item in ipairs(all_data.calendar) do
			local key = item.file .. ":" .. item.line
			if not seen[key] then
				table.insert(combined, item)
				seen[key] = true
			end
		end
		return combined
	else
		return all_data.tasks -- Default fallback
	end
end

-- Process a view through the filter → sort → group → render pipeline
local function process_view(view_id, view_def)
	-- 1. Get source data
	local all_data = scan_files()
	local items = get_source_items(all_data, view_def.source or "tasks")

	-- 2. Filter → Sort → Group
	items = apply_filters(items, view_def.filters)
	items = apply_sort(items, view_def.sort)
	local groups = group_items(items, view_def.group_by)

	-- 3. Render
	return render_view(groups, view_def)
end

-- Generic view function that works with any view definition
function M.show_view(view_id)
	local view_def = find_view(view_id)
	if not view_def then
		vim.notify("Unknown view: " .. view_id, vim.log.levels.ERROR)
		return
	end

	local lines, line_to_item = process_view(view_id, view_def)

	local buf, win = utils.open_window({
		title = "Agenda - " .. (view_def.title or view_id),
		method = config.agendas.window_method,
		filetype = "markdown",
		footer = "status cycle <tab> | <CR> jump | q close",
	})

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	highlight_states(buf, lines)
	vim.bo[buf].modifiable = false

	-- Configure line wrapping with indentation for continuation lines
	vim.wo[win].wrap = true
	vim.wo[win].breakindent = true
	vim.wo[win].breakindentopt = "shift:12"

	-- Add keymap to jump to file
	vim.keymap.set("n", "<CR>", function()
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

	-- Add keymap to cycle TODO state
	vim.keymap.set("n", "<Tab>", function()
		local cursor = vim.api.nvim_win_get_cursor(win)
		local line_num = cursor[1]
		local item = line_to_item[line_num]
		if item and cycle_todo_in_file(item) then
			-- Refresh the view
			local new_lines, new_line_to_item = process_view(view_id, view_def)
			vim.bo[buf].modifiable = true
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
			vim.bo[buf].modifiable = false
			highlight_states(buf, new_lines)
			line_to_item = new_line_to_item
			-- Restore cursor position
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_set_cursor(win, cursor)
			end
		end
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

	-- Get first view title for initial window title
	local first_view = config.agendas.views[1]
	local initial_title = "Agenda - " .. (first_view.title or first_view.id)

	local buf, win = utils.open_window({
		title = initial_title,
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
	vim.wo[win].breakindentopt = "shift:12"

	-- Setup cycler for tab navigation
	local cycler = require("org_markdown.utils.cycler")

	-- Extract view IDs in order (preserves config order)
	local view_ids = {}
	for _, view in ipairs(config.agendas.views) do
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
			return string.format("Tab [%d/%d] | status cycle <tab> | agenda cycle ] | <CR> jump | q close", index, total)
		end,
		memory_id = "agenda",
	})

	cycle_instance:setup()

	vim.keymap.set("n", "<CR>", function()
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
		local cursor = vim.api.nvim_win_get_cursor(win)
		local line_num = cursor[1]
		local item = vim.b[buf].agenda_line_to_item[line_num]
		if item and cycle_todo_in_file(item) then
			-- Refresh the current tab
			local current_tab = vim.b[buf].agenda_current_tab or 1
			local current_view_id = config.agendas.views[current_tab].id
			refresh_tab_content(buf, win, current_tab, current_view_id)
			-- Restore cursor position
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_set_cursor(win, cursor)
			end
		end
	end, { buffer = buf, silent = true })

	-- Get first view from config (preserves order)
	local first_view_id = config.agendas.views[1].id
	refresh_tab_content(buf, win, 1, first_view_id)
end

return M
