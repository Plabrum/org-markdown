-- org_markdown/agenda/calendar.lua + tasks.lua
local config = require("org_markdown.config")
local utils = require("org_markdown.utils")
local parser = require("org_markdown.parser")
local formatter = require("org_markdown.formatter")
local queries = require("org_markdown.queries")

local M = {}
vim.api.nvim_set_hl(0, "OrgTodo", { fg = "#ff5f5f", bold = true })
vim.api.nvim_set_hl(0, "OrgInProgress", { fg = "#f0c000", bold = true })
vim.api.nvim_set_hl(0, "OrgDone", { fg = "#5fd75f", bold = true })
vim.api.nvim_set_hl(0, "OrgTitle", { fg = "#87afff", bold = true })

local function highlight_states(buf, lines)
	for i, line in ipairs(lines) do
		if line:match("TODO") then
			vim.api.nvim_buf_add_highlight(buf, -1, "OrgTodo", i - 1, 0, -1)
		elseif line:match("IN_PROGRESS") then
			vim.api.nvim_buf_add_highlight(buf, -1, "OrgInProgress", i - 1, 0, -1)
		elseif line:match("DONE") then
			vim.api.nvim_buf_add_highlight(buf, -1, "OrgDone", i - 1, 0, -1)
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
			local heading = parser.parse_heading(line)
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
			end
		end

		table.insert(lines, "")
	end

	return lines
end

local function get_task_lines()
	local items = scan_files().tasks
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
	highlight_states(buf, lines)
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
	highlight_states(buf, lines)
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
	table.insert(task_lines, "")
	table.insert(task_lines, separator)
	local combined_lines = vim.list_extend(task_lines, calendar_lines)

	-- Display content
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, combined_lines)
	highlight_states(buf, task_lines)
	vim.bo[buf].modifiable = false
end

return M
