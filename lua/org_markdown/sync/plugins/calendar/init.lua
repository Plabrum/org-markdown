local config = require("org_markdown.config")
local datetime = require("org_markdown.utils.datetime")

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
-- CALENDAR ACCESS (Swift)
-- ============================================================================

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

-- ============================================================================
-- DATE PARSING
-- ============================================================================

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

-- ============================================================================
-- FILTERING & UTILITIES
-- ============================================================================

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

			id = raw.uid,
			location = raw.location,
			source_url = raw.url,
			body = raw.notes,
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
