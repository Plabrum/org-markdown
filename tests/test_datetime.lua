local datetime = require("org_markdown.utils.datetime")

local T = MiniTest.new_set()

-- ============================================================================
-- PARSING FUNCTIONS
-- ============================================================================

T["extract_org_date"] = MiniTest.new_set()

T["extract_org_date"]["extracts tracked date"] = function()
	local date, tracked = datetime.extract_org_date("<2025-11-29 Fri>")
	MiniTest.expect.equality(date, "2025-11-29")
	MiniTest.expect.equality(tracked, true)
end

T["extract_org_date"]["extracts untracked date"] = function()
	local date, tracked = datetime.extract_org_date("[2025-11-29]")
	MiniTest.expect.equality(date, "2025-11-29")
	MiniTest.expect.equality(tracked, false)
end

T["extract_org_date"]["returns nil for no date"] = function()
	local date, tracked = datetime.extract_org_date("No date here")
	MiniTest.expect.equality(date, nil)
	MiniTest.expect.equality(tracked, false)
end

T["extract_org_date"]["handles nil input"] = function()
	local date, tracked = datetime.extract_org_date(nil)
	MiniTest.expect.equality(date, nil)
	MiniTest.expect.equality(tracked, false)
end

T["extract_times"] = MiniTest.new_set()

T["extract_times"]["extracts multi-day time range"] = function()
	local start_time, end_time = datetime.extract_times("<2025-11-29 Fri 09:00>--<2025-11-30 Sat 17:00>")
	MiniTest.expect.equality(start_time, "09:00")
	MiniTest.expect.equality(end_time, "17:00")
end

T["extract_times"]["extracts same-day time range"] = function()
	local start_time, end_time = datetime.extract_times("<2025-11-29 Fri 09:00-17:00>")
	MiniTest.expect.equality(start_time, "09:00")
	MiniTest.expect.equality(end_time, "17:00")
end

T["extract_times"]["extracts single time"] = function()
	local start_time, end_time = datetime.extract_times("<2025-11-29 Fri 14:00>")
	MiniTest.expect.equality(start_time, "14:00")
	MiniTest.expect.equality(end_time, nil)
end

T["extract_times"]["returns nil for no time"] = function()
	local start_time, end_time = datetime.extract_times("<2025-11-29 Fri>")
	MiniTest.expect.equality(start_time, nil)
	MiniTest.expect.equality(end_time, nil)
end

T["parse_macos_date"] = MiniTest.new_set()

T["parse_macos_date"]["parses with time (PM)"] = function()
	local date = datetime.parse_macos_date("Saturday, November 22, 2025 at 2:00:00 PM")
	MiniTest.expect.equality(date.year, 2025)
	MiniTest.expect.equality(date.month, 11)
	MiniTest.expect.equality(date.day, 22)
	MiniTest.expect.equality(date.day_name, "Sat")
	MiniTest.expect.equality(date.time, "14:00")
end

T["parse_macos_date"]["parses with time (AM)"] = function()
	local date = datetime.parse_macos_date("Monday, January 1, 2025 at 9:30:00 AM")
	MiniTest.expect.equality(date.year, 2025)
	MiniTest.expect.equality(date.month, 1)
	MiniTest.expect.equality(date.day, 1)
	MiniTest.expect.equality(date.time, "09:30")
end

T["parse_macos_date"]["parses without time"] = function()
	local date = datetime.parse_macos_date("Friday, December 25, 2025")
	MiniTest.expect.equality(date.year, 2025)
	MiniTest.expect.equality(date.month, 12)
	MiniTest.expect.equality(date.day, 25)
	MiniTest.expect.equality(date.day_name, "Fri")
	MiniTest.expect.equality(date.time, nil)
end

T["parse_macos_date"]["handles noon (12 PM)"] = function()
	local date = datetime.parse_macos_date("Monday, January 1, 2025 at 12:00:00 PM")
	MiniTest.expect.equality(date.time, "12:00")
end

T["parse_macos_date"]["handles midnight (12 AM)"] = function()
	local date = datetime.parse_macos_date("Monday, January 1, 2025 at 12:00:00 AM")
	MiniTest.expect.equality(date.time, "00:00")
end

T["parse_iso_date"] = MiniTest.new_set()

T["parse_iso_date"]["parses ISO string"] = function()
	local date = datetime.parse_iso_date("2025-11-29")
	MiniTest.expect.equality(date.year, 2025)
	MiniTest.expect.equality(date.month, 11)
	MiniTest.expect.equality(date.day, 29)
end

T["parse_iso_date"]["returns nil for invalid string"] = function()
	local date = datetime.parse_iso_date("not a date")
	MiniTest.expect.equality(date, nil)
end

T["validate_time"] = MiniTest.new_set()

T["validate_time"]["accepts valid times"] = function()
	MiniTest.expect.equality(datetime.validate_time("00:00"), true)
	MiniTest.expect.equality(datetime.validate_time("12:30"), true)
	MiniTest.expect.equality(datetime.validate_time("23:59"), true)
end

T["validate_time"]["rejects invalid hours"] = function()
	MiniTest.expect.equality(datetime.validate_time("24:00"), false)
	MiniTest.expect.equality(datetime.validate_time("25:30"), false)
end

T["validate_time"]["rejects invalid minutes"] = function()
	MiniTest.expect.equality(datetime.validate_time("12:60"), false)
	MiniTest.expect.equality(datetime.validate_time("12:99"), false)
end

T["validate_time"]["rejects invalid format"] = function()
	MiniTest.expect.equality(datetime.validate_time("1:30"), false)
	MiniTest.expect.equality(datetime.validate_time("12:3"), false)
	MiniTest.expect.equality(datetime.validate_time("not a time"), false)
end

-- ============================================================================
-- FORMATTING FUNCTIONS
-- ============================================================================

T["to_iso_string"] = MiniTest.new_set()

T["to_iso_string"]["converts table to ISO string"] = function()
	local result = datetime.to_iso_string({ year = 2025, month = 11, day = 29 })
	MiniTest.expect.equality(result, "2025-11-29")
end

T["to_iso_string"]["passes through ISO string"] = function()
	local result = datetime.to_iso_string("2025-11-29")
	MiniTest.expect.equality(result, "2025-11-29")
end

T["to_iso_string"]["handles nil"] = function()
	local result = datetime.to_iso_string(nil)
	MiniTest.expect.equality(result, nil)
end

T["to_org_string"] = MiniTest.new_set()

T["to_org_string"]["formats tracked date"] = function()
	local result = datetime.to_org_string({ year = 2025, month = 11, day = 29, day_name = "Fri" }, { tracked = true })
	MiniTest.expect.equality(result, "<2025-11-29 Fri>")
end

T["to_org_string"]["formats untracked date"] = function()
	local result = datetime.to_org_string({ year = 2025, month = 11, day = 29, day_name = "Fri" }, { tracked = false })
	MiniTest.expect.equality(result, "[2025-11-29 Fri]")
end

T["to_org_string"]["adds time"] = function()
	local result = datetime.to_org_string(
		{ year = 2025, month = 11, day = 29, day_name = "Fri" },
		{ tracked = true, time = "14:00" }
	)
	MiniTest.expect.equality(result, "<2025-11-29 Fri 14:00>")
end

T["to_org_string"]["adds time range"] = function()
	local result = datetime.to_org_string(
		{ year = 2025, month = 11, day = 29, day_name = "Fri" },
		{ tracked = true, time = "09:00", end_time = "17:00" }
	)
	MiniTest.expect.equality(result, "<2025-11-29 Fri 09:00-17:00>")
end

T["format_date_range"] = MiniTest.new_set()

T["format_date_range"]["formats all-day single day"] = function()
	local result = datetime.format_date_range(
		{ year = 2025, month = 11, day = 29, day_name = "Fri" },
		nil,
		{ all_day = true }
	)
	MiniTest.expect.equality(result, "<2025-11-29 Fri>")
end

T["format_date_range"]["formats timed single day"] = function()
	local result = datetime.format_date_range(
		{ year = 2025, month = 11, day = 29, day_name = "Fri" },
		nil,
		{ all_day = false, start_time = "09:00", end_time = "17:00" }
	)
	MiniTest.expect.equality(result, "<2025-11-29 Fri 09:00-17:00>")
end

T["format_date_range"]["formats multi-day all-day"] = function()
	local result = datetime.format_date_range(
		{ year = 2025, month = 12, day = 1, day_name = "Mon" },
		{ year = 2025, month = 12, day = 3, day_name = "Wed" },
		{ all_day = true }
	)
	MiniTest.expect.equality(result, "<2025-12-01 Mon>--<2025-12-03 Wed>")
end

T["format_date_range"]["formats multi-day timed"] = function()
	local result = datetime.format_date_range(
		{ year = 2025, month = 12, day = 1, day_name = "Mon" },
		{ year = 2025, month = 12, day = 3, day_name = "Wed" },
		{ all_day = false, start_time = "09:00", end_time = "17:00" }
	)
	MiniTest.expect.equality(result, "<2025-12-01 Mon 09:00>--<2025-12-03 Wed 17:00>")
end

T["format_display"] = MiniTest.new_set()

T["format_display"]["formats string date"] = function()
	local result = datetime.format_display("2025-11-29")
	MiniTest.expect.no_equality(result:match("29"), nil)
	MiniTest.expect.no_equality(result:match("Nov"), nil)
end

T["format_display"]["formats table date"] = function()
	local result = datetime.format_display({ year = 2025, month = 11, day = 29 })
	MiniTest.expect.no_equality(result:match("29"), nil)
	MiniTest.expect.no_equality(result:match("Nov"), nil)
end

T["format_display"]["uses custom format"] = function()
	local result = datetime.format_display("2025-11-29", "%Y-%m-%d")
	MiniTest.expect.equality(result, "2025-11-29")
end

T["get_day_name"] = MiniTest.new_set()

T["get_day_name"]["returns day name from string"] = function()
	local result = datetime.get_day_name("2025-11-29")
	MiniTest.expect.equality(result, "Sat")
end

T["get_day_name"]["returns day name from table"] = function()
	local result = datetime.get_day_name({ year = 2025, month = 11, day = 29 })
	MiniTest.expect.equality(result, "Sat")
end

T["capture_format"] = MiniTest.new_set()

T["capture_format"]["formats without brackets"] = function()
	local result = datetime.capture_format("%Y-%m-%d")
	MiniTest.expect.no_equality(result:match("%d%d%d%d%-%d%d%-%d%d"), nil)
end

T["capture_format"]["formats with angle brackets"] = function()
	local result = datetime.capture_format("%Y-%m-%d", "<")
	MiniTest.expect.no_equality(result:match("^<.*>$"), nil)
end

T["capture_format"]["formats with square brackets"] = function()
	local result = datetime.capture_format("%Y-%m-%d", "[")
	MiniTest.expect.no_equality(result:match("^%[.*%]$"), nil)
end

-- ============================================================================
-- COMPARISON FUNCTIONS
-- ============================================================================

T["compare"] = MiniTest.new_set()

T["compare"]["returns -1 for earlier date"] = function()
	local result = datetime.compare("2025-11-28", "2025-11-29")
	MiniTest.expect.equality(result, -1)
end

T["compare"]["returns 0 for same date"] = function()
	local result = datetime.compare("2025-11-29", "2025-11-29")
	MiniTest.expect.equality(result, 0)
end

T["compare"]["returns 1 for later date"] = function()
	local result = datetime.compare("2025-11-30", "2025-11-29")
	MiniTest.expect.equality(result, 1)
end

T["compare"]["works with table dates"] = function()
	local result = datetime.compare({ year = 2025, month = 11, day = 28 }, { year = 2025, month = 11, day = 29 })
	MiniTest.expect.equality(result, -1)
end

T["is_in_range"] = MiniTest.new_set()

T["is_in_range"]["returns true for date in range"] = function()
	local result = datetime.is_in_range("2025-11-29", "2025-11-01", "2025-11-30")
	MiniTest.expect.equality(result, true)
end

T["is_in_range"]["returns false for date before range"] = function()
	local result = datetime.is_in_range("2025-10-31", "2025-11-01", "2025-11-30")
	MiniTest.expect.equality(result, false)
end

T["is_in_range"]["returns false for date after range"] = function()
	local result = datetime.is_in_range("2025-12-01", "2025-11-01", "2025-11-30")
	MiniTest.expect.equality(result, false)
end

T["is_in_range"]["includes range boundaries"] = function()
	MiniTest.expect.equality(datetime.is_in_range("2025-11-01", "2025-11-01", "2025-11-30"), true)
	MiniTest.expect.equality(datetime.is_in_range("2025-11-30", "2025-11-01", "2025-11-30"), true)
end

T["is_same_day"] = MiniTest.new_set()

T["is_same_day"]["returns true for same day"] = function()
	local result = datetime.is_same_day({ year = 2025, month = 11, day = 29 }, { year = 2025, month = 11, day = 29 })
	MiniTest.expect.equality(result, true)
end

T["is_same_day"]["returns false for different day"] = function()
	local result = datetime.is_same_day({ year = 2025, month = 11, day = 28 }, { year = 2025, month = 11, day = 29 })
	MiniTest.expect.equality(result, false)
end

T["is_before"] = MiniTest.new_set()

T["is_before"]["returns true for earlier date"] = function()
	local result = datetime.is_before("2025-11-28", "2025-11-29")
	MiniTest.expect.equality(result, true)
end

T["is_before"]["returns false for later date"] = function()
	local result = datetime.is_before("2025-11-30", "2025-11-29")
	MiniTest.expect.equality(result, false)
end

T["is_before"]["returns false for same date"] = function()
	local result = datetime.is_before("2025-11-29", "2025-11-29")
	MiniTest.expect.equality(result, false)
end

-- ============================================================================
-- DATE MATH FUNCTIONS
-- ============================================================================

T["today"] = MiniTest.new_set()

T["today"]["returns ISO string by default"] = function()
	local result = datetime.today()
	MiniTest.expect.no_equality(result:match("%d%d%d%d%-%d%d%-%d%d"), nil)
end

T["today"]["returns table when requested"] = function()
	local result = datetime.today(true)
	MiniTest.expect.no_equality(result.year, nil)
	MiniTest.expect.no_equality(result.month, nil)
	MiniTest.expect.no_equality(result.day, nil)
	MiniTest.expect.no_equality(result.day_name, nil)
end

T["add_days"] = MiniTest.new_set()

T["add_days"]["adds days to string date"] = function()
	local result = datetime.add_days("2025-11-29", 7)
	MiniTest.expect.equality(result, "2025-12-06")
end

T["add_days"]["subtracts days from string date"] = function()
	local result = datetime.add_days("2025-11-29", -7)
	MiniTest.expect.equality(result, "2025-11-22")
end

T["add_days"]["adds days to table date"] = function()
	local result = datetime.add_days({ year = 2025, month = 11, day = 29 }, 7)
	MiniTest.expect.equality(result.year, 2025)
	MiniTest.expect.equality(result.month, 12)
	MiniTest.expect.equality(result.day, 6)
end

T["add_days"]["preserves input format"] = function()
	-- String input -> string output
	local str_result = datetime.add_days("2025-11-29", 1)
	MiniTest.expect.equality(type(str_result), "string")

	-- Table input -> table output
	local tbl_result = datetime.add_days({ year = 2025, month = 11, day = 29 }, 1)
	MiniTest.expect.equality(type(tbl_result), "table")
end

T["calculate_range"] = MiniTest.new_set()

T["calculate_range"]["uses absolute range"] = function()
	local start_date, end_date = datetime.calculate_range({ from = "2025-11-01", to = "2025-11-30" })
	MiniTest.expect.equality(start_date, "2025-11-01")
	MiniTest.expect.equality(end_date, "2025-11-30")
end

T["calculate_range"]["calculates relative range"] = function()
	local start_date, end_date = datetime.calculate_range({ days = 7, offset = 0 })
	-- Can't assert exact dates since it's relative to today, but ensure they're valid
	MiniTest.expect.no_equality(start_date:match("%d%d%d%d%-%d%d%-%d%d"), nil)
	MiniTest.expect.no_equality(end_date:match("%d%d%d%d%-%d%d%-%d%d"), nil)

	-- End date should be 6 days after start date (7 days inclusive)
	local days_diff = datetime.days_between(start_date, end_date)
	MiniTest.expect.equality(days_diff, 6)
end

T["days_between"] = MiniTest.new_set()

T["days_between"]["calculates positive difference"] = function()
	local result = datetime.days_between("2025-11-29", "2025-12-06")
	MiniTest.expect.equality(result, 7)
end

T["days_between"]["calculates negative difference"] = function()
	local result = datetime.days_between("2025-12-06", "2025-11-29")
	MiniTest.expect.equality(result, -7)
end

T["days_between"]["returns 0 for same date"] = function()
	local result = datetime.days_between("2025-11-29", "2025-11-29")
	MiniTest.expect.equality(result, 0)
end

T["days_from_today"] = MiniTest.new_set()

T["days_from_today"]["works with future date"] = function()
	local future = datetime.add_days(datetime.today(), 10)
	local result = datetime.days_from_today(future)
	-- Allow some tolerance for test execution time
	MiniTest.expect.no_equality(result >= 9 and result <= 10, false)
end

T["days_from_today"]["works with past date"] = function()
	local past = datetime.add_days(datetime.today(), -10)
	local result = datetime.days_from_today(past)
	-- Allow tolerance: os.time() includes current time, so -10 days at midnight could be -11 to -9
	MiniTest.expect.no_equality(result >= -11 and result <= -9, false)
end

return T
