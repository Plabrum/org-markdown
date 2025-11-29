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
local refresh_tab_content  -- Forward declaration

local function cycle_tab(buf, win, direction)
	local current = vim.b[buf].agenda_current_tab or 1
	local next_tab
	if direction > 0 then
		next_tab = (current == 2) and 1 or 2
	else
		next_tab = (current == 1) and 2 or 1
	end
	vim.b[buf].agenda_current_tab = next_tab
	refresh_tab_content(buf, win, next_tab)
end

refresh_tab_content = function(buf, win, tab_index)
	local lines, line_to_item
	if tab_index == 1 then
		lines, line_to_item = get_task_lines()
	else
		lines, line_to_item = get_calendar_lines()
	end

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	vim.b[buf].agenda_line_to_item = line_to_item

	highlight_states(buf, lines)

	local tab_name = tab_index == 1 and "Tasks" or "Calendar"
	local footer = string.format("Tab [%d/2] %s | ] next | [ prev | <CR> jump | q close", tab_index, tab_name)

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

function M.show_calendar()
	local lines, line_to_item = get_calendar_lines()
	local buf, win = utils.open_window({
		title = "Agenda Calendar",
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

function M.show_tasks()
	local lines, line_to_item = get_task_lines()
	local buf, win = utils.open_window({
		title = "Agenda Task",
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

	refresh_tab_content(buf, win, 1)
end

return M
