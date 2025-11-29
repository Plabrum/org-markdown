local config = require("org_markdown.config")

local M = {
	name = "calendar",
	description = "Sync events from Apple Calendar",

	default_config = {
		enabled = true,
		sync_file = "~/notes/calendar.md",
		days_ahead = 30,
		days_behind = 0,
		calendars = {}, -- {} = all calendars
		exclude_calendars = {},
		include_time = true,
		include_end_time = true,
		heading_level = 1,
		auto_sync = false,
		auto_sync_interval = 3600, -- 1 hour
	},

	supports_auto_sync = true,
	command_name = "MarkdownSyncCalendar",
	keymap = "<leader>os",
}

-- ============================================================================
-- SETUP & VALIDATION
-- ============================================================================

function M.setup(plugin_config)
	-- Validate macOS
	if vim.fn.has("mac") == 0 then
		vim.notify("Calendar sync requires macOS (Calendar.app)", vim.log.levels.WARN)
		return false
	end
	return true
end

-- ============================================================================
-- CALENDAR ACCESS (AppleScript)
-- ============================================================================

--- Get list of all available calendars from Calendar.app
--- @return table|nil, string|nil calendar_names, error
local function get_available_calendars()
	local script = [[
tell application "Calendar"
	set calNames to {}
	repeat with cal in every calendar
		set end of calNames to name of cal
	end repeat
	return calNames
end tell
]]

	local output = vim.fn.systemlist({ "osascript", "-e", script })
	if vim.v.shell_error ~= 0 then
		return nil, "Calendar access denied. Grant permissions in System Preferences > Privacy & Security > Automation"
	end

	if #output == 0 or output[1] == "" then
		return {}, nil
	end

	-- Parse: "cal1, cal2, cal3" -> { "cal1", "cal2", "cal3" }
	local calendars = vim.split(output[1], ", ")
	return calendars, nil
end

--- Fetch events from Calendar.app for specified date range
--- @param calendars table List of calendar names to sync
--- @param start_date string YYYY-MM-DD format
--- @param end_date string YYYY-MM-DD format
--- @return table|nil, string|nil events, error
local function fetch_calendar_events(calendars, start_date, end_date)
	-- Convert YYYY-MM-DD to AppleScript date format: "MM/DD/YYYY"
	local function to_applescript_date(iso_date)
		local year, month, day = iso_date:match("(%d%d%d%d)-(%d%d)-(%d%d)")
		return string.format("%s/%s/%s", month, day, year)
	end

	local start_as = to_applescript_date(start_date)
	local end_as = to_applescript_date(end_date)

	-- Build calendar list for AppleScript
	local cal_list_parts = {}
	for _, cal in ipairs(calendars) do
		table.insert(cal_list_parts, '"' .. cal:gsub('"', '\\"') .. '"')
	end
	local cal_list = "{" .. table.concat(cal_list_parts, ", ") .. "}"

	local script = string.format(
		[[
tell application "Calendar"
	set startDate to date "%s"
	set endDate to date "%s"
	set output to ""

	repeat with calName in %s
		try
			set cal to calendar calName
		on error
			-- Calendar doesn't exist, skip
			next repeat
		end try

		repeat with evt in (every event of cal whose start date >= startDate and start date <= endDate)
			set evtTitle to summary of evt
			set evtStart to start date of evt as string
			set evtEnd to end date of evt as string
			set evtAllDay to allday event of evt as string

			set eventLine to (calName as string) & "|" & evtTitle & "|" & evtStart & "|" & evtEnd & "|" & evtAllDay
			set output to output & eventLine & linefeed
		end repeat
	end repeat

	return output
end tell
]],
		start_as,
		end_as,
		cal_list
	)

	local output = vim.fn.systemlist({ "osascript", "-e", script })
	if vim.v.shell_error ~= 0 then
		return nil, "Failed to fetch calendar events from Calendar.app"
	end

	return output, nil
end

-- ============================================================================
-- DATE PARSING
-- ============================================================================

--- Parse macOS date string to components
--- macOS returns: "Saturday, November 22, 2025 at 2:00:00 PM" or "Saturday, November 22, 2025"
--- @param date_str string macOS date format
--- @return table|nil date components { year, month, day, day_name, time }
local function parse_macos_date(date_str)
	if not date_str or date_str == "" then
		return nil
	end

	local month_map = {
		January = 1,
		February = 2,
		March = 3,
		April = 4,
		May = 5,
		June = 6,
		July = 7,
		August = 8,
		September = 9,
		October = 10,
		November = 11,
		December = 12,
	}

	-- Try parsing with time: "Saturday, November 22, 2025 at 2:00:00 PM"
	local day_name, month_name, day, year, hour, min, sec, meridian =
		date_str:match("(%a+), (%a+) (%d+), (%d+) at (%d+):(%d+):(%d+) (%a+)")

	local time = nil
	if day_name then
		-- Has time - convert to 24-hour format
		hour = tonumber(hour)
		min = tonumber(min)

		if meridian == "PM" and hour ~= 12 then
			hour = hour + 12
		elseif meridian == "AM" and hour == 12 then
			hour = 0
		end

		time = string.format("%02d:%02d", hour, min)
	else
		-- Try parsing without time: "Saturday, November 22, 2025"
		day_name, month_name, day, year = date_str:match("(%a+), (%a+) (%d+), (%d+)")

		if not day_name then
			vim.notify("Failed to parse date: " .. date_str, vim.log.levels.WARN)
			return nil
		end
	end

	return {
		year = tonumber(year),
		month = month_map[month_name],
		day = tonumber(day),
		day_name = day_name:sub(1, 3), -- "Sat"
		time = time,
	}
end

--- Parse AppleScript output into events
--- @param output table Lines from AppleScript
--- @return table events Array of parsed events
local function parse_applescript_output(output)
	local events = {}

	for _, line in ipairs(output) do
		if line ~= "" then
			-- Format: CALENDAR|TITLE|START|END|ALLDAY
			local parts = vim.split(line, "|", { plain = true })
			if #parts >= 5 then
				local calendar = parts[1]
				local title = parts[2]
				local start_raw = parts[3]
				local end_raw = parts[4]
				local all_day_str = parts[5]

				local start_date = parse_macos_date(start_raw)
				local end_date = parse_macos_date(end_raw)

				if start_date then
					local event = {
						calendar = calendar,
						title = title,
						start = start_date,
						end_date = end_date,
						all_day = all_day_str == "true",
					}
					table.insert(events, event)
				end
			end
		end
	end

	return events
end

-- ============================================================================
-- FILTERING & UTILITIES
-- ============================================================================

--- Calculate date range based on config
--- @param plugin_config table Plugin configuration
--- @return string, string start_date, end_date (YYYY-MM-DD format)
local function calculate_date_range(plugin_config)
	local today = os.time()
	local days_behind = plugin_config.days_behind or 0
	local days_ahead = plugin_config.days_ahead or 30

	local start_time = today - (days_behind * 86400)
	local end_time = today + (days_ahead * 86400)

	return os.date("%Y-%m-%d", start_time), os.date("%Y-%m-%d", end_time)
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

-- ============================================================================
-- MAIN SYNC FUNCTION
-- ============================================================================

function M.sync()
	local plugin_config = config.sync.plugins.calendar
	if not plugin_config or not plugin_config.enabled then
		return nil, "Calendar sync is disabled"
	end

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
		local event = {
			title = raw.title,
			start_date = raw.start,
			end_date = raw.end_date,
			start_time = raw.start.time,
			end_time = raw.end_date and raw.end_date.time,
			all_day = raw.all_day,
			tags = { sanitize_tag(raw.calendar) },
		}
		table.insert(events, event)
	end

	return {
		events = events,
		stats = {
			count = #events,
			calendars = calendars_to_sync,
			date_range = start_date .. " to " .. end_date,
		},
	}
end

return M
