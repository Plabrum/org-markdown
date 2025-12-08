local config = require("org_markdown.config")
local utils = require("org_markdown.utils.utils")
local datetime = require("org_markdown.utils.datetime")
local async = require("org_markdown.utils.async")

local M = {}

-- Plugin registry
M.plugins = {}

-- Auto-sync timers
local auto_sync_timers = {}

-- =====================================================================
-- ASYNC COMMAND EXECUTION
-- =====================================================================

--- Execute a shell command asynchronously (non-blocking)
--- When called from a coroutine context (inside async.run), automatically awaits and returns the result directly
--- When called outside a coroutine, returns a promise
--- @param cmd string|table Command to execute (string or table for jobstart)
--- @return table|nil, string|nil Output lines (success), error message (failure)
function M.execute_command(cmd)
	local promise = async.promise(function(resolve, reject)
		local stdout_lines = {}
		local stderr_lines = {}

		vim.fn.jobstart(cmd, {
			stdout_buffered = true,
			stderr_buffered = true,
			on_stdout = function(_, data)
				if data then
					for _, line in ipairs(data) do
						if line ~= "" then
							table.insert(stdout_lines, line)
						end
					end
				end
			end,
			on_stderr = function(_, data)
				if data then
					for _, line in ipairs(data) do
						if line ~= "" then
							table.insert(stderr_lines, line)
						end
					end
				end
			end,
			on_exit = function(_, exit_code)
				if exit_code == 0 then
					resolve(stdout_lines)
				else
					local error_msg = #stderr_lines > 0 and table.concat(stderr_lines, "\n")
						or ("Command failed with exit code " .. exit_code)
					reject(error_msg)
				end
			end,
		})
	end)

	-- Auto-await if we're in a coroutine context (plugin.pull() is wrapped in async.run)
	local co = coroutine.running()
	if co then
		-- We're in a coroutine - manually handle promise to avoid throwing errors
		-- Set up callbacks and yield
		local success, result
		promise
			:then_(function(val)
				success = true
				result = val
				coroutine.resume(co)
			end)
			:catch_(function(e)
				success = false
				result = e
				coroutine.resume(co)
			end)

		coroutine.yield()

		-- Return result
		if success then
			return result, nil
		else
			return nil, tostring(result)
		end
	else
		-- Not in coroutine - return promise for manual handling
		return promise
	end
end

-- =====================================================================
-- ITEM VALIDATION SCHEMA
-- =====================================================================

local ITEM_SCHEMA = {
	-- Required fields
	title = {
		type = "string",
		required = true,
		validate = function(v)
			return v and v ~= ""
		end,
		error_msg = "title must be non-empty string",
	},

	-- Date fields (optional - items can be notes without dates)
	start_date = {
		type = "table",
		required = false,
		validate = function(v)
			return not v or (v.year and v.month and v.day)
		end,
		error_msg = "start_date must have year, month, day if provided",
	},

	due_date = {
		type = "table",
		required = false,
		validate = function(v)
			return not v or (v.year and v.month and v.day)
		end,
		error_msg = "due_date must have year, month, day if provided",
	},

	end_date = {
		type = "table",
		required = false,
		validate = function(v)
			return not v or (v.year and v.month and v.day)
		end,
		error_msg = "end_date must have year, month, day if provided",
	},

	-- Time fields (optional - for timed items)
	all_day = {
		type = "boolean",
		required = false,
		error_msg = "all_day must be boolean if provided",
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

	-- Org-markdown fields
	status = {
		type = "string",
		required = false,
		validate = function(v)
			if not v then
				return true
			end
			local valid_states = config.status_states
			return vim.tbl_contains(valid_states, v)
		end,
		error_msg = "status must be valid state from config.status_states",
	},

	priority = {
		type = "string",
		required = false,
		validate = function(v)
			return not v or v:match("^[A-Z]$")
		end,
		error_msg = "priority must be single uppercase letter",
	},

	tags = {
		type = "table",
		required = false,
		validate = function(v)
			return not v or vim.tbl_islist(v)
		end,
		error_msg = "tags must be array of strings",
	},

	-- Content
	body = {
		type = "string",
		required = false,
	},

	description = {
		type = "string",
		required = false,
	},
}

--- Validate an item against the schema
--- @param item table Item to validate
--- @param plugin_name string Plugin name (for error messages)
--- @return boolean, table|nil, string|nil Success, errors array, formatted error message
local function validate_item(item, plugin_name)
	if not item or type(item) ~= "table" then
		return false, { "Item must be a table" }, "[" .. plugin_name .. "] Item must be a table"
	end

	local errors = {}

	for field_name, schema in pairs(ITEM_SCHEMA) do
		local value = item[field_name]

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
			"[%s] Invalid item '%s':\n  - %s",
			plugin_name,
			item.title or "(no title)",
			table.concat(errors, "\n  - ")
		)
		return false, errors, err_msg
	end

	return true, nil, nil
end

-- =========================================================================
-- PLUGIN REGISTRATION
-- =========================================================================

--- Register a sync plugin
--- @param plugin_module table Plugin module with required interface
function M.register_plugin(plugin_module)
	-- Validate plugin interface
	if not plugin_module.name then
		vim.notify("Sync plugin missing 'name' field", vim.log.levels.ERROR)
		return false
	end

	if not plugin_module.sync_file then
		vim.notify("Sync plugin '" .. plugin_module.name .. "' missing 'sync_file' field", vim.log.levels.ERROR)
		return false
	end

	if type(plugin_module.pull) ~= "function" then
		vim.notify("Sync plugin '" .. plugin_module.name .. "' missing 'pull' function", vim.log.levels.ERROR)
		return false
	end

	-- Add to registry
	M.plugins[plugin_module.name] = plugin_module

	-- Initialize config structure
	if not config.sync then
		config.sync = { plugins = {} }
	end
	if not config.sync.plugins then
		config.sync.plugins = {}
	end
	if not config.sync.plugins[plugin_module.name] then
		config.sync.plugins[plugin_module.name] = {}
	end

	-- Set sync_file from plugin definition (can be overridden in user config)
	if not config.sync.plugins[plugin_module.name].sync_file then
		config.sync.plugins[plugin_module.name].sync_file = plugin_module.sync_file
	end

	-- Merge default config into config.sync.plugins[name]
	if plugin_module.default_config then
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

	-- Setup auto-push if enabled and plugin supports it
	local plugin_config = config.sync.plugins[plugin_module.name]
	if plugin_config.auto_push and type(plugin_module.push) == "function" then
		local sync_file = vim.fn.expand(plugin_config.sync_file)
		vim.api.nvim_create_autocmd("BufWritePost", {
			pattern = sync_file,
			callback = function()
				-- Prevent recursive pushes during sync operations
				if not plugin_module._is_syncing then
					plugin_module.push()
				end
			end,
			desc = string.format("Auto-push changes to %s", plugin_module.description or plugin_module.name),
		})
	end

	return true
end

-- =========================================================================
-- ITEM FORMATTING
-- =========================================================================

--- Format date range for an item
--- @param item table Item with start_date, end_date, start_time, end_time, all_day
--- @return string Formatted date range
local function format_date_range(item)
	-- Delegate to datetime module
	return datetime.format_date_range(item.start_date, item.end_date, {
		all_day = item.all_day,
		start_time = item.start_time,
		end_time = item.end_time,
	})
end

--- Format an item as markdown lines
--- @param item table Item data structure
--- @param plugin_config table Plugin configuration
--- @return table Array of markdown lines
local function format_item_as_markdown(item, plugin_config)
	local lines = {}
	local heading_level = plugin_config.heading_level or 1

	-- Build heading parts
	local heading_parts = { string.rep("#", heading_level) }

	-- Add status if present
	if item.status then
		table.insert(heading_parts, item.status)
	end

	-- Add priority if present
	if item.priority then
		table.insert(heading_parts, "[#" .. item.priority .. "]")
	end

	-- Add title
	table.insert(heading_parts, item.title)

	local heading = table.concat(heading_parts, " ")

	-- Add date ONLY if present (items can be notes without dates)
	local date_str = nil
	if item.start_date then
		date_str = format_date_range(item)
	elseif item.due_date then
		-- Format due_date as tracked date for agenda
		date_str = string.format("<%04d-%02d-%02d>", item.due_date.year, item.due_date.month, item.due_date.day)
	end

	if date_str then
		heading = heading .. " " .. date_str
	end

	-- Add tags with minimal padding
	if item.tags and #item.tags > 0 then
		local tag_str = ":" .. table.concat(item.tags, ":") .. ":"
		heading = heading .. " " .. tag_str
	end

	table.insert(lines, heading)

	-- Add body/description (plugins format their own metadata here)
	if item.body and item.body ~= "" then
		table.insert(lines, "")
		table.insert(lines, item.body)
	elseif item.description and item.description ~= "" then
		table.insert(lines, "")
		table.insert(lines, item.description)
	end

	-- Blank line after item
	table.insert(lines, "")

	return lines
end

-- =========================================================================
-- FILE OPERATIONS
-- =========================================================================

--- Write items to sync file (simple - replaces file content)
--- @param items table Array of items
--- @param plugin_name string Plugin name
--- @param plugin_config table Plugin configuration
--- @param stats table Sync statistics
local function write_sync_file(items, plugin_name, plugin_config, stats)
	local lines = {}

	-- YAML frontmatter (if file_heading is specified)
	if plugin_config.file_heading and plugin_config.file_heading ~= "" then
		table.insert(lines, "---")
		table.insert(lines, "name: " .. plugin_config.file_heading)
		table.insert(lines, "---")
		table.insert(lines, "")
	end

	-- Warning header
	table.insert(lines, "<!-- AUTO-MANAGED: Do not edit. Changes will be overwritten. -->")
	table.insert(lines, string.format("<!-- Last synced: %s -->", os.date("%Y-%m-%d %H:%M:%S")))

	-- Add all stats as metadata comments (generic - plugins can add any stats they want)
	for key, value in pairs(stats) do
		if key ~= "count" then -- Skip count, it's shown in success notification
			local formatted_value
			if type(value) == "table" then
				formatted_value = string.format("%s (%d total)", table.concat(value, ", "), #value)
			else
				formatted_value = tostring(value)
			end
			-- Convert key to Title Case for display
			local display_key = key:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
				return first:upper() .. rest:lower()
			end)
			table.insert(lines, string.format("<!-- %s: %s -->", display_key, formatted_value))
		end
	end
	table.insert(lines, "")

	-- Format items
	for _, item in ipairs(items) do
		local item_lines = format_item_as_markdown(item, plugin_config)
		for _, line in ipairs(item_lines) do
			table.insert(lines, line)
		end
	end

	-- Write to file (simple - just replace content)
	local filepath = vim.fn.expand(plugin_config.sync_file)
	utils.write_lines(filepath, lines)
end

-- =========================================================================
-- SYNC OPERATIONS
-- =========================================================================

--- Sync a specific plugin (pull data from external source)
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

	-- Set syncing flag to prevent auto-push during sync
	plugin._is_syncing = true

	-- Run plugin pull in async context (allows plugins to use execute_command with :await())
	async.run(function()
		local ok, result, err = pcall(plugin.pull)

		if not ok then
			-- pcall failed (exception thrown)
			plugin._is_syncing = false
			vim.schedule(function()
				vim.notify(
					string.format("Pull failed for %s: %s", plugin.description or plugin_name, tostring(result)),
					vim.log.levels.ERROR
				)
			end)
			return
		end

		if not result then
			-- pull() returned nil (with optional error message)
			plugin._is_syncing = false
			vim.schedule(function()
				vim.notify(
					string.format("Pull failed for %s: %s", plugin.description or plugin_name, tostring(err or "no data")),
					vim.log.levels.ERROR
				)
			end)
			return
		end

		-- Extract items and stats
		local items = result.items or result.events or {} -- Support both "items" and legacy "events"
		local stats = result.stats or {}

		if #items == 0 then
			plugin._is_syncing = false
			vim.schedule(function()
				vim.notify(
					string.format("Pull completed for %s: no items returned", plugin.description or plugin_name),
					vim.log.levels.WARN
				)
			end)
			return
		end

		-- Validate and filter items
		local valid_items = vim.tbl_filter(function(item)
			local valid = validate_item(item, plugin_name)
			return valid
		end, items)

		if #valid_items == 0 then
			plugin._is_syncing = false
			vim.schedule(function()
				vim.notify(
					string.format("Pull failed for %s: all %d items invalid", plugin.description or plugin_name, #items),
					vim.log.levels.ERROR
				)
			end)
			return
		end

		-- Write to sync file
		write_sync_file(valid_items, plugin_name, plugin_config, stats)

		-- Clear syncing flag
		plugin._is_syncing = false

		-- Success notification
		local count = stats.count or #valid_items
		local msg = string.format("Synced %d items from %s", count, plugin.description or plugin_name)
		local invalid_count = #items - #valid_items
		if invalid_count > 0 then
			msg = msg .. string.format(" (%d skipped)", invalid_count)
		end
		vim.schedule(function()
			vim.notify(msg, vim.log.levels.INFO)
		end)
	end)
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

-- =========================================================================
-- AUTO-SYNC
-- =========================================================================

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
			interval * 1000, -- Delay first run by interval (don't run on startup)
			interval * 1000, -- Then repeat at interval
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

-- =========================================================================
-- ASYNC PULL (for startup)
-- =========================================================================

--- Pull all enabled plugins in background after startup
--- Runs silently - failures don't show notifications. If network is slow/unavailable,
--- the pull will complete in background without blocking the UI.
function M.pull_all_async()
	-- Collect enabled plugins
	local plugins_to_pull = {}
	for plugin_name, plugin in pairs(M.plugins) do
		local plugin_config = config.sync.plugins[plugin_name]
		if plugin_config and plugin_config.enabled then
			table.insert(plugins_to_pull, plugin_name)
		end
	end

	if #plugins_to_pull == 0 then
		return
	end

	-- Pull each plugin in background (scheduled to not block UI)
	for _, plugin_name in ipairs(plugins_to_pull) do
		vim.schedule(function()
			local plugin = M.plugins[plugin_name]
			local plugin_config = config.sync.plugins[plugin_name]

			if not plugin or not plugin_config then
				return
			end

			-- Set syncing flag
			plugin._is_syncing = true

			-- Run plugin pull in async context (allows plugins to use execute_command with auto-await)
			-- All errors are caught silently (this is a background operation)
			async.run(function()
				-- Wrap everything in pcall to catch errors from awaited promises
				local success, result = pcall(function()
					return plugin.pull()
				end)

				if not success then
					-- Error occurred (could be network timeout, command failure, etc.) - silent
					plugin._is_syncing = false
					return
				end

				if not result then
					-- pull() returned nil - silent
					plugin._is_syncing = false
					return
				end

				-- Extract items and stats
				local items = result.items or result.events or {}
				local stats = result.stats or {}

				if #items == 0 then
					plugin._is_syncing = false
					return
				end

				-- Validate and filter items
				local valid_items = vim.tbl_filter(function(item)
					return validate_item(item, plugin_name)
				end, items)

				if #valid_items > 0 then
					-- Write to sync file (silent)
					write_sync_file(valid_items, plugin_name, plugin_config, stats)
				end

				plugin._is_syncing = false
			end)
		end)
	end
end

return M
