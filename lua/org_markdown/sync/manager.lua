local config = require("org_markdown.config")
local utils = require("org_markdown.utils.utils")
local datetime = require("org_markdown.utils.datetime")

local M = {}

-- Plugin registry
M.plugins = {}

-- Sync locks to prevent concurrent syncs
local sync_locks = {}

-- Auto-sync timers
local auto_sync_timers = {}

-- ============================================================================
-- EVENT VALIDATION SCHEMA
-- ============================================================================

local EVENT_SCHEMA = {
	-- Required fields
	title = {
		type = "string",
		required = true,
		validate = function(v)
			return v and v ~= ""
		end,
		error_msg = "title must be non-empty string",
	},

	start_date = {
		type = "table",
		required = true,
		validate = function(v)
			return v and v.year and v.month and v.day and v.day_name
		end,
		error_msg = "start_date must have year, month, day, day_name",
	},

	all_day = {
		type = "boolean",
		required = true,
		error_msg = "all_day must be boolean",
	},

	-- Optional fields
	end_date = {
		type = "table",
		required = false,
		validate = function(v)
			return not v or (v.year and v.month and v.day)
		end,
		error_msg = "end_date must have year, month, day if provided",
	},

	start_time = {
		type = "string",
		required = false,
		validate = function(v)
			return not v or v:match("^%d%d:%d%d$")
		end,
		error_msg = "start_time must be HH:MM format",
	},

	end_time = {
		type = "string",
		required = false,
		validate = function(v)
			return not v or v:match("^%d%d:%d%d$")
		end,
		error_msg = "end_time must be HH:MM format",
	},

	tags = {
		type = "table",
		required = false,
		validate = function(v)
			return not v or vim.tbl_islist(v)
		end,
		error_msg = "tags must be array of strings",
	},

	body = {
		type = "string",
		required = false,
	},

	-- Extended fields (Phase 3)
	id = { type = "string", required = false },
	source_url = { type = "string", required = false },
	location = { type = "string", required = false },
	description = { type = "string", required = false },
	status = {
		type = "string",
		required = false,
		validate = function(v)
			local valid_states = { "TODO", "IN_PROGRESS", "WAITING", "DONE", "CANCELLED", "BLOCKED" }
			return not v or vim.tbl_contains(valid_states, v)
		end,
		error_msg = "status must be valid state",
	},
	priority = {
		type = "string",
		required = false,
		validate = function(v)
			return not v or v:match("^[A-Z]$")
		end,
		error_msg = "priority must be single uppercase letter",
	},
}

--- Validate an event against the schema
--- @param event table Event to validate
--- @param plugin_name string Plugin name (for error messages)
--- @return boolean, table|nil, string|nil Success, errors array, formatted error message
local function validate_event(event, plugin_name)
	if not event or type(event) ~= "table" then
		return false, { "Event must be a table" }, "[" .. plugin_name .. "] Event must be a table"
	end

	local errors = {}

	for field_name, schema in pairs(EVENT_SCHEMA) do
		local value = event[field_name]

		-- Check required
		if schema.required and value == nil then
			table.insert(errors, field_name .. " is required")
			goto continue
		end

		-- Skip further validation if optional and not provided
		if not schema.required and value == nil then
			goto continue
		end

		-- Check type
		if type(value) ~= schema.type then
			table.insert(errors, string.format("%s must be %s, got %s", field_name, schema.type, type(value)))
			goto continue
		end

		-- Custom validation
		if schema.validate and not schema.validate(value) then
			table.insert(errors, schema.error_msg or field_name .. " is invalid")
		end

		::continue::
	end

	if #errors > 0 then
		local err_msg = string.format(
			"[%s] Invalid event '%s':\n  - %s",
			plugin_name,
			event.title or "(no title)",
			table.concat(errors, "\n  - ")
		)
		return false, errors, err_msg
	end

	return true, nil, nil
end

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

--- Format date range for an event
--- @param event table Event with start_date, end_date, start_time, end_time, all_day
--- @return string Formatted date range
local function format_date_range(event)
	-- Delegate to datetime module
	return datetime.format_date_range(event.start_date, event.end_date, {
		all_day = event.all_day,
		start_time = event.start_time,
		end_time = event.end_time,
	})
end

--- Format an event as markdown lines
--- @param event table Event data structure
--- @param plugin_config table Plugin configuration
--- @return table Array of markdown lines
local function format_event_as_markdown(event, plugin_config)
	local lines = {}
	local heading_level = plugin_config.heading_level or 1

	-- Build heading parts
	local heading_parts = { string.rep("#", heading_level) }

	-- Add status if present
	if event.status then
		table.insert(heading_parts, event.status)
	end

	-- Add priority if present
	if event.priority then
		table.insert(heading_parts, "[#" .. event.priority .. "]")
	end

	-- Add title
	table.insert(heading_parts, event.title)

	local heading = table.concat(heading_parts, " ")

	-- Add date
	local date_str = format_date_range(event)
	heading = heading .. " " .. date_str

	-- Add tags with minimal padding
	if event.tags and #event.tags > 0 then
		local tag_str = ":" .. table.concat(event.tags, ":") .. ":"
		heading = heading .. " " .. tag_str
	end

	table.insert(lines, heading)

	-- Add metadata section
	local metadata = {}

	if event.location then
		table.insert(metadata, "**Location:** " .. event.location)
	end

	if event.source_url then
		table.insert(metadata, "**Source:** " .. event.source_url)
	end

	if event.id then
		table.insert(metadata, "**ID:** `" .. event.id .. "`")
	end

	if #metadata > 0 then
		table.insert(lines, "")
		for _, line in ipairs(metadata) do
			table.insert(lines, line)
		end
	end

	-- Add description/body
	if event.description and event.description ~= "" then
		table.insert(lines, "")
		table.insert(lines, event.description)
	elseif event.body and event.body ~= "" then
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

--- Validate sync markers in a file
--- @param lines table Array of lines from file
--- @param plugin_name string Name of plugin (for marker identification)
--- @return boolean, string Success status and message
local function validate_markers(lines, plugin_name)
	local begin_pattern = vim.pesc(string.format("<!-- BEGIN ORG-MARKDOWN %s SYNC -->", plugin_name:upper()))
	local end_pattern = vim.pesc(string.format("<!-- END ORG-MARKDOWN %s SYNC -->", plugin_name:upper()))

	local begin_count = 0
	local end_count = 0

	for _, line in ipairs(lines) do
		if line:match("^%s*" .. begin_pattern) then
			begin_count = begin_count + 1
		end
		if line:match("^%s*" .. end_pattern) then
			end_count = end_count + 1
		end
	end

	-- Validate
	if begin_count == 0 and end_count == 0 then
		return true, "no_markers" -- File has no sync section yet
	end

	if begin_count ~= end_count then
		return false,
			string.format("Marker mismatch: %d BEGIN, %d END markers. File may be corrupted.", begin_count, end_count)
	end

	if begin_count > 1 then
		return false, "Nested or duplicate markers detected. Manual cleanup required."
	end

	return true, "valid"
end

--- Read file and extract content outside sync markers
--- @param filepath string Path to file
--- @param plugin_name string Name of plugin (for marker identification)
--- @return table, table Lines before markers, lines after markers
local function read_preserved_content(filepath, plugin_name)
	local expanded_path = vim.fn.expand(filepath)

	-- Return empty tables if file doesn't exist
	if vim.fn.filereadable(expanded_path) == 0 then
		return {}, {}
	end

	local lines = utils.read_lines(expanded_path)

	-- VALIDATE FIRST - prevent data loss from corrupted markers
	local valid, status = validate_markers(lines, plugin_name)
	if not valid then
		vim.notify(string.format("[%s] Sync aborted: %s", plugin_name, status), vim.log.levels.ERROR)
		error("Marker validation failed: " .. status)
	end

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

--- Cleanup old backup files, keeping only the 3 most recent
--- @param filepath string Original file path
local function cleanup_old_backups(filepath)
	local dir = vim.fn.fnamemodify(filepath, ":h")
	local basename = vim.fn.fnamemodify(filepath, ":t")

	-- Find all backups for this file
	local backups = vim.fn.glob(dir .. "/" .. basename .. ".backup.*", false, true)

	-- Sort by timestamp (extracted from filename)
	table.sort(backups, function(a, b)
		local ts_a = a:match("%.backup%.(%d+)$")
		local ts_b = b:match("%.backup%.(%d+)$")
		return (tonumber(ts_a) or 0) > (tonumber(ts_b) or 0)
	end)

	-- Keep only 3 most recent, delete the rest
	for i = 4, #backups do
		vim.uv.fs_unlink(backups[i])
	end
end

--- Write sync file atomically with backup
--- @param filepath string Path to file
--- @param final_lines table Lines to write
--- @param plugin_name string Plugin name (for error messages)
local function write_sync_file_atomic(filepath, final_lines, plugin_name)
	local expanded = vim.fn.expand(filepath)

	-- Create backup if file exists
	if vim.fn.filereadable(expanded) == 1 then
		local backup_path = expanded .. ".backup." .. os.time()
		local copy_ok, copy_err = pcall(vim.uv.fs_copyfile, expanded, backup_path)
		if not copy_ok then
			vim.notify(
				string.format("[%s] Warning: Failed to create backup: %s", plugin_name, tostring(copy_err)),
				vim.log.levels.WARN
			)
		else
			-- Cleanup old backups after successful backup creation
			cleanup_old_backups(expanded)
		end
	end

	-- Write to temp file first
	local temp_path = expanded .. ".tmp"
	utils.write_lines(temp_path, final_lines)

	-- Atomic rename (on Unix, this is atomic)
	local rename_ok, rename_err = pcall(vim.uv.fs_rename, temp_path, expanded)
	if not rename_ok then
		-- Clean up temp file
		vim.uv.fs_unlink(temp_path)
		error("Failed to write sync file: " .. tostring(rename_err))
	end
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

	-- Write to file atomically with backup
	write_sync_file_atomic(filepath, final_lines, plugin_name)
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

	if not events or #events == 0 then
		vim.notify("[" .. plugin_name .. "] No events returned", vim.log.levels.WARN)
		sync_locks[plugin_name] = false
		return
	end

	-- Validate each event
	local valid_events = {}
	local invalid_count = 0

	for i, event in ipairs(events) do
		local valid, errors, err_msg = validate_event(event, plugin_name)

		if valid then
			table.insert(valid_events, event)
		else
			invalid_count = invalid_count + 1

			-- Log first few errors in detail
			if invalid_count <= 3 then
				vim.notify(err_msg, vim.log.levels.WARN)
			end
		end
	end

	if invalid_count > 3 then
		vim.notify(
			string.format("[%s] %d more events invalid (not shown)", plugin_name, invalid_count - 3),
			vim.log.levels.WARN
		)
	end

	-- Continue with valid events only
	if #valid_events == 0 then
		vim.notify("[" .. plugin_name .. "] No valid events to sync", vim.log.levels.ERROR)
		sync_locks[plugin_name] = false
		return
	end

	-- Write to sync file
	write_sync_file(valid_events, plugin_name, plugin_config, stats)

	-- Success notification
	local count = stats.count or #valid_events
	local msg = string.format("Synced %d events from %s", count, plugin.description or plugin_name)
	if invalid_count > 0 then
		msg = msg .. string.format(" (%d invalid, skipped)", invalid_count)
	end
	vim.notify(msg, vim.log.levels.INFO)

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
