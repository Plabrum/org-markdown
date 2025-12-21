local config = require("org_markdown.config")
local secrets = require("org_markdown.utils.secrets")
local mapping = require("org_markdown.sync.plugins.linear.mapping")
local api = require("org_markdown.sync.plugins.linear.api")
local push_helpers = require("org_markdown.sync.plugins.linear.push_helpers")

local M = {
	name = "linear",
	description = "Sync issues from Linear",
	sync_file = "~/org/linear.md",

	default_config = {
		enabled = false,
		sync_file = "~/org/linear.md",
		file_heading = "", -- Optional: YAML frontmatter heading (e.g., "Linear Issues")
		api_key = "", -- Required: Linear API key (get from https://linear.app/settings/api)
		include_assigned = true,
		include_cycles = false,
		team_ids = {}, -- Team keys (e.g., {"IF", "ENG"}) - Empty = all teams
		heading_level = 1,
		auto_sync = false,
		auto_sync_interval = 3600, -- 1 hour

		-- Status mapping: Linear state name → org-markdown status
		-- Multiple Linear states can map to the same org-markdown status
		-- Linear state names are matched case-insensitively using pattern matching
		status_mapping = {
			-- TODO states
			{ pattern = "backlog", status = "TODO" },
			{ pattern = "todo", status = "TODO" },
			{ pattern = "triage", status = "TODO" },

			-- IN_PROGRESS states
			{ pattern = "in progress", status = "IN_PROGRESS" },
			{ pattern = "in review", status = "IN_PROGRESS" },
			{ pattern = "started", status = "IN_PROGRESS" },
			{ pattern = "in development", status = "IN_PROGRESS" },

			-- DONE states
			{ pattern = "done", status = "DONE" },
			{ pattern = "completed", status = "DONE" },

			-- CANCELLED states
			{ pattern = "cancel", status = "CANCELLED" },
			{ pattern = "duplicate", status = "CANCELLED" },

			-- BLOCKED/WAITING states
			{ pattern = "block", status = "BLOCKED" },
			{ pattern = "waiting", status = "WAITING" },
		},

		-- Reverse mapping for push (org-markdown → Linear state name)
		-- Used when syncing changes back to Linear
		reverse_status_mapping = {
			TODO = "Todo",
			IN_PROGRESS = "In Progress",
			DONE = "Done",
			CANCELLED = "Canceled",
			BLOCKED = "Blocked",
			WAITING = "Waiting",
		},

		-- Push configuration (bidirectional sync: markdown → Linear)
		push = {
			enabled = false, -- Opt-in for safety
			staging_file = "~/org/linear-staging.md", -- File to capture new Linear issues (cleared after push)
			default_team_key = "", -- Required for creates (e.g., "IF", "ENG")
			auto_push = false, -- Enable BufWritePost trigger
			skip_on_conflict = true, -- Skip items if Linear was modified
			create_missing_labels = false, -- Create labels that don't exist
		},
	},

	supports_auto_sync = true,
	command_name = "MarkdownSyncLinear",
	keymap = "<leader>ol",
}

-- =========================================================================
-- ITEM CONVERSION (PULL)
-- =========================================================================

--- Convert Linear issue to item format
--- @param issue table Linear issue object
--- @param plugin_config table Plugin configuration
--- @return table Item
local function issue_to_item(issue, plugin_config)
	-- Build body with metadata and description
	local body_parts = {}

	-- Add metadata section
	local metadata = {}
	if not mapping.is_null(issue.assignee) and issue.assignee.name then
		table.insert(metadata, "**Assignee:** " .. issue.assignee.name)
	end
	if not mapping.is_null(issue.project) and issue.project.name then
		table.insert(metadata, "**Project:** " .. issue.project.name)
	end
	if not mapping.is_null(issue.state) and issue.state.name then
		table.insert(metadata, "**State:** " .. issue.state.name)
	end
	if not mapping.is_null(issue.url) then
		table.insert(metadata, "**URL:** " .. issue.url)
	end
	if not mapping.is_null(issue.identifier) then
		table.insert(metadata, "**ID:** `" .. issue.identifier .. "`")
	end

	if #metadata > 0 then
		table.insert(body_parts, table.concat(metadata, "  \n"))
	end

	-- Add description if present
	if not mapping.is_null(issue.description) and issue.description ~= "" then
		if #body_parts > 0 then
			table.insert(body_parts, "")
		end
		table.insert(body_parts, issue.description)
	end

	local item = {
		title = issue.title,
		status = mapping.map_linear_state(
			not mapping.is_null(issue.state) and issue.state.name or nil,
			plugin_config.status_mapping
		),
		priority = mapping.map_priority(issue.priority),
		due_date = mapping.parse_linear_date(not mapping.is_null(issue.dueDate) and issue.dueDate or nil),
		tags = {},
		body = #body_parts > 0 and table.concat(body_parts, "\n") or nil,
	}

	-- Add team tag
	if not mapping.is_null(issue.team) then
		table.insert(item.tags, issue.team.key)
	end

	-- Add project tag if present
	if not mapping.is_null(issue.project) then
		table.insert(item.tags, issue.project.name:gsub("%s+", "-"):lower())
	end

	return item
end

--- Convert Linear cycle to item format
--- @param cycle table Linear cycle object
--- @return table Item
local function cycle_to_item(cycle)
	-- Build body with metadata
	local metadata = {}
	if not mapping.is_null(cycle.team) and cycle.team.name then
		table.insert(metadata, "**Team:** " .. cycle.team.name)
	end
	if not mapping.is_null(cycle.id) then
		table.insert(metadata, "**ID:** `" .. cycle.id .. "`")
	end

	local item = {
		title = string.format("[%s] %s", cycle.team.key, cycle.name),
		start_date = mapping.parse_linear_date(not mapping.is_null(cycle.startsAt) and cycle.startsAt:match("^[^T]+") or nil),
		end_date = mapping.parse_linear_date(not mapping.is_null(cycle.endsAt) and cycle.endsAt:match("^[^T]+") or nil),
		all_day = true,
		tags = { "cycle", cycle.team.key },
		body = #metadata > 0 and table.concat(metadata, "  \n") or nil,
	}

	return item
end

-- =========================================================================
-- MAIN PULL FUNCTION
-- =========================================================================

function M.pull()
	local plugin_config = config.sync.plugins.linear
	if not plugin_config or not plugin_config.enabled then
		return nil, "Linear sync is disabled"
	end

	-- Resolve secrets from config (supports env:, cmd:, file: prefixes)
	local api_key = secrets.resolve(plugin_config.api_key)

	-- Validate API key
	if not api_key or api_key == "" then
		return nil, "Linear sync requires an API key. Set config.sync.plugins.linear.api_key"
	end

	local items = {}

	-- Fetch assigned issues
	if plugin_config.include_assigned then
		local issues, err = api.fetch_assigned_issues(api_key, plugin_config.team_ids or {})
		if not issues then
			return nil, err
		end

		for _, issue in ipairs(issues) do
			table.insert(items, issue_to_item(issue, plugin_config))
		end
	end

	-- Fetch cycles
	if plugin_config.include_cycles then
		local cycles, err = api.fetch_cycles(api_key, plugin_config.team_ids or {})
		if not cycles then
			return nil, err
		end

		for _, cycle in ipairs(cycles) do
			table.insert(items, cycle_to_item(cycle))
		end
	end

	-- Trigger push if enabled (bidirectional sync)
	if plugin_config.push and plugin_config.push.enabled then
		-- Run push asynchronously (doesn't block pull completion)
		M.push_to_linear()
	end

	return {
		items = items,
		stats = {
			count = #items,
			source = "Linear",
		},
	}
end

-- =========================================================================
-- PUSH: MAIN ORCHESTRATION
-- =========================================================================

--- Push markdown changes to Linear (bidirectional sync)
--- Runs asynchronously and doesn't block the UI
function M.push_to_linear()
	local async = require("org_markdown.utils.async")

	async.run(function()
		local plugin_config = config.sync.plugins.linear

		-- Validation
		if not plugin_config or not plugin_config.push or not plugin_config.push.enabled then
			return
		end

		-- Resolve API key
		local api_key = secrets.resolve(plugin_config.api_key)
		if not api_key or api_key == "" then
			vim.schedule(function()
				vim.notify("Linear API key required for push", vim.log.levels.ERROR)
			end)
			return
		end

		-- Validate team key for creates
		local default_team_key = plugin_config.push.default_team_key
		if not default_team_key or default_team_key == "" then
			vim.schedule(function()
				vim.notify("Linear push requires config.sync.plugins.linear.push.default_team_key", vim.log.levels.ERROR)
			end)
			return
		end

		-- Reset cache for this push operation
		api.reset_push_cache()

		-- Get team ID (required for creates)
		local team_id, err = api.get_team_id(api_key, default_team_key)
		if not team_id then
			vim.schedule(function()
				vim.notify(
					string.format("Failed to get team ID for '%s': %s", default_team_key, err or "unknown error"),
					vim.log.levels.ERROR
				)
			end)
			return
		end

		-- Scan files for items to push
		local items = push_helpers.scan_files_for_push_items(plugin_config.push.staging_file)

		if #items == 0 then
			vim.schedule(function()
				vim.notify("No items to push to Linear", vim.log.levels.INFO)
			end)
			return
		end

		-- Push each item
		local results = {
			success = 0,
			failed = 0,
			created = 0,
			updated = 0,
			skipped = 0,
			conflicts = 0,
			deleted = 0,
		}

		for _, item in ipairs(items) do
			-- Add reverse status mapping to item for API calls
			item.reverse_status_mapping = plugin_config.reverse_status_mapping

			local ok, push_err = pcall(function()
				if item.linear_id then
					-- UPDATE existing issue
					-- First, fetch current state for conflict detection
					local linear_issue, fetch_err = api.fetch_linear_issue(api_key, item.linear_id)
					if fetch_err then
						error("Failed to fetch issue: " .. fetch_err)
					end

					-- Check if we should push (conflict detection)
					local should_push, reason = push_helpers.should_push_item(item, linear_issue)

					if not should_push then
						if reason == "conflict" then
							results.conflicts = results.conflicts + 1
							results.skipped = results.skipped + 1
						elseif reason == "deleted" then
							-- Issue was deleted in Linear - clear metadata so it can be recreated
							vim.schedule(function()
								push_helpers.clear_linear_metadata(item.file, item.line)
							end)
							results.deleted = results.deleted + 1
							results.skipped = results.skipped + 1
						end
						return
					end

					-- Update issue in Linear
					local updated_issue, update_err = api.update_linear_issue(item, api_key, team_id)
					if updated_issue then
						-- Remove from staging (already tracked in Linear)
						vim.schedule(function()
							push_helpers.remove_from_staging(item.file, item.line)
						end)

						results.updated = results.updated + 1
						results.success = results.success + 1
					else
						error("Failed to update issue: " .. (update_err or "unknown error"))
					end
				else
					-- CREATE new issue
					local created_issue, create_err = api.create_linear_issue(item, api_key, team_id)
					if created_issue then
						-- Remove from staging (will appear in linear.md on next pull)
						vim.schedule(function()
							push_helpers.remove_from_staging(item.file, item.line)
						end)

						results.created = results.created + 1
						results.success = results.success + 1
					else
						error("Failed to create issue: " .. (create_err or "unknown error"))
					end
				end
			end)

			if not ok then
				results.failed = results.failed + 1
				-- Log error silently (could add debug logging here)
			end
		end

		-- Notify user of results
		vim.schedule(function()
			local msg_parts = {}
			table.insert(msg_parts, string.format("Linear push: %d synced", results.success))

			if results.created > 0 or results.updated > 0 then
				table.insert(msg_parts, string.format("(%d created, %d updated)", results.created, results.updated))
			end

			if results.skipped > 0 then
				local skip_details = {}
				if results.conflicts > 0 then
					table.insert(skip_details, string.format("%d conflicts", results.conflicts))
				end
				if results.deleted > 0 then
					table.insert(skip_details, string.format("%d deleted", results.deleted))
				end

				local skip_msg = string.format("%d skipped", results.skipped)
				if #skip_details > 0 then
					skip_msg = skip_msg .. " (" .. table.concat(skip_details, ", ") .. ")"
				end
				table.insert(msg_parts, skip_msg)
			end

			if results.failed > 0 then
				table.insert(msg_parts, string.format("%d failed", results.failed))
			end

			local msg = table.concat(msg_parts, ", ")
			local level = results.failed > 0 and vim.log.levels.WARN or vim.log.levels.INFO

			vim.notify(msg, level)
		end)
	end)
end

-- Alias for sync manager auto-push support
M.push = M.push_to_linear

return M
