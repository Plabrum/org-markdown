-- org_markdown/agenda/calendar.lua + tasks.lua
local config = require("org_markdown.config")
local utils = require("org_markdown.utils")

local M = {}

local ns = vim.api.nvim_create_namespace("org_markdown_agenda")

-- Matchers
local function parse_heading(line)
	local state, priority, text = line:match("^#+%s+(%u+)%s+(%[%#%u%])?%s*(.-)%s*$")
	if not state or (state ~= "TODO" and state ~= "IN_PROGRESS") then
		return nil
	end
	local tags = {}
	for tag in line:gmatch(":([%w_-]+):") do
		table.insert(tags, tag)
	end
	local pri = priority and priority:match("%[(#%u)%]") or nil
	return state, pri, text, tags
end

local function extract_date(line)
	local tracked = line:match("<(%d%d%d%d%-%d%d%-%d%d)>")
	local untracked = line:match("%[(%d%d%d%d%-%d%d%-%d%d)%]")
	return tracked, untracked
end

-- Returns table of agenda items
local function scan_files()
	local files = utils.find_markdown_files()
	local agenda_items = {}

	for _, file in ipairs(files) do
		local lines = utils.read_lines(file)
		for i, line in ipairs(lines) do
			local state, priority, text, tags = parse_heading(line)
			if state then
				local tracked_date, _ = extract_date(line)
				if tracked_date then
					table.insert(agenda_items, {
						title = text,
						state = state,
						priority = priority,
						date = tracked_date,
						line = i,
						file = file,
						tags = tags,
						source = vim.fn.fnamemodify(file, ":t:r"),
					})
				end
			end
		end
	end

	return agenda_items
end

local function format_date(date_str)
	local y, m, d = date_str:match("(%d+)%-(%d+)%-(%d+)")
	local time = os.time({ year = y, month = m, day = d })
	return os.date("%A %d %b", time)
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
	local items = scan_files()
	local grouped = {}
	for _, d in ipairs(get_next_seven_days()) do
		grouped[d] = {}
	end

	for _, item in ipairs(items) do
		if grouped[item.date] then
			table.insert(grouped[item.date], item)
		end
	end

	local lines = {}
	table.insert(lines, "Agenda (next 7 days)")
	table.insert(lines, "")

	for _, date in ipairs(get_next_seven_days()) do
		table.insert(lines, "  " .. format_date(date))
		local day_items = grouped[date]
		if #day_items == 0 then
			table.insert(lines, "    (no entries)")
		else
			for _, entry in ipairs(day_items) do
				local prefix = string.format("    - [%s] %s", entry.state, entry.title)
				table.insert(lines, prefix)
			end
		end
		table.insert(lines, "")
	end

	return lines
end

local function get_task_lines()
	local items = scan_files()
	table.sort(items, priority_sort)

	local lines = { "AgendaTask (by priority)", "" }
	for _, item in ipairs(items) do
		local p = item.priority and string.format("[#%s]", item.priority) or ""
		local line = string.format("  %s %-12s %s (%s)", p, item.state, item.title, vim.fn.fnamemodify(item.file, ":t"))
		table.insert(lines, line)
	end

	return lines
end

function M.show_calendar()
	local lines = get_calendar_lines()
	local buf, win = utils.open_window({
		title = "Agenda Calendar",
		filetype = "markdown",
		method = "float",
		footer = "Press q to close",
	})
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
end

function M.show_tasks()
	local lines = get_task_lines()
	local buf, win = utils.open_window({
		title = "Agenda Task",
		filetype = "markdown",
		method = "float",
		footer = "Press q to close",
	})
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
end

function M.show_combined()
	local task_lines = get_task_lines()
	local calendar_lines = get_calendar_lines()

	-- Open window first to get its actual width
	local buf, win = utils.open_window({
		title = "Agenda",
		filetype = "markdown",
		method = "float",
		footer = "Press q to close",
	})

	-- Get actual window width
	local win_width = vim.api.nvim_win_get_width(win)
	local separator = string.rep("-", win_width)

	-- Add separator and combine
	table.insert(task_lines, separator)
	local combined_lines = vim.list_extend(task_lines, calendar_lines)

	-- Display content
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, combined_lines)
	vim.bo[buf].modifiable = false
end

return M
