local config = require("org_markdown.config")
local utils = require("org_markdown.utils.utils")

local M = {}

-- Plugin registry
M.plugins = {}

-- Sync locks to prevent concurrent syncs
local sync_locks = {}

-- Auto-sync timers
local auto_sync_timers = {}

-- ============================================================================
-- PLUGIN REGISTRATION
-- ============================================================================

--- Register a sync plugin
--- @param plugin_module table Plugin module with required interface
function M.register_plugin(plugin_module)
	-- Validate plugin interface
	if not plugin_module.name then
		vim.notify("Sync plugin missing 'name' field", vim.log.levels.ERROR)
		return false
	end

	if type(plugin_module.sync) ~= "function" then
		vim.notify("Sync plugin '" .. plugin_module.name .. "' missing 'sync' function", vim.log.levels.ERROR)
		return false
	end

	-- Add to registry
	M.plugins[plugin_module.name] = plugin_module

	-- Merge default config into config.sync.plugins[name]
	if plugin_module.default_config then
		if not config.sync then
			config.sync = { plugins = {} }
		end
		if not config.sync.plugins then
			config.sync.plugins = {}
		end

		-- Initialize plugin config if not exists
		if not config.sync.plugins[plugin_module.name] then
			config.sync.plugins[plugin_module.name] = {}
		end

		-- Deep merge default config
		local function merge_config(default, user)
			for k, v in pairs(default) do
				if user[k] == nil then
					user[k] = v
				elseif type(v) == "table" and type(user[k]) == "table" then
					merge_config(v, user[k])
				end
			end
		end

		merge_config(plugin_module.default_config, config.sync.plugins[plugin_module.name])
	end

	-- Call plugin setup if it exists
	if type(plugin_module.setup) == "function" then
		local ok, err = pcall(plugin_module.setup, config.sync.plugins[plugin_module.name])
		if not ok then
			vim.notify("Failed to setup sync plugin '" .. plugin_module.name .. "': " .. tostring(err), vim.log.levels.ERROR)
			return false
		end
		if err == false then
			-- Setup returned false (e.g., platform check failed)
			return false
		end
	end

	return true
end

-- ============================================================================
-- EVENT FORMATTING
-- ============================================================================

--- Check if two dates are the same day
--- @param date1 table Date with year, month, day
--- @param date2 table Date with year, month, day
--- @return boolean
local function is_same_day(date1, date2)
	return date1.year == date2.year and date1.month == date2.month and date1.day == date2.day
end

--- Format date range for an event
--- @param event table Event with start_date, end_date, start_time, end_time, all_day
--- @return string Formatted date range
local function format_date_range(event)
	local start = event.start_date
	local date_str = string.format("<%04d-%02d-%02d %s", start.year, start.month, start.day, start.day_name)

	-- Multi-day event
	if event.end_date and not is_same_day(event.start_date, event.end_date) then
		local end_d = event.end_date

		-- Add start time if timed event
		if not event.all_day and event.start_time then
			date_str = date_str .. " " .. event.start_time
		end

		date_str = date_str
			.. ">--<"
			.. string.format("%04d-%02d-%02d %s", end_d.year, end_d.month, end_d.day, end_d.day_name)

		-- Add end time if timed event
		if not event.all_day and event.end_time then
			date_str = date_str .. " " .. event.end_time
		end
	else
		-- Single-day event: add time for timed events
		if not event.all_day and event.start_time then
			if event.end_time then
				date_str = date_str .. " " .. event.start_time .. "-" .. event.end_time
			else
				date_str = date_str .. " " .. event.start_time
			end
		end
	end

	date_str = date_str .. ">"
	return date_str
end

--- Format an event as markdown lines
--- @param event table Event data structure
--- @param plugin_config table Plugin configuration
--- @return table Array of markdown lines
local function format_event_as_markdown(event, plugin_config)
	local lines = {}
	local heading_level = plugin_config.heading_level or 1

	-- Build heading
	local heading = string.rep("#", heading_level) .. " " .. event.title

	-- Add tags with padding
	if event.tags and #event.tags > 0 then
		local tag_str = ":" .. table.concat(event.tags, ":") .. ":"
		local padding_length = 80 - vim.fn.strdisplaywidth(heading) - vim.fn.strdisplaywidth(tag_str)
		if padding_length > 1 then
			heading = heading .. string.rep(" ", padding_length) .. tag_str
		else
			heading = heading .. " " .. tag_str
		end
	end

	table.insert(lines, heading)

	-- Build date line
	local date_line = format_date_range(event)
	table.insert(lines, date_line)

	-- Optional body
	if event.body and event.body ~= "" then
		table.insert(lines, "")
		table.insert(lines, event.body)
	end

	-- Blank line after event
	table.insert(lines, "")

	return lines
end

-- ============================================================================
-- FILE OPERATIONS
-- ============================================================================

--- Read file and extract content outside sync markers
--- @param filepath string Path to file
--- @param plugin_name string Name of plugin (for marker identification)
--- @return table, table Lines before markers, lines after markers
local function read_preserved_content(filepath, plugin_name)
	local expanded_path = vim.fn.expand(filepath)
	local lines = utils.read_lines(expanded_path)

	local before_marker = string.format("<!-- BEGIN ORG-MARKDOWN %s SYNC -->", plugin_name:upper())
	local after_marker = string.format("<!-- END ORG-MARKDOWN %s SYNC -->", plugin_name:upper())

	local lines_before = {}
	local lines_after = {}
	local in_sync_section = false
	local found_end_marker = false

	for _, line in ipairs(lines) do
		if line:match("^%s*" .. vim.pesc(before_marker)) then
			in_sync_section = true
		elseif line:match("^%s*" .. vim.pesc(after_marker)) then
			in_sync_section = false
			found_end_marker = true
		elseif not in_sync_section and not found_end_marker then
			table.insert(lines_before, line)
		elseif not in_sync_section and found_end_marker then
			table.insert(lines_after, line)
		end
	end

	return lines_before, lines_after
end

--- Write events to sync file with marker preservation
--- @param events table Array of events
--- @param plugin_name string Plugin name
--- @param plugin_config table Plugin configuration
--- @param stats table Sync statistics
local function write_sync_file(events, plugin_name, plugin_config, stats)
	local filepath = vim.fn.expand(plugin_config.sync_file)

	-- Read preserved content
	local lines_before, lines_after = read_preserved_content(filepath, plugin_name)

	-- Build new sync section
	local sync_section = {}

	-- Add markers and metadata
	table.insert(sync_section, string.format("<!-- BEGIN ORG-MARKDOWN %s SYNC -->", plugin_name:upper()))
	table.insert(sync_section, string.format("<!-- Last synced: %s -->", os.date("%Y-%m-%d %H:%M:%S")))
	if stats.date_range then
		table.insert(sync_section, string.format("<!-- Date range: %s -->", stats.date_range))
	end
	if stats.calendars then
		table.insert(
			sync_section,
			string.format("<!-- Calendars: %s (%d total) -->", table.concat(stats.calendars, ", "), #stats.calendars)
		)
	end
	if stats.source then
		table.insert(sync_section, string.format("<!-- Source: %s -->", stats.source))
	end
	table.insert(sync_section, "")

	-- Add formatted events
	for _, event in ipairs(events) do
		local event_lines = format_event_as_markdown(event, plugin_config)
		for _, line in ipairs(event_lines) do
			table.insert(sync_section, line)
		end
	end

	table.insert(sync_section, string.format("<!-- END ORG-MARKDOWN %s SYNC -->", plugin_name:upper()))

	-- Combine: before + sync section + after
	local final_lines = {}
	for _, line in ipairs(lines_before) do
		table.insert(final_lines, line)
	end
	if #lines_before > 0 and lines_before[#lines_before] ~= "" then
		table.insert(final_lines, "")
	end
	for _, line in ipairs(sync_section) do
		table.insert(final_lines, line)
	end
	if #lines_after > 0 then
		table.insert(final_lines, "")
		for _, line in ipairs(lines_after) do
			table.insert(final_lines, line)
		end
	end

	-- Write to file
	utils.write_lines(filepath, final_lines)
end

-- ============================================================================
-- SYNC OPERATIONS
-- ============================================================================

--- Sync a specific plugin
--- @param plugin_name string Name of plugin to sync
function M.sync_plugin(plugin_name)
	local plugin = M.plugins[plugin_name]
	if not plugin then
		vim.notify("Unknown sync plugin: " .. plugin_name, vim.log.levels.ERROR)
		return
	end

	local plugin_config = config.sync.plugins[plugin_name]
	if not plugin_config or not plugin_config.enabled then
		vim.notify("Sync plugin '" .. plugin_name .. "' is disabled", vim.log.levels.WARN)
		return
	end

	-- Check sync lock
	if sync_locks[plugin_name] then
		vim.notify("Sync already in progress for " .. plugin_name, vim.log.levels.WARN)
		return
	end

	-- Set lock
	sync_locks[plugin_name] = true

	-- Show progress notification
	vim.notify("Syncing " .. (plugin.description or plugin_name) .. "...", vim.log.levels.INFO)

	-- Call plugin sync
	local ok, result, err = pcall(plugin.sync)

	if not ok then
		-- Plugin errored
		vim.notify("Sync failed for " .. plugin_name .. ": " .. tostring(result), vim.log.levels.ERROR)
		sync_locks[plugin_name] = false
		return
	end

	if not result then
		-- Plugin returned nil (error)
		vim.notify("Sync failed for " .. plugin_name .. ": " .. tostring(err or "unknown error"), vim.log.levels.ERROR)
		sync_locks[plugin_name] = false
		return
	end

	-- Extract events and stats
	local events = result.events or {}
	local stats = result.stats or {}

	-- Write to sync file
	write_sync_file(events, plugin_name, plugin_config, stats)

	-- Success notification
	local count = stats.count or #events
	vim.notify(string.format("Synced %d events from %s", count, plugin.description or plugin_name), vim.log.levels.INFO)

	-- Clear lock
	sync_locks[plugin_name] = false
end

--- Sync all enabled plugins
function M.sync_all()
	local synced_count = 0

	for plugin_name, plugin in pairs(M.plugins) do
		local plugin_config = config.sync.plugins[plugin_name]
		if plugin_config and plugin_config.enabled then
			M.sync_plugin(plugin_name)
			synced_count = synced_count + 1
		end
	end

	if synced_count == 0 then
		vim.notify("No sync plugins enabled", vim.log.levels.WARN)
	end
end

-- ============================================================================
-- AUTO-SYNC
-- ============================================================================

--- Setup auto-sync timers for plugins that support it
function M.setup_auto_sync()
	for plugin_name, plugin in pairs(M.plugins) do
		if not plugin.supports_auto_sync then
			goto continue
		end

		local plugin_config = config.sync.plugins[plugin_name]
		if not plugin_config or not plugin_config.enabled or not plugin_config.auto_sync then
			goto continue
		end

		local interval = plugin_config.auto_sync_interval or 3600 -- Default 1 hour
		if interval < 60 then
			vim.notify("Auto-sync interval for " .. plugin_name .. " too short (minimum 60s), using 60s", vim.log.levels.WARN)
			interval = 60
		end

		-- Create timer
		local timer = vim.loop.new_timer()
		timer:start(
			0, -- Start immediately
			interval * 1000, -- Interval in ms
			vim.schedule_wrap(function()
				M.sync_plugin(plugin_name)
			end)
		)

		auto_sync_timers[plugin_name] = timer

		::continue::
	end
end

--- Stop all auto-sync timers (for cleanup)
function M.stop_auto_sync()
	for plugin_name, timer in pairs(auto_sync_timers) do
		timer:stop()
		timer:close()
		auto_sync_timers[plugin_name] = nil
	end
end

return M
