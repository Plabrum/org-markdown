-- org_markdown/agenda/calendar.lua + tasks.lua
local config = require("org_markdown.config")
local utils = require("org_markdown.utils.utils")
local parser = require("org_markdown.utils.parser")
local formatter = require("org_markdown.utils.formatter")
local queries = require("org_markdown.utils.queries")

local M = {}
vim.api.nvim_set_hl(0, "OrgTodo", { fg = "#ff5f5f", bold = true })
vim.api.nvim_set_hl(0, "OrgInProgress", { fg = "#f0c000", bold = true })
vim.api.nvim_set_hl(0, "OrgDone", { fg = "#5fd75f", bold = true })
vim.api.nvim_set_hl(0, "OrgTitle", { fg = "#87afff", bold = true })

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
		for i, line in ipairs(lines) do
			local heading = parser.parse_headline(line)
			if heading and heading.state then
				table.insert(agenda_items.tasks, {
					title = heading.text,
					state = heading.state,
					priority = heading.priority,
					date = heading.tracked,
					line = i,
					file = file,
					tags = heading.tags,
					source = vim.fn.fnamemodify(file, ":t:r"),
				})
			end
			if heading and heading.tracked then
				table.insert(agenda_items.calendar, {
					title = heading.text,
					state = heading.state,
					priority = heading.priority,
					date = heading.tracked,
					line = i,
					file = file,
					tags = heading.tags,
					source = vim.fn.fnamemodify(file, ":t:r"),
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

	if date_range_spec.days then
		-- Relative date range: { days = N, offset = 0 }
		local offset = date_range_spec.offset or 0
		local today = os.time()
		local start_date = os.date("%Y-%m-%d", today + offset * 86400)
		local end_date = os.date("%Y-%m-%d", today + (offset + date_range_spec.days - 1) * 86400)
		return { from = start_date, to = end_date }
	else
		-- Absolute date range: { from = "YYYY-MM-DD", to = "YYYY-MM-DD" }
		return date_range_spec
	end
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

	local result
	if field == "priority" then
		local rank = sort_spec.priority_rank or { A = 1, B = 2, C = 3, Z = 99 }
		local pa = a.priority or "Z"
		local pb = b.priority or "Z"
		result = (rank[pa] or 99) < (rank[pb] or 99)
	elseif field == "date" then
		result = (a.date or "9999-99-99") < (b.date or "9999-99-99")
	elseif field == "state" then
		result = (a.state or "") < (b.state or "")
	elseif field == "title" then
		result = (a.title or "") < (b.title or "")
	elseif field == "file" then
		result = (a.source or "") < (b.source or "")
	end

	return ascending and result or not result
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
	return result
end

-- Formatter registry with built-in presets
local formatters = {
	default = {
		flat = function(item)
			-- Current get_task_lines() format
			local p = item.priority and string.format("[#%s] ", item.priority) or ""
			local state = string.format("%-12s ", item.state or "")
			local filename = string.format("(%s)", vim.fn.fnamemodify(item.file, ":t"))
			return string.format("%s%s%s %s", p, state, item.title, filename)
		end,

		grouped = function(item)
			-- Current get_calendar_lines() format
			local parts = {}
			if item.state then
				table.insert(parts, item.state)
			end
			if item.priority then
				table.insert(parts, string.format("[%s]", item.priority))
			end

			local label = #parts > 0 and (table.concat(parts, " ") .. " ") or ""
			return string.format("    • %s%s", label, item.title)
		end,

		group_header = function(group_key, group_by)
			if group_by == "date" then
				return "  " .. formatter.format_date(group_key)
			else
				return group_key
			end
		end,
	},

	compact = {
		flat = function(item)
			local state = item.state or ""
			return string.format("%s %s", state, item.title)
		end,

		grouped = function(item)
			return string.format("  • %s", item.title)
		end,

		group_header = function(group_key)
			return group_key
		end,
	},

	detailed = {
		flat = function(item)
			local parts = { string.format("▸ %s", item.title) }
			local meta = {}
			if item.state then
				table.insert(meta, "State: " .. item.state)
			end
			if item.priority then
				table.insert(meta, "Priority: #" .. item.priority)
			end
			if item.date then
				table.insert(meta, "Date: " .. item.date)
			end
			if #meta > 0 then
				table.insert(parts, "  " .. table.concat(meta, " | "))
			end
			return table.concat(parts, "\n")
		end,

		grouped = function(item)
			return string.format("  ▸ %s", item.title)
		end,

		group_header = function(group_key, group_by)
			if group_by == "date" then
				return "  " .. formatter.format_date(group_key)
			else
				return group_key
			end
		end,
	},
}

-- Render a view from grouped items
local function render_view(groups, view_def)
	local lines = { view_def.title or "Agenda View", "" }
	local line_to_item = {}

	local format_name = (view_def.display and view_def.display.format) or "default"
	local fmt = formatters[format_name] or formatters.default

	for _, group in ipairs(groups) do
		if group.key then
			-- Add group header
			table.insert(lines, fmt.group_header(group.key, view_def.group_by))
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
	local view_def = config.agendas.views and config.agendas.views[view_id]
	if not view_def then
		vim.notify("Unknown view: " .. view_id, vim.log.levels.ERROR)
		return
	end

	local lines, line_to_item = process_view(view_id, view_def)

	local buf, win = utils.open_window({
		title = view_def.title or view_id,
		method = config.agendas.window_method,
		filetype = "markdown",
		footer = "Press <CR> to jump to file, q to close",
	})

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	highlight_states(buf, lines)
	vim.bo[buf].modifiable = false

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
end

local function get_next_seven_days()
	local today = os.time()
	local days = {}
	for i = 0, 6 do
		local t = os.date("%Y-%m-%d", today + i * 86400)
		table.insert(days, t)
	end
	return days
end

------------------display --------------------------
local function priority_sort(a, b)
	local rank = { A = 1, B = 2, C = 3, Z = 99 }
	local pa = a.priority or "Z"
	local pb = b.priority or "Z"
	return rank[pa] < rank[pb]
end

local function get_calendar_lines()
	local items = scan_files().calendar

	-- Group entries by date
	local grouped = {}
	for _, d in ipairs(get_next_seven_days()) do
		grouped[d] = {}
	end
	for _, item in ipairs(items) do
		if grouped[item.date] then
			table.insert(grouped[item.date], item)
		end
	end

	-- Begin output
	local lines = {}
	local line_to_item = {} -- Maps display line number to agenda item
	table.insert(lines, "Agenda (next 7 days)")
	table.insert(lines, "")

	-- Render each day with entries
	for _, date in ipairs(get_next_seven_days()) do
		table.insert(lines, "  " .. formatter.format_date(date))
		local day_items = grouped[date]

		if #day_items == 0 then
			table.insert(lines, "    (no entries)")
		else
			for _, entry in ipairs(day_items) do
				local parts = {}

				if entry.state then
					table.insert(parts, string.format("%s", entry.state))
				end
				if entry.priority then
					table.insert(parts, string.format("[%s]", entry.priority))
				end

				local label = #parts > 0 and (table.concat(parts, " ") .. " ") or ""
				local prefix = string.format("    • %s%s", label, entry.title)
				table.insert(lines, prefix)
				line_to_item[#lines] = entry -- Store the mapping
			end
		end

		table.insert(lines, "")
	end

	return lines, line_to_item
end

local function get_task_lines()
	local items = scan_files().tasks
	table.sort(items, priority_sort)

	local lines = { "AgendaTask (by priority)", "" }
	local line_to_item = {} -- Maps display line number to agenda item
	for _, item in ipairs(items) do
		local p = item.priority and string.format("[#%s] ", item.priority) or ""
		local state = string.format("%-12s ", item.state)
		local filename = string.format("(%s)", vim.fn.fnamemodify(item.file, ":t"))
		local line = string.format("%s%s%s %s", p, state, item.title, filename)
		table.insert(lines, line)
		line_to_item[#lines] = item -- Store the mapping
	end

	return lines, line_to_item
end

-- Tab cycling helper functions
local refresh_tab_content -- Forward declaration

local function cycle_tab(buf, win, direction)
	local tab_config = config.agendas.tabbed_view or { views = { "tasks", "calendar" } }
	local view_ids = tab_config.views
	local num_tabs = #view_ids

	local current = vim.b[buf].agenda_current_tab or 1
	local next_tab

	if direction > 0 then
		next_tab = (current % num_tabs) + 1
	else
		next_tab = current == 1 and num_tabs or (current - 1)
	end

	vim.b[buf].agenda_current_tab = next_tab
	refresh_tab_content(buf, win, next_tab, view_ids[next_tab])
end

refresh_tab_content = function(buf, win, tab_index, view_id)
	local view_def = config.agendas.views and config.agendas.views[view_id]
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

	local tab_config = config.agendas.tabbed_view or { views = { "tasks", "calendar" } }
	local num_tabs = #tab_config.views
	local footer = string.format(
		"Tab [%d/%d] %s | ] next | [ prev | <CR> jump | q close",
		tab_index,
		num_tabs,
		view_def.title or view_id
	)

	local win_config = vim.api.nvim_win_get_config(win)
	if win_config.relative and win_config.relative ~= "" then
		win_config.footer = footer
		vim.api.nvim_win_set_config(win, win_config)
	else
		vim.wo[win].statusline = footer
	end

	if vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_set_cursor(win, { 3, 0 })
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

	vim.keymap.set("n", "]", function()
		cycle_tab(buf, win, 1)
	end, { buffer = buf, silent = true })

	vim.keymap.set("n", "[", function()
		cycle_tab(buf, win, -1)
	end, { buffer = buf, silent = true })

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

	-- Get first view from config
	local tab_config = config.agendas.tabbed_view or { views = { "tasks", "calendar" } }
	local first_view_id = tab_config.views[1]
	refresh_tab_content(buf, win, 1, first_view_id)
end

return M
