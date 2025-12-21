-- =========================================================================
-- LINEAR API INTERACTIONS
-- =========================================================================
--
-- This module handles all Linear GraphQL API operations including:
-- - Query execution
-- - Fetching issues and cycles
-- - Creating and updating issues
-- - ID lookups with caching

local mapping = require("org_markdown.sync.plugins.linear.mapping")

local M = {}

-- Cache for ID lookups (lives for duration of push operation)
M.push_cache = {
	teams = {}, -- { ["IF"] = "uuid-123", ... }
	states = {}, -- { ["uuid-team-123"] = { ["Todo"] = "uuid-state-456", ... } }
	labels = {}, -- { ["backend"] = "uuid-label-789", ... }
	viewer_id = nil, -- "uuid-user-abc"
}

--- Reset push cache (call at start of each push operation)
function M.reset_push_cache()
	M.push_cache = {
		teams = {},
		states = {},
		labels = {},
		viewer_id = nil,
	}
end

-- =========================================================================
-- GRAPHQL EXECUTION
-- =========================================================================

--- Execute Linear GraphQL query
--- @param api_key string Linear API key
--- @param query string GraphQL query
--- @return table|nil, string|nil Response data, error message
function M.execute_graphql_query(api_key, query)
	local manager = require("org_markdown.sync.manager")

	-- Build curl command - normalize all whitespace and escape quotes
	local escaped_query = query
		:gsub("[\r\n\t]+", " ") -- Replace all newlines, returns, tabs with single space
		:gsub("%s+", " ") -- Collapse multiple spaces to single space
		:gsub("^%s+", "") -- Trim leading whitespace
		:gsub("%s+$", "") -- Trim trailing whitespace
		:gsub('"', '\\"') -- Escape quotes
	local json_payload = string.format('{"query":"%s"}', escaped_query)

	local cmd = string.format(
		"curl -s -X POST https://api.linear.app/graphql -H 'Content-Type: application/json' -H 'Authorization: %s' -d %s",
		api_key,
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

-- =========================================================================
-- FETCH OPERATIONS (PULL)
-- =========================================================================

--- Fetch assigned issues from Linear
--- @param api_key string Linear API key
--- @param team_ids table List of team keys (e.g., {"IF", "ENG"}) - empty = all teams
--- @return table|nil, string|nil Issues array, error message
function M.fetch_assigned_issues(api_key, team_ids)
	-- Build team filter (using team keys, not IDs)
	local team_filter = ""
	if #team_ids > 0 then
		local quoted_keys = {}
		for _, key in ipairs(team_ids) do
			table.insert(quoted_keys, '"' .. key .. '"')
		end
		team_filter = string.format("team: { key: { in: [%s] } },", table.concat(quoted_keys, ","))
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

	local data, err = M.execute_graphql_query(api_key, query)
	if not data then
		return nil, err
	end

	return data.issues and data.issues.nodes or {}, nil
end

--- Fetch active cycles from Linear
--- @param api_key string Linear API key
--- @param team_ids table List of team keys (e.g., {"IF", "ENG"}) - empty = all teams
--- @return table|nil, string|nil Cycles array, error message
function M.fetch_cycles(api_key, team_ids)
	-- Build team filter (using team keys, not IDs)
	local team_filter = ""
	if #team_ids > 0 then
		local quoted_keys = {}
		for _, key in ipairs(team_ids) do
			table.insert(quoted_keys, '"' .. key .. '"')
		end
		team_filter = string.format("team: { key: { in: [%s] } },", table.concat(quoted_keys, ","))
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

	local data, err = M.execute_graphql_query(api_key, query)
	if not data then
		return nil, err
	end

	return data.cycles and data.cycles.nodes or {}, nil
end

--- Fetch current Linear issue by identifier (for conflict detection)
--- @param api_key string Linear API key
--- @param identifier string Issue identifier (e.g., "IF-123")
--- @return table|nil issue Issue data with updatedAt
--- @return string|nil error Error message if fetch fails
function M.fetch_linear_issue(api_key, identifier)
	if not identifier then
		return nil, "Issue identifier required"
	end

	local query = string.format(
		[[
		query {
			issue(id: "%s") {
				id
				identifier
				title
				updatedAt
			}
		}
	]],
		identifier
	)

	local data, err = M.execute_graphql_query(api_key, query)
	if not data then
		return nil, err
	end

	if not data.issue then
		return nil, nil -- Issue doesn't exist (deleted)
	end

	return data.issue, nil
end

-- =========================================================================
-- ID LOOKUP WITH CACHING (PUSH)
-- =========================================================================

--- Get team ID by team key
--- @param api_key string Linear API key
--- @param team_key string Team key (e.g., "IF", "ENG")
--- @return string|nil team_id UUID
--- @return string|nil error Error message if lookup fails
function M.get_team_id(api_key, team_key)
	if not team_key or team_key == "" then
		return nil, "Team key required"
	end

	-- Check cache
	if M.push_cache.teams[team_key] then
		return M.push_cache.teams[team_key], nil
	end

	-- Query Linear API
	local query = string.format(
		[[
		query {
			teams(filter: { key: { eq: "%s" } }) {
				nodes {
					id
					key
					name
				}
			}
		}
	]],
		team_key
	)

	local data, err = M.execute_graphql_query(api_key, query)
	if not data then
		return nil, err
	end

	if not data.teams or not data.teams.nodes or #data.teams.nodes == 0 then
		return nil, string.format("Team not found: %s", team_key)
	end

	local team_id = data.teams.nodes[1].id
	M.push_cache.teams[team_key] = team_id
	return team_id, nil
end

--- Get state ID by name within a team
--- @param api_key string Linear API key
--- @param team_id string Team UUID
--- @param state_name string State name (e.g., "Todo", "In Progress")
--- @return string|nil state_id UUID
--- @return string|nil error Error message if lookup fails
function M.get_state_id(api_key, team_id, state_name)
	if not team_id or not state_name then
		return nil, nil -- Optional field, return nil silently
	end

	-- Initialize team cache if needed
	if not M.push_cache.states[team_id] then
		M.push_cache.states[team_id] = {}
	end

	-- Check cache
	if M.push_cache.states[team_id][state_name] then
		return M.push_cache.states[team_id][state_name], nil
	end

	-- Query Linear API for all states in team
	local query = string.format(
		[[
		query {
			team(id: "%s") {
				states {
					nodes {
						id
						name
					}
				}
			}
		}
	]],
		team_id
	)

	local data, err = M.execute_graphql_query(api_key, query)
	if not data or not data.team or not data.team.states then
		return nil, err
	end

	-- Cache all states for this team
	for _, state in ipairs(data.team.states.nodes) do
		M.push_cache.states[team_id][state.name] = state.id
	end

	-- Return requested state
	return M.push_cache.states[team_id][state_name], nil
end

--- Get label IDs by names (batch lookup)
--- @param api_key string Linear API key
--- @param label_names table Array of label names
--- @return table Array of label UUIDs (may be fewer than requested if some don't exist)
function M.get_label_ids(api_key, label_names)
	if not label_names or #label_names == 0 then
		return {}
	end

	local ids = {}
	local uncached_names = {}

	-- Check cache first
	for _, name in ipairs(label_names) do
		if M.push_cache.labels[name] then
			table.insert(ids, M.push_cache.labels[name])
		else
			table.insert(uncached_names, name)
		end
	end

	-- Fetch uncached labels
	if #uncached_names > 0 then
		local quoted_names = vim.tbl_map(function(n)
			return '"' .. n .. '"'
		end, uncached_names)

		local query = string.format(
			[[
			query {
				issueLabels(filter: { name: { in: [%s] } }) {
					nodes {
						id
						name
					}
				}
			}
		]],
			table.concat(quoted_names, ", ")
		)

		local data, err = M.execute_graphql_query(api_key, query)
		if data and data.issueLabels and data.issueLabels.nodes then
			for _, label in ipairs(data.issueLabels.nodes) do
				M.push_cache.labels[label.name] = label.id
				table.insert(ids, label.id)
			end
		end
	end

	return ids
end

--- Get viewer (current user) ID
--- @param api_key string Linear API key
--- @return string|nil viewer_id UUID
--- @return string|nil error Error message if lookup fails
function M.get_viewer_id(api_key)
	-- Check cache
	if M.push_cache.viewer_id then
		return M.push_cache.viewer_id, nil
	end

	-- Query Linear API
	local query = [[
		query {
			viewer {
				id
				name
			}
		}
	]]

	local data, err = M.execute_graphql_query(api_key, query)
	if not data or not data.viewer then
		return nil, err
	end

	M.push_cache.viewer_id = data.viewer.id
	return M.push_cache.viewer_id, nil
end

-- =========================================================================
-- MUTATION OPERATIONS (PUSH)
-- =========================================================================

--- Create a new Linear issue
--- @param item table Item data from markdown
--- @param api_key string Linear API key
--- @param team_id string Team UUID
--- @return table|nil issue Created issue with identifier and updatedAt
--- @return string|nil error Error message if creation fails
function M.create_linear_issue(item, api_key, team_id)
	if not item.title or item.title == "" then
		return nil, "Issue title required"
	end

	if not team_id then
		return nil, "Team ID required for creating issues"
	end

	-- Get viewer ID (assignee defaults to current user)
	local assignee_id, err = M.get_viewer_id(api_key)
	if not assignee_id then
		return nil, "Failed to get viewer ID: " .. (err or "unknown error")
	end

	-- Map status to Linear state ID
	local state_id = nil
	if item.status then
		local state_name = mapping.map_status_to_linear(item.status, item.reverse_status_mapping)
		if state_name then
			state_id, err = M.get_state_id(api_key, team_id, state_name)
		end
	end

	-- Map priority
	local priority = mapping.map_priority_to_linear(item.priority)

	-- Extract due date (tracked date)
	local due_date = nil
	if item.due_date then
		due_date = string.format("%04d-%02d-%02d", item.due_date.year, item.due_date.month, item.due_date.day)
	end

	-- Get label IDs from tags
	local label_ids = {}
	if item.tags and #item.tags > 0 then
		label_ids = M.get_label_ids(api_key, item.tags)
	end

	-- Build input object
	local input_parts = {}
	table.insert(input_parts, string.format('teamId: "%s"', team_id))
	table.insert(input_parts, string.format('title: "%s"', item.title:gsub('"', '\\"')))
	table.insert(input_parts, string.format('assigneeId: "%s"', assignee_id))

	if item.description then
		table.insert(input_parts, string.format('description: "%s"', item.description:gsub('"', '\\"'):gsub("\n", "\\n")))
	end

	if state_id then
		table.insert(input_parts, string.format('stateId: "%s"', state_id))
	end

	if priority and priority > 0 then
		table.insert(input_parts, string.format("priority: %d", priority))
	end

	if due_date then
		table.insert(input_parts, string.format('dueDate: "%s"', due_date))
	end

	if #label_ids > 0 then
		local quoted_ids = vim.tbl_map(function(id)
			return '"' .. id .. '"'
		end, label_ids)
		table.insert(input_parts, string.format("labelIds: [%s]", table.concat(quoted_ids, ", ")))
	end

	-- Build mutation
	local mutation = string.format(
		[[
		mutation {
			issueCreate(input: { %s }) {
				success
				issue {
					id
					identifier
					title
					updatedAt
				}
			}
		}
	]],
		table.concat(input_parts, ", ")
	)

	local data, err = M.execute_graphql_query(api_key, mutation)
	if not data then
		return nil, err
	end

	if not data.issueCreate or not data.issueCreate.success then
		return nil, "Failed to create issue"
	end

	return data.issueCreate.issue, nil
end

--- Update an existing Linear issue
--- @param item table Item data from markdown
--- @param api_key string Linear API key
--- @param team_id string Team UUID
--- @return table|nil issue Updated issue with identifier and updatedAt
--- @return string|nil error Error message if update fails
function M.update_linear_issue(item, api_key, team_id)
	if not item.linear_id then
		return nil, "Linear ID required for updates"
	end

	-- Map status to Linear state ID
	local state_id = nil
	if item.status then
		local state_name = mapping.map_status_to_linear(item.status, item.reverse_status_mapping)
		if state_name and team_id then
			local err
			state_id, err = M.get_state_id(api_key, team_id, state_name)
		end
	end

	-- Map priority
	local priority = mapping.map_priority_to_linear(item.priority)

	-- Extract due date
	local due_date = nil
	if item.due_date then
		due_date = string.format("%04d-%02d-%02d", item.due_date.year, item.due_date.month, item.due_date.day)
	end

	-- Get label IDs from tags
	local label_ids = {}
	if item.tags and #item.tags > 0 then
		label_ids = M.get_label_ids(api_key, item.tags)
	end

	-- Build input object (only include fields that have values)
	local input_parts = {}

	if item.title and item.title ~= "" then
		table.insert(input_parts, string.format('title: "%s"', item.title:gsub('"', '\\"')))
	end

	if item.description then
		table.insert(input_parts, string.format('description: "%s"', item.description:gsub('"', '\\"'):gsub("\n", "\\n")))
	end

	if state_id then
		table.insert(input_parts, string.format('stateId: "%s"', state_id))
	end

	if priority and priority > 0 then
		table.insert(input_parts, string.format("priority: %d", priority))
	end

	if due_date then
		table.insert(input_parts, string.format('dueDate: "%s"', due_date))
	end

	if #label_ids > 0 then
		local quoted_ids = vim.tbl_map(function(id)
			return '"' .. id .. '"'
		end, label_ids)
		table.insert(input_parts, string.format("labelIds: [%s]", table.concat(quoted_ids, ", ")))
	end

	-- Build mutation
	local mutation = string.format(
		[[
		mutation {
			issueUpdate(id: "%s", input: { %s }) {
				success
				issue {
					id
					identifier
					updatedAt
				}
			}
		}
	]],
		item.linear_id,
		table.concat(input_parts, ", ")
	)

	local data, err = M.execute_graphql_query(api_key, mutation)
	if not data then
		return nil, err
	end

	if not data.issueUpdate or not data.issueUpdate.success then
		return nil, "Failed to update issue"
	end

	return data.issueUpdate.issue, nil
end

return M
