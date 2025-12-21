-- =========================================================================
-- LINEAR STATE AND PRIORITY MAPPINGS
-- =========================================================================
--
-- This module handles bidirectional mapping between Linear states/priorities
-- and org-markdown statuses/priorities.

local M = {}

--- Map Linear state to org-markdown status using configured mappings
--- @param state_name string Linear state name
--- @param status_mapping table Pattern-based status mapping from config
--- @return string|nil Org-markdown status
function M.map_linear_state(state_name, status_mapping)
	if not state_name then
		return nil
	end

	local lower_state = state_name:lower()

	-- Try to match against configured patterns
	if status_mapping then
		for _, mapping in ipairs(status_mapping) do
			if lower_state:match(mapping.pattern:lower()) then
				return mapping.status
			end
		end
	end

	-- Default to TODO if no mapping found
	return "TODO"
end

--- Map org-markdown status to Linear state name (for push functionality)
--- @param status string Org-markdown status
--- @param reverse_status_mapping table Reverse mapping from config
--- @return string|nil Linear state name
function M.map_status_to_linear(status, reverse_status_mapping)
	if not status then
		return nil
	end

	if reverse_status_mapping then
		return reverse_status_mapping[status]
	end

	return nil
end

--- Map Linear priority to org-markdown priority
--- @param priority number|nil Linear priority (0-4)
--- @return string|nil Priority letter (A-C)
function M.map_priority(priority)
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

--- Map org-markdown priority letter to Linear priority number
--- @param priority string Priority letter (A, B, C)
--- @return number|nil Linear priority (1=Urgent, 2=High, 3=Medium, 4=Low, 0=None)
function M.map_priority_to_linear(priority)
	if not priority then
		return 0 -- No priority
	end

	local priority_map = {
		A = 1, -- Urgent
		B = 2, -- High
		C = 3, -- Medium
	}

	return priority_map[priority] or 0
end

--- Parse Linear date string (YYYY-MM-DD) to date table
--- @param date_str string|nil ISO date string
--- @return table|nil Date table {year, month, day}
function M.parse_linear_date(date_str)
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

--- Check if value is nil or vim.NIL (JSON null)
--- @param value any Value to check
--- @return boolean True if nil or vim.NIL
function M.is_null(value)
	return value == nil or value == vim.NIL
end

return M
