local config = require("org_markdown.config")
local secrets = require("org_markdown.utils.secrets")

local M = {
	name = "sheets",
	description = "Sync tasks from Google Sheets",
	sync_file = "~/org/sheets.md",

	default_config = {
		enabled = false,
		sync_file = "~/org/sheets.md",
		file_heading = "", -- Optional: YAML frontmatter heading (e.g., "Sheets Tasks")

		-- Authentication (pick one method)
		api_key = "", -- Simplest: Google API key (requires public sheet, READ-ONLY)
		use_gcloud = false, -- OAuth via gcloud CLI (supports read/write)
		access_token = "", -- Alternative: Manual OAuth2 access token (supports read/write)
		quota_project = "", -- Required for OAuth: Google Cloud project ID for billing/quota

		-- Sync direction
		bidirectional = false, -- Enable write-back to sheet (requires OAuth)
		auto_push = false, -- Enable auto-push on file save (requires bidirectional=true)

		-- Spreadsheet identification
		spreadsheet_id = "", -- Required: From URL docs.google.com/spreadsheets/d/{ID}/
		sheet_name = "Sheet1", -- Tab name within spreadsheet

		-- Column mapping (by column name from header row)
		columns = {
			title = "Feature", -- Required: maps to item title
			status = "Status", -- Optional: maps to TODO/IN_PROGRESS/DONE
			priority = "Priority", -- Optional: numeric -> letter conversion
			tags = { "Task Type" }, -- Optional: array of columns to become tags
			body = { "Bug Feature", "Owner", "Notes" }, -- Optional: formatted into body
		},

		-- Data conversions
		conversions = {
			-- Status mapping (case-insensitive matching)
			status_map = {
				["todo"] = "TODO",
				["in progress"] = "IN_PROGRESS",
				["done"] = "DONE",
				["cancelled"] = "CANCELLED",
				["waiting"] = "WAITING",
				["blocked"] = "BLOCKED",
			},

			-- Priority ranges (numeric -> letter)
			priority_ranges = {
				{ min = 1, max = 3, letter = "A" },
				{ min = 4, max = 6, letter = "B" },
				{ min = 7, max = 10, letter = "C" },
			},

			-- Tag sanitization
			sanitize_tags = true, -- Convert to lowercase, replace spaces with hyphens
		},

		-- Other settings
		heading_level = 2,
		auto_sync = false,
		auto_sync_interval = 1800, -- 30 minutes
	},

	supports_auto_sync = true,
	command_name = "MarkdownSyncSheets",
	keymap = "<leader>osh",
}

-- =========================================================================
-- OAUTH TOKEN MANAGEMENT
-- =========================================================================

--- Get OAuth2 access token from gcloud CLI
--- @return string|nil, string|nil Access token, error message
local function get_gcloud_token()
	local manager = require("org_markdown.sync.manager")

	-- Check if gcloud is available
	local _, err = manager.execute_command("which gcloud")
	if err then
		return nil, "gcloud CLI not found. Install via 'brew install google-cloud-sdk'"
	end

	-- Get access token using gcloud
	local cmd = "CLOUDSDK_PYTHON=/opt/homebrew/bin/python3 gcloud auth application-default print-access-token"
	local token_lines, err = manager.execute_command(cmd)

	if not token_lines then
		return nil, "Failed to get gcloud token. Run 'gcloud auth application-default login' first"
	end

	-- Join lines and trim whitespace
	local token = table.concat(token_lines, "\n"):match("^%s*(.-)%s*$")

	if not token or token == "" then
		return nil, "gcloud returned empty token"
	end

	return token, nil
end

-- =========================================================================
-- DATA TRANSFORMATION HELPERS
-- =========================================================================

--- Map raw status value to org-markdown status
--- @param raw_status string|nil Raw status from sheet
--- @param status_map table Status mapping configuration
--- @return string|nil Org-markdown status (TODO, IN_PROGRESS, DONE, etc.)
local function map_status(raw_status, status_map)
	if not raw_status or raw_status == "" then
		return nil
	end

	-- Normalize: lowercase, trim whitespace
	local normalized = raw_status:lower():match("^%s*(.-)%s*$")

	-- Look up in status_map (exact match first)
	for pattern, org_status in pairs(status_map) do
		if normalized == pattern:lower() then
			return org_status
		end
	end

	-- Fallback: fuzzy matching for common patterns
	if normalized:match("todo") or normalized:match("backlog") then
		return "TODO"
	elseif normalized:match("progress") or normalized:match("doing") or normalized:match("started") then
		return "IN_PROGRESS"
	elseif normalized:match("done") or normalized:match("complete") then
		return "DONE"
	elseif normalized:match("cancel") then
		return "CANCELLED"
	elseif normalized:match("wait") then
		return "WAITING"
	elseif normalized:match("block") then
		return "BLOCKED"
	end

	return nil -- Unknown status -> treat as note without status
end

--- Map numeric priority to letter (A-Z)
--- @param raw_priority string|number|nil Raw priority from sheet
--- @param priority_ranges table Priority range mappings
--- @return string|nil Priority letter (A, B, C, etc.)
local function map_priority(raw_priority, priority_ranges)
	if not raw_priority then
		return nil
	end

	-- Convert to number
	local priority_num = tonumber(raw_priority)
	if not priority_num then
		-- Try to extract number from string (e.g., "P1" -> 1)
		priority_num = tonumber(raw_priority:match("%d+"))
	end

	if not priority_num then
		return nil
	end

	-- Check against range mappings
	for _, range in ipairs(priority_ranges) do
		if priority_num >= range.min and priority_num <= range.max then
			return range.letter
		end
	end

	return nil -- Outside configured ranges
end

--- Sanitize tag value for org-markdown format
--- @param tag_value string|nil Raw tag value from sheet
--- @param should_sanitize boolean Whether to sanitize the tag
--- @return string|nil Sanitized tag
local function sanitize_tag(tag_value, should_sanitize)
	if not tag_value or tag_value == "" then
		return nil
	end

	local tag = tag_value

	if should_sanitize then
		-- Remove special characters, convert to lowercase, replace spaces with hyphens
		tag = tag
			:gsub("[^%w%s-]", "") -- Remove special chars
			:gsub("%s+", "-") -- Replace spaces with hyphens
			:lower() -- Lowercase
	end

	-- Return nil if sanitization resulted in empty string
	if tag == "" then
		return nil
	end

	return tag
end

-- =========================================================================
-- GOOGLE SHEETS API INTEGRATION
-- =========================================================================

--- Fetch sheet data from Google Sheets API
--- @param spreadsheet_id string Spreadsheet ID from URL
--- @param sheet_name string Sheet/tab name
--- @param auth_param string Either API key or OAuth2 access token
--- @param use_api_key boolean If true, treat auth_param as API key; otherwise as OAuth token
--- @param quota_project string|nil Google Cloud quota project ID (for OAuth)
--- @return table|nil, string|nil Raw sheet data (2D array), error message
local function fetch_sheet_data(spreadsheet_id, sheet_name, auth_param, use_api_key, quota_project)
	local manager = require("org_markdown.sync.manager")

	-- Build API URL with range (A:Z for all columns)
	local range = sheet_name .. "!A:Z"
	local base_url = string.format("https://sheets.googleapis.com/v4/spreadsheets/%s/values/%s", spreadsheet_id, range)

	-- Build curl command based on auth method
	local cmd
	if use_api_key then
		-- API key: add as query parameter (for public sheets)
		-- Don't use shellescape here - the key is embedded in the URL which is already quoted
		local url = base_url .. "?key=" .. auth_param
		cmd = string.format('curl -s "%s"', url)
	else
		-- OAuth: add as bearer token header + quota project header (if provided)
		if quota_project and quota_project ~= "" then
			cmd = string.format(
				'curl -s -H "Authorization: Bearer %s" -H "x-goog-user-project: %s" "%s"',
				auth_param,
				quota_project,
				base_url
			)
		else
			cmd = string.format('curl -s -H "Authorization: Bearer %s" "%s"', auth_param, base_url)
		end
	end

	-- Execute async (auto-awaits in coroutine context)
	local output_lines, err = manager.execute_command(cmd)

	if not output_lines then
		return nil, "Google Sheets API request failed: " .. (err or "Unknown error")
	end

	-- Join lines into single string for JSON parsing
	local output = table.concat(output_lines, "\n")

	-- Parse JSON response
	local ok, response = pcall(vim.fn.json_decode, output)
	if not ok then
		return nil, "Failed to parse Google Sheets API response: " .. tostring(response)
	end

	-- Check for API errors
	if response.error then
		local error_msg = response.error.message or "Unknown error"
		if response.error.code == 401 then
			error_msg = error_msg .. " (Token may be expired - please refresh your access_token)"
		elseif response.error.code == 404 then
			error_msg = error_msg .. " (Check spreadsheet_id and sheet_name)"
		end
		return nil, "Google Sheets API error: " .. error_msg
	end

	-- Extract values (2D array)
	if not response.values or #response.values == 0 then
		return nil, "No data found in sheet: " .. sheet_name
	end

	return response.values, nil
end

--- Parse raw sheet values into row objects with column headers
--- @param values table 2D array from API (first row = headers)
--- @return table Array of row objects { column_name = value, _row_number = number }
local function parse_rows(values)
	if not values or #values < 2 then
		return {} -- No data rows (only headers or empty)
	end

	local headers = values[1] -- First row = column names
	local rows = {}

	for i = 2, #values do -- Skip header row
		local row_data = values[i]
		local row_obj = {
			_row_number = i, -- Track sheet row number (1-indexed, includes header)
		}

		for col_idx, header in ipairs(headers) do
			local cell_value = row_data[col_idx]
			-- Only add to row object if cell has non-empty value
			if cell_value and cell_value ~= "" then
				row_obj[header] = cell_value
			end
		end

		-- Only add row if it has at least one value (besides row number)
		local has_data = false
		for key, _ in pairs(row_obj) do
			if key ~= "_row_number" then
				has_data = true
				break
			end
		end
		if has_data then
			table.insert(rows, row_obj)
		end
	end

	return rows
end

-- =========================================================================
-- ITEM CONVERSION
-- =========================================================================

--- Convert a sheet row to standard item format
--- @param row table Row object with column values
--- @param column_config table Column mapping configuration
--- @param conversion_config table Data conversion configuration
--- @return table|nil Item object or nil if invalid
local function row_to_item(row, column_config, conversion_config)
	-- 1. Extract title (REQUIRED)
	local title_col = column_config.title
	if not title_col or not row[title_col] or row[title_col] == "" then
		return nil -- Skip rows without title
	end

	local item = {
		title = row[title_col],
		tags = {},
		_row_number = row._row_number, -- Track sheet row number for bi-directional sync
	}

	-- 2. Extract and map status
	if column_config.status and row[column_config.status] then
		item.status = map_status(row[column_config.status], conversion_config.status_map)
	end

	-- 3. Extract and map priority
	if column_config.priority and row[column_config.priority] then
		item.priority = map_priority(row[column_config.priority], conversion_config.priority_ranges)
	end

	-- 4. Extract tags from multiple columns
	if column_config.tags then
		for _, tag_col in ipairs(column_config.tags) do
			if row[tag_col] and row[tag_col] ~= "" then
				local tag = sanitize_tag(row[tag_col], conversion_config.sanitize_tags)
				if tag then
					table.insert(item.tags, tag)
				end
			end
		end
	end

	-- 5. Build body from multiple columns
	local body_parts = {}

	if column_config.body then
		for _, body_col in ipairs(column_config.body) do
			if row[body_col] and row[body_col] ~= "" then
				-- Format as "**Column Name:** Value"
				table.insert(body_parts, string.format("**%s:** %s", body_col, row[body_col]))
			end
		end
	end

	-- Add row number as property (for bi-directional sync)
	-- This gets parsed as a node property when the document is read
	if item._row_number then
		table.insert(body_parts, string.format("SHEET_ROW: [%d]", item._row_number))
	end

	if #body_parts > 0 then
		-- Two spaces at end for markdown line break
		item.body = table.concat(body_parts, "  \n")
	end

	return item
end

-- =========================================================================
-- MARKDOWN PARSING (for bi-directional sync)
-- =========================================================================

--- Parse existing markdown file to extract items with row numbers
--- @param filepath string Path to markdown file
--- @return table Array of items from markdown with _row_number field
local function parse_existing_markdown(filepath)
	local document = require("org_markdown.utils.document")
	local expanded_path = vim.fn.expand(filepath)

	-- Check if file exists
	if vim.fn.filereadable(expanded_path) == 0 then
		return {} -- File doesn't exist yet, no items
	end

	local root = document.read_from_file(expanded_path)
	local items = {}

	-- Recursive helper to collect items from document tree
	local function collect_items(node)
		if node.type == "heading" and node.parsed and node.parsed.text then
			local item = {
				title = node.parsed.text,
				status = node.parsed.state,
				priority = node.parsed.priority,
				tags = node.parsed.tags or {},
			}

			-- Get row number from node property
			local row_number = node:get_property("SHEET_ROW")
			if row_number then
				item._row_number = tonumber(row_number)
			end

			if item._row_number then
				table.insert(items, item)
			end
		end

		-- Recurse into children
		for _, child in ipairs(node.children or {}) do
			collect_items(child)
		end
	end

	collect_items(root)
	return items
end

-- =========================================================================
-- ITEM TO ROW CONVERSION (for push)
-- =========================================================================

--- Convert item back to sheet row format
--- @param item table Item object
--- @param headers table Array of column headers from sheet
--- @param column_config table Column mapping configuration
--- @param conversion_config table Data conversion configuration
--- @return table Array of cell values matching header order
local function item_to_row(item, headers, column_config, conversion_config)
	local row = {}

	-- Initialize all cells as empty
	for i = 1, #headers do
		row[i] = ""
	end

	-- Build column name -> index map
	local col_map = {}
	for i, header in ipairs(headers) do
		col_map[header] = i
	end

	-- Fill in values based on column mapping

	-- Title
	if column_config.title and col_map[column_config.title] then
		row[col_map[column_config.title]] = item.title or ""
	end

	-- Status (reverse mapping: org-markdown status -> sheet status)
	if column_config.status and col_map[column_config.status] and item.status then
		local original_status = nil
		for pattern, org_status in pairs(conversion_config.status_map) do
			if org_status == item.status then
				original_status = pattern
				break
			end
		end
		-- Capitalize first letter for readability
		if original_status then
			original_status = original_status:gsub("^%l", string.upper)
		end
		row[col_map[column_config.status]] = original_status or item.status
	end

	-- Priority (reverse mapping: letter -> numeric)
	if column_config.priority and col_map[column_config.priority] and item.priority then
		local numeric_priority = nil
		for _, range in ipairs(conversion_config.priority_ranges) do
			if range.letter == item.priority then
				-- Use the minimum of the range (A=1, B=4, C=7)
				numeric_priority = range.min
				break
			end
		end
		row[col_map[column_config.priority]] = tostring(numeric_priority or "")
	end

	return row
end

-- =========================================================================
-- SHEET WRITE OPERATIONS
-- =========================================================================

--- Update a row in the sheet
--- @param spreadsheet_id string Spreadsheet ID
--- @param sheet_name string Sheet name
--- @param row_number number Row number (1-indexed, includes header)
--- @param values table Array of cell values
--- @param auth_token string OAuth access token
--- @param quota_project string|nil Google Cloud quota project ID
--- @return boolean, string|nil Success, error message
local function update_sheet_row(spreadsheet_id, sheet_name, row_number, values, auth_token, quota_project)
	local manager = require("org_markdown.sync.manager")

	local range = string.format("%s!A%d:Z%d", sheet_name, row_number, row_number)
	local url = string.format(
		"https://sheets.googleapis.com/v4/spreadsheets/%s/values/%s?valueInputOption=RAW",
		spreadsheet_id,
		range
	)

	local payload = vim.fn.json_encode({ values = { values } })
	local headers = string.format('-H "Authorization: Bearer %s" -H "Content-Type: application/json"', auth_token)
	if quota_project and quota_project ~= "" then
		headers = headers .. string.format(' -H "x-goog-user-project: %s"', quota_project)
	end

	local cmd = string.format('curl -s -X PUT %s -d %s "%s"', headers, vim.fn.shellescape(payload), url)

	-- Execute async (auto-awaits in coroutine context)
	local output_lines, err = manager.execute_command(cmd)

	if not output_lines then
		return false, "Failed to update row " .. row_number .. ": " .. (err or "Unknown error")
	end

	local output = table.concat(output_lines, "\n")
	local ok, response = pcall(vim.fn.json_decode, output)
	if not ok or response.error then
		return false,
			"Failed to update row " .. row_number .. ": " .. (response.error and response.error.message or "Unknown error")
	end

	return true, nil
end

--- Append a row to the sheet
--- @param spreadsheet_id string Spreadsheet ID
--- @param sheet_name string Sheet name
--- @param values table Array of cell values
--- @param auth_token string OAuth access token
--- @param quota_project string|nil Google Cloud quota project ID
--- @return number|nil, string|nil Row number, error message
local function append_sheet_row(spreadsheet_id, sheet_name, values, auth_token, quota_project)
	local manager = require("org_markdown.sync.manager")

	local range = string.format("%s!A:Z", sheet_name)
	local url = string.format(
		"https://sheets.googleapis.com/v4/spreadsheets/%s/values/%s:append?valueInputOption=RAW",
		spreadsheet_id,
		range
	)

	local payload = vim.fn.json_encode({ values = { values } })
	local headers = string.format('-H "Authorization: Bearer %s" -H "Content-Type: application/json"', auth_token)
	if quota_project and quota_project ~= "" then
		headers = headers .. string.format(' -H "x-goog-user-project: %s"', quota_project)
	end

	local cmd = string.format('curl -s -X POST %s -d %s "%s"', headers, vim.fn.shellescape(payload), url)

	-- Execute async (auto-awaits in coroutine context)
	local output_lines, err = manager.execute_command(cmd)

	if not output_lines then
		return nil, "Failed to append row: " .. (err or "Unknown error")
	end

	local output = table.concat(output_lines, "\n")
	local ok, response = pcall(vim.fn.json_decode, output)
	if not ok or response.error then
		return nil, "Failed to append row: " .. (response.error and response.error.message or "Unknown error")
	end

	-- Extract row number from response (updates.updatedRange)
	if response.updates and response.updates.updatedRange then
		local row_num = response.updates.updatedRange:match("!A(%d+):")
		return tonumber(row_num), nil
	end

	return nil, "Could not determine new row number"
end

-- =========================================================================
-- MAIN PULL FUNCTION
-- =========================================================================

function M.pull()
	local plugin_config = config.sync.plugins.sheets

	-- Check if plugin is enabled
	if not plugin_config or not plugin_config.enabled then
		return nil, "Google Sheets sync is disabled"
	end

	-- Resolve secrets from config (supports env:, cmd:, file: prefixes)
	local api_key = secrets.resolve(plugin_config.api_key)
	local access_token = secrets.resolve(plugin_config.access_token)
	local spreadsheet_id = secrets.resolve(plugin_config.spreadsheet_id)
	local quota_project = secrets.resolve(plugin_config.quota_project)

	-- Validate spreadsheet ID
	if not spreadsheet_id or spreadsheet_id == "" then
		return nil, "Spreadsheet ID not configured. Set config.sync.plugins.sheets.spreadsheet_id"
	end

	-- Validate authentication method (in order of preference)
	local has_api_key = api_key and api_key ~= ""
	local has_manual_token = access_token and access_token ~= ""
	local use_gcloud = plugin_config.use_gcloud

	if not has_api_key and not has_manual_token and not use_gcloud then
		return nil, "Google Sheets sync requires authentication (api_key, access_token, or use_gcloud=true)"
	end

	-- Determine auth method and get credential
	local auth_param
	local use_api_key = false

	if has_api_key then
		-- Prefer API key (simplest)
		auth_param = api_key
		use_api_key = true
	elseif has_manual_token then
		-- Use manual OAuth token
		auth_param = access_token
	elseif use_gcloud then
		-- Get OAuth token from gcloud
		local token, err = get_gcloud_token()
		if not token then
			return nil, "Failed to get gcloud token: " .. err
		end
		auth_param = token
	else
		return nil, "No authentication method available"
	end

	-- Fetch sheet data from Google Sheets API
	local values, err = fetch_sheet_data(spreadsheet_id, plugin_config.sheet_name, auth_param, use_api_key, quota_project)

	if not values then
		return nil, err
	end

	local headers = values[1] -- First row = column headers

	-- Parse rows from 2D array
	local rows = parse_rows(values)

	-- Convert sheet rows to items
	local sheet_items = {}
	local sheet_items_by_row = {} -- Map: row_number -> {item=item, index=index in sheet_items}
	for _, row in ipairs(rows) do
		local item = row_to_item(row, plugin_config.columns, plugin_config.conversions)
		if item then
			table.insert(sheet_items, item)
			if item._row_number then
				sheet_items_by_row[item._row_number] = { item = item, index = #sheet_items }
			end
		end
	end

	-- BI-DIRECTIONAL SYNC: Disabled during pull (sheets wins)
	-- Push only happens via explicit M.push() call or auto_push on save
	-- This ensures pull always overwrites markdown with sheet data

	-- Return sheet items (pull always uses sheet data)
	return {
		items = sheet_items,
		stats = {
			count = #sheet_items,
			source = "Google Sheets",
			sheet_name = plugin_config.sheet_name,
		},
	}
end

--- Push markdown changes to Google Sheets
--- Called automatically on file save if auto_push is enabled
function M.push()
	local plugin_config = config.sync.plugins.sheets
	if not plugin_config or not plugin_config.enabled then
		return
	end

	if not plugin_config.bidirectional then
		vim.notify("Sheets auto-push requires bidirectional=true", vim.log.levels.WARN)
		return
	end

	-- Resolve secrets
	local secrets = require("org_markdown.utils.secrets")
	local spreadsheet_id = secrets.resolve(plugin_config.spreadsheet_id)
	local quota_project = secrets.resolve(plugin_config.quota_project)

	if not spreadsheet_id or spreadsheet_id == "" then
		vim.notify("Sheets push failed: spreadsheet_id not configured", vim.log.levels.ERROR)
		return
	end

	-- Get OAuth token (push requires write access)
	local auth_token, err
	if plugin_config.use_gcloud then
		auth_token, err = get_gcloud_token()
	else
		local access_token = secrets.resolve(plugin_config.access_token)
		if access_token and access_token ~= "" then
			auth_token = access_token
		else
			err = "No access token configured (use_gcloud=false and access_token empty)"
		end
	end

	if not auth_token then
		vim.notify("Sheets push failed: " .. (err or "no auth token"), vim.log.levels.ERROR)
		return
	end

	-- Fetch sheet headers to get column positions
	local sheet_data, fetch_err =
		fetch_sheet_data(spreadsheet_id, plugin_config.sheet_name, auth_token, false, quota_project)
	if not sheet_data then
		vim.notify("Sheets push failed: " .. (fetch_err or "could not fetch sheet"), vim.log.levels.ERROR)
		return
	end

	local rows = parse_sheet_response(sheet_data)
	if #rows == 0 then
		vim.notify("Sheets push failed: sheet is empty", vim.log.levels.ERROR)
		return
	end

	local headers = rows[1] -- First row is headers

	-- Parse markdown file
	local md_items = parse_existing_markdown(plugin_config.sync_file)
	if #md_items == 0 then
		-- No items to push (file might be empty or newly created)
		return
	end

	-- Push each item
	local push_count = 0
	for _, item in ipairs(md_items) do
		if item._row_number then
			local row_values = item_to_row(item, headers, plugin_config.columns, plugin_config.conversions)
			local success, push_err =
				update_sheet_row(spreadsheet_id, plugin_config.sheet_name, item._row_number, row_values, auth_token, quota_project)

			if success then
				push_count = push_count + 1
			else
				vim.notify(
					string.format("Failed to push row %d: %s", item._row_number, push_err or "unknown error"),
					vim.log.levels.WARN
				)
			end
		end
	end

	if push_count > 0 then
		vim.notify(string.format("Pushed %d changes to Google Sheets", push_count), vim.log.levels.INFO)
	end
end

return M
