local config = require("org_markdown.config")
local datetime = require("org_markdown.utils.datetime")
local async = require("org_markdown.utils.async")

local M = {
	name = "calendar",
	description = "Sync events from Apple Calendar",
	sync_file = "~/org/calendar.md",

	default_config = {
		enabled = true,
		sync_file = "~/org/calendar.md",
		file_heading = "", -- Optional: YAML frontmatter heading (e.g., "Calendar")
		days_ahead = 30,
		days_behind = 0,
		calendars = {}, -- {} = all calendars
		exclude_calendars = { "org-markdown" }, -- Exclude push target by default
		include_time = true,
		include_end_time = true,
		heading_level = 1,
		auto_sync = false, -- Disabled by default (enable after creating "org-markdown" calendar)
		auto_sync_interval = 3600, -- 1 hour

		-- Push config (markdown → Calendar.app)
		push = {
			enabled = true,
			target_calendar = "org-markdown", -- Calendar to write to
		},
	},

	supports_auto_sync = true,
	command_name = "MarkdownSyncCalendar",
	keymap = "<leader>os",
}

-- =========================================================================
-- CALENDAR ACCESS (Swift)
-- =========================================================================

--- Get list of all available calendars from Calendar.app (using Swift helper)
--- @return table|nil, string|nil calendar_names, error
local function get_available_calendars()
	local manager = require("org_markdown.sync.manager")

	-- Get path to Swift helper script
	local script_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
	local swift_script = script_dir .. "/calendar_fetch.swift"

	-- Check if Swift script exists
	if vim.fn.filereadable(swift_script) == 0 then
		return nil, "Calendar Swift helper not found: " .. swift_script
	end

	-- Execute Swift script in list mode (async, non-blocking)
	local cmd = string.format("%s --list-calendars", vim.fn.shellescape(swift_script))
	local output, err = manager.execute_command(cmd)

	if not output then
		local error_msg = err or "Unknown error"
		if error_msg == "" or error_msg:match("^Command failed") then
			error_msg = "Calendar access denied. Grant permissions in System Preferences > Privacy & Security"
		end
		return nil, error_msg
	end

	if #output == 0 then
		return {}, nil
	end

	-- Each line is a calendar name
	return output, nil
end

--- Fetch events from Calendar.app for specified date range
--- @param calendars table List of calendar names to sync
--- @param start_date string YYYY-MM-DD format
--- @param end_date string YYYY-MM-DD format
--- @return table|nil, string|nil events, error
local function fetch_calendar_events(calendars, start_date, end_date)
	local manager = require("org_markdown.sync.manager")

	-- Convert YYYY-MM-DD to day offset from today
	local function days_from_today(iso_date)
		local year, month, day = iso_date:match("(%d%d%d%d)-(%d%d)-(%d%d)")
		local target_time = os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day) })
		local today_time = os.time()
		return math.floor((target_time - today_time) / 86400)
	end

	local days_behind = -days_from_today(start_date)
	local days_ahead = days_from_today(end_date)

	-- Build comma-separated calendar list
	local cal_list = table.concat(calendars, ",")

	-- Get path to Swift helper script
	local script_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
	local swift_script = script_dir .. "/calendar_fetch.swift"

	-- Check if Swift script exists
	if vim.fn.filereadable(swift_script) == 0 then
		return nil, "Calendar Swift helper not found: " .. swift_script
	end

	-- Execute Swift script (async, non-blocking)
	local cmd =
		string.format("%s %s %d %d", vim.fn.shellescape(swift_script), vim.fn.shellescape(cal_list), days_behind, days_ahead)

	local output, err = manager.execute_command(cmd)

	if not output then
		local error_msg = err or "Swift calendar helper failed"
		return nil, error_msg
	end

	return output, nil
end

-- =========================================================================
-- DATE PARSING
-- =========================================================================

--- Parse macOS date string to components
--- macOS returns: "Saturday, November 22, 2025 at 2:00:00 PM" or "Saturday, November 22, 2025"
--- @param date_str string macOS date format
--- @return table|nil date components { year, month, day, day_name, time }
local function parse_macos_date(date_str)
	-- Delegate to datetime module
	local result = datetime.parse_macos_date(date_str)
	if not result then
		vim.notify("Failed to parse date: " .. (date_str or "nil"), vim.log.levels.WARN)
	end
	return result
end

--- Split pipe-delimited string respecting escaped pipes (\|)
--- @param line string Pipe-delimited string with escaped pipes
--- @return table Parts with unescaped pipes
local function split_escaped_pipes(line)
	local parts = {}
	local current = ""
	local i = 1

	while i <= #line do
		local char = line:sub(i, i)

		if char == "\\" and i < #line and line:sub(i + 1, i + 1) == "|" then
			-- Escaped pipe - add the pipe to current part and skip the backslash
			current = current .. "|"
			i = i + 2
		elseif char == "|" then
			-- Unescaped pipe - split here
			table.insert(parts, current)
			current = ""
			i = i + 1
		else
			-- Regular character
			current = current .. char
			i = i + 1
		end
	end

	-- Add the last part
	table.insert(parts, current)

	return parts
end

--- Parse AppleScript output into events
--- @param output table Lines from AppleScript
--- @return table events Array of parsed events
local function parse_applescript_output(output)
	local events = {}

	for _, line in ipairs(output) do
		if line ~= "" then
			-- Format: CALENDAR|TITLE|START|END|ALLDAY|LOCATION|URL|NOTES|UID
			-- Use custom split to handle escaped pipes in titles/locations/notes
			local parts = split_escaped_pipes(line)
			if #parts >= 5 then
				local calendar = parts[1]
				local title = parts[2]
				local start_raw = parts[3]
				local end_raw = parts[4]
				local all_day_str = parts[5]

				-- Extended fields (may not be present in older output)
				local location = parts[6] and parts[6] ~= "" and parts[6] or nil
				local url = parts[7] and parts[7] ~= "" and parts[7] or nil
				local notes = parts[8] and parts[8] ~= "" and parts[8] or nil
				local uid = parts[9] and parts[9] ~= "" and parts[9] or nil

				local start_date = parse_macos_date(start_raw)
				local end_date = parse_macos_date(end_raw)

				if start_date then
					local event = {
						calendar = calendar,
						title = title,
						start = start_date,
						end_date = end_date,
						all_day = all_day_str == "true",
						location = location,
						url = url,
						notes = notes,
						uid = uid,
					}
					table.insert(events, event)
				end
			end
		end
	end

	return events
end

-- =========================================================================
-- FILTERING & UTILITIES
-- =========================================================================

--- Calculate date range based on config
--- @param plugin_config table Plugin configuration
--- @return string, string start_date, end_date (YYYY-MM-DD format)
local function calculate_date_range(plugin_config)
	local days_behind = plugin_config.days_behind or 0
	local days_ahead = plugin_config.days_ahead or 30

	-- Convert to datetime module format: offset (negative for past), days (total range)
	local offset = -days_behind
	local total_days = days_behind + days_ahead + 1

	return datetime.calculate_range({ days = total_days, offset = offset })
end

--- Filter calendars based on config (include/exclude lists)
--- @param available table All calendar names
--- @param plugin_config table Plugin configuration
--- @return table calendars_to_sync
local function filter_calendars(available, plugin_config)
	local calendars = plugin_config.calendars or {}
	local exclude = plugin_config.exclude_calendars or {}

	-- If calendars list is specified and not empty, use only those
	if #calendars > 0 then
		local filtered = {}
		for _, cal in ipairs(calendars) do
			if vim.tbl_contains(available, cal) and not vim.tbl_contains(exclude, cal) then
				table.insert(filtered, cal)
			end
		end
		return filtered
	end

	-- Otherwise use all available calendars, minus excluded ones
	local filtered = {}
	for _, cal in ipairs(available) do
		if not vim.tbl_contains(exclude, cal) then
			table.insert(filtered, cal)
		end
	end

	return filtered
end

--- Sanitize calendar name for use as tag
--- @param calendar_name string Calendar name
--- @return string sanitized tag
local function sanitize_tag(calendar_name)
	-- Remove special characters, spaces, convert to lowercase
	local tag = calendar_name
		:gsub("[@.]", "") -- Remove @ and .
		:gsub("%s+", "") -- Remove spaces
		:lower()
	return tag
end

-- =========================================================================
-- PUSH TO CALENDAR (markdown → Calendar.app)
-- =========================================================================

--- Extract Calendar UID from body metadata
--- @param body string|nil Body content
--- @return string|nil UID if found
local function extract_uid_from_body(body)
	if not body or body == "" then
		return nil
	end
	-- Match: **Calendar ID:** `<uid>`
	local uid = body:match("%*%*Calendar ID:%*%* `([^`]+)`")
	if uid then
		return uid
	end
	-- Also try: **ID:** `<uid>` (used by pull sync)
	uid = body:match("%*%*ID:%*%* `([^`]+)`")
	return uid
end

--- Extract body content below a heading
--- @param file string File path
--- @param line_num number Heading line number
--- @return string|nil Body content (may be empty string)
local function extract_body_below_heading(file, line_num)
	local utils = require("org_markdown.utils.utils")
	local parser = require("org_markdown.utils.parser")

	local lines = utils.read_lines(file)
	if not lines or line_num >= #lines then
		return nil
	end

	local body_lines = {}
	local i = line_num + 1

	-- Collect lines until next heading or end of file
	while i <= #lines do
		local line = lines[i]
		-- Stop at next heading
		if parser.parse_headline(line) then
			break
		end
		table.insert(body_lines, line)
		i = i + 1
	end

	return #body_lines > 0 and table.concat(body_lines, "\n") or nil
end

--- Update markdown item with Calendar UID after creation
--- @param file string File path
--- @param line_num number Heading line number
--- @param uid string Calendar UID
local function update_item_with_uid(file, line_num, uid)
	local utils = require("org_markdown.utils.utils")
	local parser = require("org_markdown.utils.parser")

	local lines = utils.read_lines(file)
	if not lines or not lines[line_num] then
		return
	end

	local timestamp = os.date("%Y-%m-%d %H:%M")

	-- Find insertion point (after heading, before next heading or end)
	local insert_pos = line_num + 1
	local found_existing = false

	while insert_pos <= #lines do
		local line = lines[insert_pos]

		-- Stop at next heading
		if parser.parse_headline(line) then
			break
		end

		-- Check if Calendar ID already exists
		if line:match("%*%*Calendar ID:%*%*") or line:match("%*%*ID:%*%*") then
			-- Update existing metadata
			lines[insert_pos] = string.format("**Calendar ID:** `%s`", uid)
			-- Check if next line is Last Synced
			if insert_pos + 1 <= #lines and lines[insert_pos + 1]:match("%*%*Last Synced:%*%*") then
				lines[insert_pos + 1] = string.format("**Last Synced:** %s", timestamp)
			else
				table.insert(lines, insert_pos + 1, string.format("**Last Synced:** %s", timestamp))
			end
			found_existing = true
			break
		end

		insert_pos = insert_pos + 1
	end

	if not found_existing then
		-- Insert new metadata block after heading
		local metadata_lines = {
			"",
			string.format("**Calendar ID:** `%s`", uid),
			string.format("**Last Synced:** %s", timestamp),
			"",
		}

		-- Insert metadata
		for i = #metadata_lines, 1, -1 do
			table.insert(lines, line_num + 1, metadata_lines[i])
		end
	end

	utils.write_lines(file, lines)
end

--- Create event in Calendar.app via Swift script
--- @param item table Item with title, start_date, start_time, end_time, all_day, body
--- @return string|nil, string|nil UID (success), error message (failure)
local function create_calendar_event(item)
	local manager = require("org_markdown.sync.manager")
	local plugin_config = config.sync and config.sync.plugins and config.sync.plugins.calendar or M.default_config
	local target_cal = plugin_config.push and plugin_config.push.target_calendar or "org-markdown"

	-- Get path to Swift script
	local script_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
	local swift_script = script_dir .. "/calendar_push.swift"

	if vim.fn.filereadable(swift_script) == 0 then
		return nil, "Calendar push script not found: " .. swift_script
	end

	-- Convert date to ISO format
	local start_iso = datetime.to_iso_string(item.start_date)
	if not start_iso then
		return nil, "Invalid start date for item: " .. item.title
	end

	-- Add time to start date
	if item.start_time and not item.all_day then
		start_iso = start_iso .. "T" .. item.start_time .. ":00"
	else
		start_iso = start_iso .. "T00:00:00"
	end

	-- Calculate end date/time
	local end_iso
	if item.end_date then
		-- Multi-day event
		end_iso = datetime.to_iso_string(item.end_date)
		if not end_iso then
			end_iso = start_iso
		else
			if item.end_time and not item.all_day then
				end_iso = end_iso .. "T" .. item.end_time .. ":00"
			else
				end_iso = end_iso .. "T23:59:59"
			end
		end
	elseif item.end_time and not item.all_day then
		-- Same-day event with end time
		end_iso = datetime.to_iso_string(item.start_date) .. "T" .. item.end_time .. ":00"
	else
		-- Use start as end (1-hour default or all-day)
		if item.all_day then
			end_iso = start_iso
		else
			-- Default 1-hour duration
			end_iso = start_iso
		end
	end

	-- Build command
	local cmd = string.format(
		"%s --create %s --title %s --start %s --end %s --all-day %s",
		vim.fn.shellescape(swift_script),
		vim.fn.shellescape(target_cal),
		vim.fn.shellescape(item.title),
		vim.fn.shellescape(start_iso),
		vim.fn.shellescape(end_iso),
		item.all_day and "true" or "false"
	)

	-- Add optional location and notes
	if item.location and item.location ~= "" then
		cmd = cmd .. " --location " .. vim.fn.shellescape(item.location)
	end
	if item.body and item.body ~= "" then
		cmd = cmd .. " --notes " .. vim.fn.shellescape(item.body)
	end

	-- Execute async (auto-awaits in coroutine context)
	local output, err = manager.execute_command(cmd)

	if not output then
		-- Check if it's a calendar creation error
		if err and err:match("does not allow calendars to be added") then
			vim.schedule(function()
				vim.notify(
					string.format(
						"Calendar '%s' not found. Please create it manually in Calendar.app or set push.target_calendar to an existing calendar.",
						target_cal
					),
					vim.log.levels.WARN
				)
			end)
		else
			vim.schedule(function()
				vim.notify(
					string.format("Failed to create event '%s': %s", item.title, err or "Unknown error"),
					vim.log.levels.ERROR
				)
			end)
		end
		return nil, err or "Failed to create event"
	end

	-- Get UID from first line (remove empty lines)
	for _, line in ipairs(output) do
		if line and line ~= "" then
			return line, nil -- Return UID
		end
	end

	return nil, "No UID returned from Swift script"
end

--- Update existing event in Calendar.app via Swift script
--- @param item table Item with uid, title, start_date, start_time, end_time, all_day, file, line
--- @return boolean, string|nil Success, error message (failure)
local function update_calendar_event(item)
	local manager = require("org_markdown.sync.manager")

	if not item.uid then
		return false, "No UID provided for update"
	end

	local plugin_config = config.sync and config.sync.plugins and config.sync.plugins.calendar or M.default_config
	local target_cal = plugin_config.push and plugin_config.push.target_calendar or "org-markdown"

	-- Get path to Swift script
	local script_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
	local swift_script = script_dir .. "/calendar_push.swift"

	if vim.fn.filereadable(swift_script) == 0 then
		return false, "Calendar push script not found"
	end

	-- Convert dates to ISO format
	local start_iso = datetime.to_iso_string(item.start_date)
	if not start_iso then
		return false, "Invalid start date"
	end

	if item.start_time and not item.all_day then
		start_iso = start_iso .. "T" .. item.start_time .. ":00"
	else
		start_iso = start_iso .. "T00:00:00"
	end

	local end_iso
	if item.end_date then
		end_iso = datetime.to_iso_string(item.end_date)
		if end_iso then
			if item.end_time and not item.all_day then
				end_iso = end_iso .. "T" .. item.end_time .. ":00"
			else
				end_iso = end_iso .. "T23:59:59"
			end
		else
			end_iso = start_iso
		end
	elseif item.end_time and not item.all_day then
		end_iso = datetime.to_iso_string(item.start_date) .. "T" .. item.end_time .. ":00"
	else
		end_iso = start_iso
	end

	-- Build command
	local cmd = string.format(
		"%s --update %s %s --title %s --start %s --end %s --all-day %s",
		vim.fn.shellescape(swift_script),
		vim.fn.shellescape(item.uid),
		vim.fn.shellescape(target_cal),
		vim.fn.shellescape(item.title),
		vim.fn.shellescape(start_iso),
		vim.fn.shellescape(end_iso),
		item.all_day and "true" or "false"
	)

	-- Execute async (auto-awaits in coroutine context)
	local output, err = manager.execute_command(cmd)

	if not output then
		-- Check if UID not found (event deleted in Calendar.app)
		if err and err:match("Event not found") then
			vim.schedule(function()
				vim.notify(
					string.format("Event '%s' not found in Calendar.app (may have been deleted). UID: %s", item.title, item.uid),
					vim.log.levels.WARN
				)
			end)
		else
			vim.schedule(function()
				vim.notify(
					string.format("Failed to update event '%s': %s", item.title, err or "Unknown error"),
					vim.log.levels.ERROR
				)
			end)
		end
		return false, err or "Failed to update event"
	end

	-- Update Last Synced timestamp
	vim.schedule(function()
		update_item_with_uid(item.file, item.line, item.uid)
	end)

	return true, nil
end

--- Push items from markdown files to Calendar.app (async)
--- Scans all markdown files for items with tracked dates, excluding sync file (calendar.md)
--- Runs asynchronously and doesn't block the UI
function M.push_to_calendar()
	async.run(function()
		local plugin_config = config.sync and config.sync.plugins and config.sync.plugins.calendar or M.default_config

		-- Check if push is enabled
		if not plugin_config or not plugin_config.push or not plugin_config.push.enabled then
			return
		end

		local queries = require("org_markdown.utils.queries")
		local utils = require("org_markdown.utils.utils")
		local parser = require("org_markdown.utils.parser")

		-- Get all markdown files
		local files = queries.find_markdown_files()

		-- Scan for items with tracked dates
		local items_to_push = {}
		local sync_filename = vim.fn.fnamemodify(vim.fn.expand(plugin_config.sync_file), ":t")

		for _, file in ipairs(files) do
			-- Skip sync file (calendar.md)
			local filename = vim.fn.fnamemodify(file, ":t")
			if filename == sync_filename then
				goto continue
			end

			local lines = utils.read_lines(file)
			for i, line in ipairs(lines) do
				local heading = parser.parse_headline(line)
				if heading and heading.tracked then
					-- Item has tracked date - add to sync list
					local body = extract_body_below_heading(file, i)
					local uid = extract_uid_from_body(body)

					-- Parse end date for multi-day events
					local end_date = nil
					local end_date_match = line:match("<[^>]+>%-%-<([^>]+)>")
					if end_date_match then
						-- Extract just the date part (YYYY-MM-DD)
						local end_date_str = end_date_match:match("(%d%d%d%d%-%d%d%-%d%d)")
						if end_date_str then
							end_date = datetime.parse_iso_date(end_date_str)
						end
					end

					table.insert(items_to_push, {
						title = heading.text,
						start_date = datetime.parse_iso_date(heading.tracked),
						end_date = end_date,
						start_time = heading.start_time,
						end_time = heading.end_time,
						all_day = heading.all_day,
						file = file,
						line = i,
						uid = uid,
						body = body,
					})
				end
			end

			::continue::
		end

		-- Push each item to Calendar.app (async)
		local results = { success = 0, failed = 0, created = 0, updated = 0 }

		for _, item in ipairs(items_to_push) do
			if item.uid then
				-- Update existing event
				local success, err = update_calendar_event(item)
				if success then
					results.success = results.success + 1
					results.updated = results.updated + 1
				else
					results.failed = results.failed + 1
				end
			else
				-- Create new event
				local uid, err = create_calendar_event(item)
				if uid then
					vim.schedule(function()
						update_item_with_uid(item.file, item.line, uid)
					end)
					results.success = results.success + 1
					results.created = results.created + 1
				else
					results.failed = results.failed + 1
				end
			end
		end

		-- Notify user
		if results.success > 0 or results.failed > 0 then
			local msg = string.format(
				"Calendar push: %d synced (%d created, %d updated), %d failed",
				results.success,
				results.created,
				results.updated,
				results.failed
			)
			vim.schedule(function()
				vim.notify(msg, results.failed > 0 and vim.log.levels.WARN or vim.log.levels.INFO)
			end)
		end
	end)
end

-- =========================================================================
-- MAIN PULL FUNCTION (bidirectional sync)
-- =========================================================================

function M.pull()
	local plugin_config = config.sync and config.sync.plugins and config.sync.plugins.calendar or M.default_config
	if not plugin_config or not plugin_config.enabled then
		return nil, "Calendar sync is disabled"
	end

	-- Validate macOS
	if vim.fn.has("mac") == 0 then
		return nil, "Calendar sync requires macOS (Calendar.app)"
	end

	-- ========== PULL: Calendar.app → calendar.md ==========

	-- Get available calendars
	local available, err = get_available_calendars()
	if not available then
		return nil, err
	end

	if #available == 0 then
		return nil, "No calendars found in Calendar.app"
	end

	-- Filter calendars
	local calendars_to_sync = filter_calendars(available, plugin_config)

	if #calendars_to_sync == 0 then
		return nil, "No calendars to sync after filtering"
	end

	-- Calculate date range
	local start_date, end_date = calculate_date_range(plugin_config)

	-- Fetch events
	local raw_output, err = fetch_calendar_events(calendars_to_sync, start_date, end_date)
	if not raw_output then
		return nil, err
	end

	-- Parse events
	local raw_events = parse_applescript_output(raw_output)

	-- Convert to standard event format
	local events = {}
	for _, raw in ipairs(raw_events) do
		-- Build body with metadata and notes
		local body_parts = {}

		-- Add metadata section
		local metadata = {}
		if raw.location and raw.location ~= "" then
			table.insert(metadata, "**Location:** " .. raw.location)
		end
		if raw.url and raw.url ~= "" then
			table.insert(metadata, "**URL:** " .. raw.url)
		end
		if raw.uid and raw.uid ~= "" then
			table.insert(metadata, "**ID:** `" .. raw.uid .. "`")
		end

		if #metadata > 0 then
			table.insert(body_parts, table.concat(metadata, "  \n"))
		end

		-- Add notes if present
		if raw.notes and raw.notes ~= "" then
			if #body_parts > 0 then
				table.insert(body_parts, "")
			end
			table.insert(body_parts, raw.notes)
		end

		local event = {
			title = raw.title,
			start_date = raw.start,
			end_date = raw.end_date,
			start_time = raw.start.time,
			end_time = raw.end_date and raw.end_date.time,
			all_day = raw.all_day,
			tags = { sanitize_tag(raw.calendar) },
			body = #body_parts > 0 and table.concat(body_parts, "\n") or nil,
		}
		table.insert(events, event)
	end

	local pull_result = {
		events = events,
		stats = {
			count = #events,
			calendars = calendars_to_sync,
			date_range = start_date .. " to " .. end_date,
		},
	}

	-- ========== PUSH: markdown → Calendar.app ==========
	-- Push user markdown items to Calendar.app (if enabled)
	if plugin_config.push and plugin_config.push.enabled then
		M.push_to_calendar()
	end

	return pull_result
end

return M
