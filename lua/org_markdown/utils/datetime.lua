--- Centralized date/time operations module
--- Supports both string dates ("2025-11-29") and table dates ({year, month, day, day_name})

local M = {}

-- ============================================================================
-- INTERNAL HELPERS
-- ============================================================================

--- Month name to number mapping
local MONTH_MAP = {
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

--- Normalize date to table format
--- @param date string|table Date in either format
--- @return table|nil Date table with {year, month, day}
local function normalize_to_table(date)
	if not date then
		return nil
	end

	if type(date) == "table" then
		return date
	end

	if type(date) == "string" then
		local y, m, d = date:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
		if y then
			return {
				year = tonumber(y),
				month = tonumber(m),
				day = tonumber(d),
			}
		end
	end

	return nil
end

--- Normalize date to string format
--- @param date string|table Date in either format
--- @return string|nil ISO date string "YYYY-MM-DD"
local function normalize_to_string(date)
	if not date then
		return nil
	end

	if type(date) == "string" then
		return date
	end

	if type(date) == "table" and date.year and date.month and date.day then
		return string.format("%04d-%02d-%02d", date.year, date.month, date.day)
	end

	return nil
end

-- ============================================================================
-- PARSING FUNCTIONS
-- ============================================================================

--- Extract org-mode date from line
--- @param line string Line containing org-mode date
--- @return string|nil, boolean Date string (YYYY-MM-DD), whether tracked (<> vs [])
function M.extract_org_date(line)
	if not line then
		return nil, false
	end

	-- Try tracked date first: <YYYY-MM-DD>
	local tracked = line:match("<(%d%d%d%d%-%d%d%-%d%d)")
	if tracked then
		return tracked, true
	end

	-- Try untracked date: [YYYY-MM-DD]
	local untracked = line:match("%[(%d%d%d%d%-%d%d%-%d%d)")
	if untracked then
		return untracked, false
	end

	return nil, false
end

--- Extract time ranges from org-mode line
--- @param line string Line containing time information
--- @return string|nil, string|nil Start time, end time (HH:MM format)
function M.extract_times(line)
	if not line then
		return nil, nil
	end

	-- Multi-day event: <...HH:MM>--<...HH:MM>
	local start_part, end_part = line:match("<([^>]+)>%-%-<([^>]+)>")
	if start_part and end_part then
		local start_time = start_part:match(" (%d%d:%d%d)")
		local end_time = end_part:match(" (%d%d:%d%d)")
		if start_time and end_time then
			return start_time, end_time
		end
	end

	-- Same-day event: <...HH:MM-HH:MM>
	local start_time, end_time = line:match("<[^>]* (%d%d:%d%d)%-(%d%d:%d%d)>")
	if start_time and end_time then
		return start_time, end_time
	end

	-- Single time: <...HH:MM>
	start_time = line:match("<[^>]* (%d%d:%d%d)>")
	if start_time then
		return start_time, nil
	end

	return nil, nil
end

--- Parse macOS Calendar date format
--- macOS returns: "Saturday, November 22, 2025 at 2:00:00 PM" or "Saturday, November 22, 2025"
--- @param date_str string macOS date format
--- @return table|nil Date table {year, month, day, time}
function M.parse_macos_date(date_str)
	if not date_str or date_str == "" then
		return nil
	end

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
			return nil
		end
	end

	return {
		year = tonumber(year),
		month = MONTH_MAP[month_name],
		day = tonumber(day),
		time = time,
	}
end

--- Parse ISO date string to date table
--- @param iso_string string "2025-11-29"
--- @return table|nil Date table {year, month, day}
function M.parse_iso_date(iso_string)
	return normalize_to_table(iso_string)
end

--- Validate time string format
--- @param time_str string "14:00"
--- @return boolean True if valid HH:MM format
function M.validate_time(time_str)
	if not time_str or type(time_str) ~= "string" then
		return false
	end

	local h, m = time_str:match("^(%d%d):(%d%d)$")
	if not h then
		return false
	end

	local hour = tonumber(h)
	local min = tonumber(m)

	return hour >= 0 and hour <= 23 and min >= 0 and min <= 59
end

-- ============================================================================
-- FORMATTING FUNCTIONS
-- ============================================================================

--- Format date table to ISO string
--- @param date table {year, month, day}
--- @return string|nil "2025-11-29"
function M.to_iso_string(date)
	return normalize_to_string(date)
end

--- Format date to org-mode string
--- @param date table|string Date to format
--- @param opts table|nil {tracked=true, time="14:00", end_time="15:00"}
--- @return string Org-mode date string
function M.to_org_string(date, opts)
	opts = opts or {}
	local date_table = normalize_to_table(date)

	if not date_table then
		return ""
	end

	local bracket_open = opts.tracked and "<" or "["
	local bracket_close = opts.tracked and ">" or "]"

	local date_str = string.format("%s%04d-%02d-%02d", bracket_open, date_table.year, date_table.month, date_table.day)

	-- Add day name if available
	if date_table.day_name then
		date_str = date_str .. " " .. date_table.day_name
	elseif opts.tracked then
		-- Calculate day name if tracked and not provided
		local timestamp = os.time(date_table)
		date_str = date_str .. " " .. os.date("%a", timestamp)
	end

	-- Add time if provided
	if opts.time then
		date_str = date_str .. " " .. opts.time
	end

	-- Add end time if different from start time
	if opts.end_time and opts.end_time ~= opts.time then
		date_str = date_str .. "-" .. opts.end_time
	end

	date_str = date_str .. bracket_close

	return date_str
end

--- Format date range for org-mode (handles multi-day, time ranges)
--- @param start_date table Start date {year, month, day, day_name}
--- @param end_date table|nil End date for multi-day events
--- @param opts table {start_time=nil, end_time=nil, all_day=true}
--- @return string Formatted org date range
function M.format_date_range(start_date, end_date, opts)
	opts = opts or {}

	if not start_date then
		return ""
	end

	local date_str = string.format(
		"<%04d-%02d-%02d %s",
		start_date.year,
		start_date.month,
		start_date.day,
		start_date.day_name or os.date("%a", os.time(start_date))
	)

	-- Multi-day event
	if end_date and not M.is_same_day(start_date, end_date) then
		-- Add start time if timed event
		if not opts.all_day and opts.start_time then
			date_str = date_str .. " " .. opts.start_time
		end

		date_str = date_str
			.. ">--<"
			.. string.format(
				"%04d-%02d-%02d %s",
				end_date.year,
				end_date.month,
				end_date.day,
				end_date.day_name or os.date("%a", os.time(end_date))
			)

		-- Add end time if timed event
		if not opts.all_day and opts.end_time then
			date_str = date_str .. " " .. opts.end_time
		end
	else
		-- Single-day event: add time for timed events
		if not opts.all_day and opts.start_time then
			if opts.end_time then
				date_str = date_str .. " " .. opts.start_time .. "-" .. opts.end_time
			else
				date_str = date_str .. " " .. opts.start_time
			end
		end
	end

	date_str = date_str .. ">"
	return date_str
end

--- Format date for display (human-readable)
--- @param date_input string|table ISO string or date table
--- @param fmt string|nil os.date format (default "%A %d %b")
--- @return string "Friday 29 Nov"
function M.format_display(date_input, fmt)
	fmt = fmt or "%A %d %b"

	local date_str = normalize_to_string(date_input)
	if not date_str then
		return ""
	end

	local y, m, d = date_str:match("(%d+)%-(%d+)%-(%d+)")
	if not y then
		return ""
	end

	local timestamp = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
	return os.date(fmt, timestamp)
end

--- Get day name abbreviation from date
--- @param date string|table Date in either format
--- @return string "Mon", "Tue", etc.
function M.get_day_name(date)
	local date_str = normalize_to_string(date)
	if not date_str then
		return ""
	end

	local y, m, d = date_str:match("(%d+)%-(%d+)%-(%d+)")
	if not y then
		return ""
	end

	local timestamp = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
	return os.date("%a", timestamp)
end

--- Format current time/date for capture templates
--- @param fmt string os.date format string
--- @param bracket string|nil "<", "[", or nil for no brackets
--- @return string Formatted date/time
function M.capture_format(fmt, bracket)
	local result = os.date(fmt)

	if bracket == "<" then
		return "<" .. result .. ">"
	elseif bracket == "[" then
		return "[" .. result .. "]"
	else
		return result
	end
end

-- ============================================================================
-- COMPARISON FUNCTIONS
-- ============================================================================

--- Compare two dates
--- @param date1 string|table First date
--- @param date2 string|table Second date
--- @return number -1 (before), 0 (same), 1 (after)
function M.compare(date1, date2)
	local str1 = normalize_to_string(date1)
	local str2 = normalize_to_string(date2)

	if not str1 or not str2 then
		return 0
	end

	if str1 < str2 then
		return -1
	elseif str1 > str2 then
		return 1
	else
		return 0
	end
end

--- Check if date is within range
--- @param date string|table Date to check
--- @param range_start string|table Range start (inclusive)
--- @param range_end string|table Range end (inclusive)
--- @return boolean True if date in range
function M.is_in_range(date, range_start, range_end)
	local date_str = normalize_to_string(date)
	local start_str = normalize_to_string(range_start)
	local end_str = normalize_to_string(range_end)

	if not date_str or not start_str or not end_str then
		return false
	end

	return date_str >= start_str and date_str <= end_str
end

--- Check if two dates are the same day
--- @param date1 table Date table
--- @param date2 table Date table
--- @return boolean True if same year, month, day
function M.is_same_day(date1, date2)
	if not date1 or not date2 then
		return false
	end

	return date1.year == date2.year and date1.month == date2.month and date1.day == date2.day
end

--- Check if date is before another
--- @param date1 string|table First date
--- @param date2 string|table Second date
--- @return boolean True if date1 < date2
function M.is_before(date1, date2)
	return M.compare(date1, date2) == -1
end

-- ============================================================================
-- DATE MATH FUNCTIONS
-- ============================================================================

--- Get today's date
--- @param as_table boolean|nil If true, return table; else ISO string
--- @return string|table Today's date
function M.today(as_table)
	if as_table then
		local now = os.date("*t")
		return {
			year = now.year,
			month = now.month,
			day = now.day,
		}
	else
		return os.date("%Y-%m-%d")
	end
end

--- Add days to a date
--- @param date string|table Starting date
--- @param days number Days to add (negative to subtract)
--- @return string|table New date (same format as input)
function M.add_days(date, days)
	local date_table = normalize_to_table(date)
	if not date_table then
		return date
	end

	local timestamp = os.time(date_table)
	timestamp = timestamp + (days * 24 * 60 * 60)

	local new_date = os.date("*t", timestamp)
	local result = {
		year = new_date.year,
		month = new_date.month,
		day = new_date.day,
	}

	-- Preserve input format: if input was string, return string
	if type(date) == "string" then
		return M.to_iso_string(result)
	else
		-- Preserve any additional fields from original table
		if date.tracked ~= nil then
			result.tracked = date.tracked
		end
		return result
	end
end

--- Calculate date range from spec
--- @param spec table {days=N, offset=0} or {from="date", to="date"}
--- @return string, string start_date, end_date (ISO strings)
function M.calculate_range(spec)
	if spec.from and spec.to then
		-- Absolute range
		return spec.from, spec.to
	end

	-- Relative range
	local days = spec.days or 7
	local offset = spec.offset or 0
	local today_time = os.time()
	local start_time = today_time + (offset * 86400)
	local end_time = today_time + ((offset + days - 1) * 86400)

	local start_date = os.date("%Y-%m-%d", start_time)
	local end_date = os.date("%Y-%m-%d", end_time)

	return start_date, end_date
end

--- Calculate days between two dates
--- @param date1 string|table Earlier date
--- @param date2 string|table Later date
--- @return number Days between (can be negative)
function M.days_between(date1, date2)
	local table1 = normalize_to_table(date1)
	local table2 = normalize_to_table(date2)

	if not table1 or not table2 then
		return 0
	end

	local time1 = os.time(table1)
	local time2 = os.time(table2)

	return math.floor((time2 - time1) / 86400)
end

--- Calculate days from today
--- @param date string|table Target date
--- @return number Days from today (negative if in past)
function M.days_from_today(date)
	local date_table = normalize_to_table(date)
	if not date_table then
		return 0
	end

	local target_time = os.time(date_table)
	local today_time = os.time()

	return math.floor((target_time - today_time) / 86400)
end

return M
