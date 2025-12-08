local config = require("org_markdown.config")
local secrets = require("org_markdown.utils.secrets")

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
		team_ids = {}, -- Empty = all teams
		heading_level = 2,
		auto_sync = false,
		auto_sync_interval = 3600, -- 1 hour
	},

	supports_auto_sync = true,
	command_name = "MarkdownSyncLinear",
	keymap = "<leader>ol",
}

-- =========================================================================
-- STATE MAPPING
-- =========================================================================

--- Map Linear state to org-markdown status
--- @param state_name string Linear state name
--- @return string|nil Org-markdown status
local function map_linear_state(state_name)
	if not state_name then
		return nil
	end

	local lower_state = state_name:lower()

	-- Map common Linear states to org-markdown states
	if lower_state:match("backlog") or lower_state:match("todo") or lower_state:match("triage") then
		return "TODO"
	elseif lower_state:match("in progress") or lower_state:match("started") or lower_state:match("in development") then
		return "IN_PROGRESS"
	elseif lower_state:match("done") or lower_state:match("completed") then
		return "DONE"
	elseif lower_state:match("cancel") then
		return "CANCELLED"
	else
		-- Default to TODO for unknown states
		return "TODO"
	end
end

--- Map Linear priority to org-markdown priority
--- @param priority number|nil Linear priority (0-4)
--- @return string|nil Priority letter (A-C)
local function map_priority(priority)
	if not priority then
		return nil
	end

	-- Linear: 0 = No priority, 1 = Urgent, 2 = High, 3 = Medium, 4 = Low
	if priority == 1 then
		return "A"
	elseif priority == 2 then
		return "B"
	elseif priority == 3 or priority == 4 then
		return "C"
	else
		return nil
	end
end

-- =========================================================================
-- DATE PARSING
-- =========================================================================

--- Parse Linear date string (YYYY-MM-DD) to date table
--- @param date_str string|nil ISO date string
--- @return table|nil Date table {year, month, day}
local function parse_linear_date(date_str)
	if not date_str then
		return nil
	end

	local year, month, day = date_str:match("(%d%d%d%d)-(%d%d)-(%d%d)")
	if year then
		return {
			year = tonumber(year),
			month = tonumber(month),
			day = tonumber(day),
		}
	end

	return nil
end

-- =========================================================================
-- LINEAR API
-- =========================================================================

--- Execute Linear GraphQL query
--- @param api_key string Linear API key
--- @param query string GraphQL query
--- @return table|nil, string|nil Response data, error message
local function execute_graphql_query(api_key, query)
	local manager = require("org_markdown.sync.manager")

	-- Build curl command
	local escaped_query = query:gsub('"', '\\"'):gsub("\n", "")
	local json_payload = string.format('{"query":"%s"}', escaped_query)

	local cmd = string.format(
		'curl -s -X POST https://api.linear.app/graphql -H "Content-Type: application/json" -H "Authorization: %s" -d %s',
		vim.fn.shellescape(api_key),
		vim.fn.shellescape(json_payload)
	)

	-- Execute async (auto-awaits in coroutine context)
	local output_lines, err = manager.execute_command(cmd)

	if not output_lines then
		return nil, "Linear API request failed: " .. (err or "Unknown error")
	end

	-- Join lines into single string for JSON parsing
	local output = table.concat(output_lines, "\n")

	-- Parse JSON response
	local ok, response = pcall(vim.fn.json_decode, output)
	if not ok then
		return nil, "Failed to parse Linear API response: " .. tostring(response)
	end

	if response.errors then
		local error_msgs = {}
		for _, err in ipairs(response.errors) do
			table.insert(error_msgs, err.message or tostring(err))
		end
		return nil, "Linear API error: " .. table.concat(error_msgs, ", ")
	end

	return response.data, nil
end

--- Fetch assigned issues from Linear
--- @param api_key string Linear API key
--- @param team_ids table List of team IDs (empty = all teams)
--- @return table|nil, string|nil Issues array, error message
local function fetch_assigned_issues(api_key, team_ids)
	-- Build team filter
	local team_filter = ""
	if #team_ids > 0 then
		local quoted_ids = {}
		for _, id in ipairs(team_ids) do
			table.insert(quoted_ids, '"' .. id .. '"')
		end
		team_filter = string.format("team: { id: { in: [%s] } },", table.concat(quoted_ids, ","))
	end

	local query = string.format(
		[[
		query {
			issues(filter: { assignee: { isMe: { eq: true } }, %s }) {
				nodes {
					id
					identifier
					title
					description
					priority
					dueDate
					url
					state { name }
					assignee { name }
					team { key name }
					project { name }
				}
			}
		}
	]],
		team_filter
	)

	local data, err = execute_graphql_query(api_key, query)
	if not data then
		return nil, err
	end

	return data.issues and data.issues.nodes or {}, nil
end

--- Fetch active cycles from Linear
--- @param api_key string Linear API key
--- @param team_ids table List of team IDs (empty = all teams)
--- @return table|nil, string|nil Cycles array, error message
local function fetch_cycles(api_key, team_ids)
	-- Build team filter
	local team_filter = ""
	if #team_ids > 0 then
		local quoted_ids = {}
		for _, id in ipairs(team_ids) do
			table.insert(quoted_ids, '"' .. id .. '"')
		end
		team_filter = string.format("team: { id: { in: [%s] } },", table.concat(quoted_ids, ","))
	end

	local query = string.format(
		[[
		query {
			cycles(filter: { %s isActive: { eq: true } }) {
				nodes {
					id
					number
					name
					startsAt
					endsAt
					team { key name }
				}
			}
		}
	]],
		team_filter
	)

	local data, err = execute_graphql_query(api_key, query)
	if not data then
		return nil, err
	end

	return data.cycles and data.cycles.nodes or {}, nil
end

-- =========================================================================
-- ITEM CONVERSION
-- =========================================================================

--- Convert Linear issue to item format
--- @param issue table Linear issue object
--- @return table Item
local function issue_to_item(issue)
	-- Build body with metadata and description
	local body_parts = {}

	-- Add metadata section
	local metadata = {}
	if issue.assignee and issue.assignee.name then
		table.insert(metadata, "**Assignee:** " .. issue.assignee.name)
	end
	if issue.project and issue.project.name then
		table.insert(metadata, "**Project:** " .. issue.project.name)
	end
	if issue.state and issue.state.name then
		table.insert(metadata, "**State:** " .. issue.state.name)
	end
	if issue.url then
		table.insert(metadata, "**URL:** " .. issue.url)
	end
	if issue.identifier then
		table.insert(metadata, "**ID:** `" .. issue.identifier .. "`")
	end

	if #metadata > 0 then
		table.insert(body_parts, table.concat(metadata, "  \n"))
	end

	-- Add description if present
	if issue.description and issue.description ~= "" then
		if #body_parts > 0 then
			table.insert(body_parts, "")
		end
		table.insert(body_parts, issue.description)
	end

	local item = {
		title = issue.title,
		status = map_linear_state(issue.state and issue.state.name),
		priority = map_priority(issue.priority),
		due_date = parse_linear_date(issue.dueDate),
		tags = {},
		body = #body_parts > 0 and table.concat(body_parts, "\n") or nil,
	}

	-- Add team tag
	if issue.team then
		table.insert(item.tags, issue.team.key)
	end

	-- Add project tag if present
	if issue.project then
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
	if cycle.team and cycle.team.name then
		table.insert(metadata, "**Team:** " .. cycle.team.name)
	end
	if cycle.id then
		table.insert(metadata, "**ID:** `" .. cycle.id .. "`")
	end

	local item = {
		title = string.format("[%s] %s", cycle.team.key, cycle.name),
		start_date = parse_linear_date(cycle.startsAt and cycle.startsAt:match("^[^T]+")),
		end_date = parse_linear_date(cycle.endsAt and cycle.endsAt:match("^[^T]+")),
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
		local issues, err = fetch_assigned_issues(api_key, plugin_config.team_ids or {})
		if not issues then
			return nil, err
		end

		for _, issue in ipairs(issues) do
			table.insert(items, issue_to_item(issue))
		end
	end

	-- Fetch cycles
	if plugin_config.include_cycles then
		local cycles, err = fetch_cycles(api_key, plugin_config.team_ids or {})
		if not cycles then
			return nil, err
		end

		for _, cycle in ipairs(cycles) do
			table.insert(items, cycle_to_item(cycle))
		end
	end

	return {
		items = items,
		stats = {
			count = #items,
			source = "Linear",
		},
	}
end

return M
