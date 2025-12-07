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
-- SETUP & VALIDATION
-- =========================================================================

function M.setup(plugin_config)
	-- Validate macOS
	if vim.fn.has("mac") == 0 then
		vim.notify("Calendar sync requires macOS (Calendar.app)", vim.log.levels.WARN)
		return false
	end
	return true
end

-- =========================================================================
-- CALENDAR ACCESS (Swift)
-- =========================================================================

--- Get list of all available calendars from Calendar.app (using Swift helper)
--- @return table|nil, string|nil calendar_names, error
local function get_available_calendars()
	-- Get path to Swift helper script
	local script_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
	local swift_script = script_dir .. "/calendar_fetch.swift"

	-- Check if Swift script exists
	if vim.fn.filereadable(swift_script) == 0 then
		return nil, "Calendar Swift helper not found: " .. swift_script
	end

	-- Execute Swift script in list mode
	local cmd = string.format("%s --list-calendars", vim.fn.shellescape(swift_script))
	local output = vim.fn.systemlist(cmd)

	if vim.v.shell_error ~= 0 then
		local error_msg = table.concat(output, "\n")
		if error_msg == "" then
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

	vim.notify(string.format("Fetching events from %d calendar(s)...", #calendars), vim.log.levels.INFO)

	-- Execute Swift script (much faster than AppleScript!)
	local cmd =
		string.format("%s %s %d %d", vim.fn.shellescape(swift_script), vim.fn.shellescape(cal_list), days_behind, days_ahead)

	local output = vim.fn.systemlist(cmd)

	if vim.v.shell_error ~= 0 then
		local error_msg = table.concat(output, "\n")
		if error_msg == "" then
			error_msg = "Swift calendar helper failed (exit code: " .. vim.v.shell_error .. ")"
		end
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

--- Parse AppleScript output into events
--- @param output table Lines from AppleScript
--- @return table events Array of parsed events
local function parse_applescript_output(output)
	local events = {}

	for _, line in ipairs(output) do
		if line ~= "" then
			-- Format: CALENDAR|TITLE|START|END|ALLDAY|LOCATION|URL|NOTES|UID
			local parts = vim.split(line, "|", { plain = true })
			if #parts >= 5 then
				local calendar = parts[1]
				local title = parts[2]:gsub("\\|", "|") -- Unescape pipes
				local start_raw = parts[3]
				local end_raw = parts[4]
				local all_day_str = parts[5]

				-- Extended fields (may not be present in older output)
				local location = parts[6] and parts[6] ~= "" and parts[6]:gsub("\\|", "|") or nil
				local url = parts[7] and parts[7] ~= "" and parts[7] or nil
				local notes = parts[8] and parts[8] ~= "" and parts[8]:gsub("\\|", "|") or nil
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

--- Execute Swift script asynchronously
--- @param cmd string Command to execute
--- @return table Promise that resolves to output or rejects with error
local function execute_swift_async(cmd)
	return async.promise(function(resolve, reject)
		vim.fn.jobstart(cmd, {
			stdout_buffered = true,
			stderr_buffered = true,
			on_stdout = function(_, data)
				if data and #data > 0 then
					resolve(data)
				end
			end,
			on_stderr = function(_, data)
				if data and #data > 0 then
					local error_msg = table.concat(data, "\n")
					reject(error_msg)
				end
			end,
			on_exit = function(_, exit_code)
				if exit_code ~= 0 then
					reject("Swift script failed with exit code: " .. exit_code)
				end
			end,
		})
	end)
end

--- Create event in Calendar.app via Swift script (async)
--- @param item table Item with title, start_date, start_time, end_time, all_day, body
--- @return table Promise that resolves to UID or rejects with error
local function create_calendar_event_async(item)
	return async.promise(function(resolve, reject)
		local plugin_config = config.sync and config.sync.plugins and config.sync.plugins.calendar or M.default_config
		local target_cal = plugin_config.push and plugin_config.push.target_calendar or "org-markdown"

		-- Get path to Swift script
		local script_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
		local swift_script = script_dir .. "/calendar_push.swift"

		if vim.fn.filereadable(swift_script) == 0 then
			return reject("Calendar push script not found: " .. swift_script)
		end

		-- Convert date to ISO format
		local start_iso = datetime.to_iso_string(item.start_date)
		if not start_iso then
			return reject("Invalid start date for item: " .. item.title)
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

		-- Execute async
		execute_swift_async(cmd)
			:then_(function(output)
				if output and #output > 0 then
					-- Get UID from first line (remove empty lines)
					for _, line in ipairs(output) do
						if line and line ~= "" then
							resolve({ uid = line, item = item })
							return
						end
					end
					reject("No UID returned from Swift script")
				else
					reject("No output from Swift script")
				end
			end)
			:catch_(function(error_msg)
				-- Check if it's a calendar creation error
				if error_msg:match("does not allow calendars to be added") then
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
						vim.notify(string.format("Failed to create event '%s': %s", item.title, error_msg), vim.log.levels.ERROR)
					end)
				end
				reject(error_msg)
			end)
	end)
end

--- Update existing event in Calendar.app via Swift script (async)
--- @param item table Item with uid, title, start_date, start_time, end_time, all_day
--- @return table Promise that resolves to true or rejects with error
local function update_calendar_event_async(item)
	return async.promise(function(resolve, reject)
		if not item.uid then
			return reject("No UID provided for update")
		end

		local plugin_config = config.sync and config.sync.plugins and config.sync.plugins.calendar or M.default_config
		local target_cal = plugin_config.push and plugin_config.push.target_calendar or "org-markdown"

		-- Get path to Swift script
		local script_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
		local swift_script = script_dir .. "/calendar_push.swift"

		if vim.fn.filereadable(swift_script) == 0 then
			return reject("Calendar push script not found")
		end

		-- Convert dates to ISO format
		local start_iso = datetime.to_iso_string(item.start_date)
		if not start_iso then
			return reject("Invalid start date")
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

		-- Execute async
		execute_swift_async(cmd)
			:then_(function()
				-- Update Last Synced timestamp
				vim.schedule(function()
					update_item_with_uid(item.file, item.line, item.uid)
				end)
				resolve({ success = true, item = item })
			end)
			:catch_(function(error_msg)
				-- Check if UID not found (event deleted in Calendar.app)
				if error_msg:match("Event not found") then
					vim.schedule(function()
						vim.notify(
							string.format("Event '%s' not found in Calendar.app (may have been deleted). UID: %s", item.title, item.uid),
							vim.log.levels.WARN
						)
					end)
				else
					vim.schedule(function()
						vim.notify(string.format("Failed to update event '%s': %s", item.title, error_msg), vim.log.levels.ERROR)
					end)
				end
				reject(error_msg)
			end)
	end)
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
				local ok, result = pcall(function()
					return update_calendar_event_async(item):await()
				end)
				if ok then
					results.success = results.success + 1
					results.updated = results.updated + 1
				else
					results.failed = results.failed + 1
				end
			else
				-- Create new event
				local ok, result = pcall(function()
					return create_calendar_event_async(item):await()
				end)
				if ok and result and result.uid then
					vim.schedule(function()
						update_item_with_uid(item.file, item.line, result.uid)
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
-- MAIN SYNC FUNCTION (now bidirectional)
-- =========================================================================

function M.sync()
	local plugin_config = config.sync and config.sync.plugins and config.sync.plugins.calendar or M.default_config
	if not plugin_config or not plugin_config.enabled then
		return nil, "Calendar sync is disabled"
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
