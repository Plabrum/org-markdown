--- Notification system for upcoming timed events
--- Alerts users at configurable intervals before events start

local M = {}

-- =========================================================================
-- STATE MANAGEMENT
-- =========================================================================

local notification_cache = {
	events = {},
	last_refresh = 0,
}

local notified_events = {}
local notification_timer = nil

-- =========================================================================
-- HELPER FUNCTIONS
-- =========================================================================

--- Parse event date/time to Unix timestamp
--- @param date_str string "2025-12-20"
--- @param time_str string "14:00"
--- @return number|nil Unix timestamp or nil if invalid
local function parse_event_datetime(date_str, time_str)
	local datetime = require("org_markdown.utils.datetime")

	if not datetime.validate_time(time_str) then
		return nil
	end

	local year, month, day = date_str:match("(%d+)-(%d+)-(%d+)")
	local hour, min = time_str:match("(%d+):(%d+)")

	if not year or not hour then
		return nil
	end

	return os.time({
		year = tonumber(year),
		month = tonumber(month),
		day = tonumber(day),
		hour = tonumber(hour),
		min = tonumber(min),
		sec = 0,
	})
end

--- Filter events to only timed events within lookahead window
--- @param all_events table Array of all calendar events
--- @return table Array of filtered timed events
local function filter_timed_events(all_events)
	local config = require("org_markdown.config")
	local now = os.time()
	local max_time = now + (config.notifications.max_lookahead_days * 86400)
	local timed_events = {}

	for _, event in ipairs(all_events) do
		-- Must have tracked date, start time, and not be all-day
		if event.date and event.start_time and not event.all_day then
			local event_time = parse_event_datetime(event.date, event.start_time)

			if event_time and event_time > now and event_time <= max_time then
				table.insert(timed_events, event)
			end
		end
	end

	-- Sort by event time (earliest first)
	table.sort(timed_events, function(a, b)
		local time_a = parse_event_datetime(a.date, a.start_time)
		local time_b = parse_event_datetime(b.date, b.start_time)
		return time_a < time_b
	end)

	return timed_events
end

--- Mark event as notified for specific interval
--- @param event table Event to mark
--- @param interval_minutes number Interval (e.g., 10)
local function mark_notified(event, interval_minutes)
	local key = string.format("%s:%d:%d", event.file, event.line, interval_minutes)
	notified_events[key] = true
end

--- Check if event already notified for interval
--- @param event table Event to check
--- @param interval_minutes number Interval (e.g., 10)
--- @return boolean True if already notified
local function is_notified(event, interval_minutes)
	local key = string.format("%s:%d:%d", event.file, event.line, interval_minutes)
	return notified_events[key] == true
end

--- Send vim.notify notification for event
--- @param event table Event data
--- @param minutes_until number Minutes until event
local function send_notification(event, minutes_until)
	local config = require("org_markdown.config")

	local message = string.format(config.notifications.notification_format, event.title, minutes_until)

	vim.notify(message, config.notifications.notification_level, {
		title = "Upcoming Event",
		timeout = 5000,
	})
end

--- Calculate next notification time (in milliseconds)
--- @return number|nil Next notification time in ms, or nil if none
local function calculate_next_notification_time()
	local config = require("org_markdown.config")
	local now = os.time()
	local next_time = nil

	for _, event in ipairs(notification_cache.events) do
		local event_time = parse_event_datetime(event.date, event.start_time)

		if not event_time then
			goto continue
		end

		for _, interval in ipairs(config.notifications.intervals) do
			-- Skip if already notified
			if not is_notified(event, interval) then
				local notify_time = event_time - (interval * 60)

				-- Only consider future notification times
				if notify_time > now then
					if not next_time or notify_time < next_time then
						next_time = notify_time
					end
				end
			end
		end

		::continue::
	end

	return next_time and (next_time * 1000) or nil
end

-- =========================================================================
-- CORE FUNCTIONS
-- =========================================================================

--- Schedule next notification check
local function schedule_next_check()
	if not notification_timer then
		notification_timer = vim.loop.new_timer()
	else
		notification_timer:stop()
	end

	local next_time = calculate_next_notification_time()

	if not next_time then
		-- No upcoming notifications, stop timer
		return
	end

	local now_ms = os.time() * 1000
	local delay_ms = math.max(1000, next_time - now_ms)

	notification_timer:start(
		delay_ms,
		0,
		vim.schedule_wrap(function()
			M.check_and_notify()
			schedule_next_check()
		end)
	)
end

--- Refresh event cache from markdown files
function M.refresh_cache()
	local config = require("org_markdown.config")

	if not config.notifications or not config.notifications.enabled then
		return
	end

	-- Scan all markdown files (reuse agenda infrastructure)
	local agenda = require("org_markdown.agenda")
	local all_data = agenda.scan_files()

	-- Filter to timed events only
	local timed_events = filter_timed_events(all_data.calendar or {})

	-- Update cache
	notification_cache.events = timed_events
	notification_cache.last_refresh = os.time()

	-- Clear notification state (handles rescheduled events)
	notified_events = {}

	-- Reschedule timer based on new cache
	schedule_next_check()
end

--- Check cache and send notifications for upcoming events
function M.check_and_notify()
	local config = require("org_markdown.config")

	if not config.notifications or not config.notifications.enabled then
		return
	end

	local now = os.time()

	-- Refresh cache if stale
	if now - notification_cache.last_refresh > config.notifications.cache_refresh_interval then
		M.refresh_cache()
		return
	end

	-- Make shallow copy to avoid iteration issues during cache refresh
	local events_to_check = vim.deepcopy(notification_cache.events)

	-- Check each event against notification intervals
	for _, event in ipairs(events_to_check) do
		local event_time = parse_event_datetime(event.date, event.start_time)

		if event_time then
			local minutes_until = math.floor((event_time - now) / 60)

			for _, interval in ipairs(config.notifications.intervals) do
				-- Notify if within interval window (±0.5 min tolerance for timer drift)
				if not is_notified(event, interval) and math.abs(minutes_until - interval) < 0.5 then
					send_notification(event, minutes_until)
					mark_notified(event, interval)
				end
			end
		end
	end
end

-- =========================================================================
-- PUBLIC API
-- =========================================================================

--- Start notification system
function M.start()
	local config = require("org_markdown.config")

	if not config.notifications or not config.notifications.enabled then
		return
	end

	-- Initial cache load
	M.refresh_cache()

	-- Setup auto-refresh on save (if enabled)
	if config.notifications.auto_refresh_on_save then
		vim.api.nvim_create_autocmd("BufWritePost", {
			pattern = { "*.md", "*.markdown" },
			callback = function()
				-- Debounce: only refresh if >30 seconds since last refresh
				local now = os.time()
				if now - notification_cache.last_refresh > 30 then
					M.refresh_cache()
				end
			end,
			desc = "Refresh notification cache on markdown save",
		})
	end

	-- Refresh cache after resume from suspend
	vim.api.nvim_create_autocmd("VimResume", {
		callback = function()
			local cfg = require("org_markdown.config")
			if cfg.notifications and cfg.notifications.enabled then
				M.refresh_cache()
			end
		end,
		desc = "Refresh notifications after suspend",
	})
end

--- Stop notification system
function M.stop()
	if notification_timer then
		notification_timer:stop()
		notification_timer:close()
		notification_timer = nil
	end

	notification_cache = { events = {}, last_refresh = 0 }
	notified_events = {}
end

return M
