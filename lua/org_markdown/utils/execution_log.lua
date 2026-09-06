-- Execution log reader + reducer
--
-- Execution state (STARTED / PAUSED / DONE) is derived, not stored in heading
-- text. This module reads an append-only log of execution events and folds
-- them into a per-task state map plus the single currently-active task.
--
-- Log format: one event per line, oldest first:
--   <ISO8601 timestamp> <VERB> <file>:<line>
-- Verbs: START, PAUSE, DONE
--
-- Task identity is `file:line`, matching agenda.lua's get_item_id().
--
-- Reducer rules:
--   START <id> -> id becomes STARTED and the sole active task.
--                 Any previously active task is demoted to PAUSED (this is
--                 what guarantees "single active task" as an invariant of
--                 the fold, not something callers have to enforce).
--   PAUSE <id> -> id becomes PAUSED. If it was active, active is cleared.
--   DONE  <id> -> id becomes DONE. Active is cleared if it was active.
--
-- Malformed lines are skipped. A missing log file yields an empty log.

local M = {}

M.VERBS = { START = true, PAUSE = true, DONE = true }

M.VERB_TO_STATE = {
	START = "STARTED",
	PAUSE = "PAUSED",
	DONE = "DONE",
}

--- Parse a single log line into an event, or nil if malformed.
--- @param line string
--- @return table|nil { timestamp = string, verb = string, id = string }
function M.parse_line(line)
	if not line or vim.trim(line) == "" then
		return nil
	end

	local timestamp, verb, id = line:match("^(%S+)%s+(%S+)%s+(%S+)%s*$")
	if not timestamp or not verb or not id then
		return nil
	end

	if not M.VERBS[verb] then
		return nil
	end

	return { timestamp = timestamp, verb = verb, id = id }
end

--- Read and parse all events from a log file, in file order.
--- Missing file returns an empty list. Malformed lines are skipped.
--- @param path string Already-expanded filesystem path
--- @return table[] events
function M.read_events(path)
	local events = {}

	local f = io.open(path, "r")
	if not f then
		return events
	end

	for line in f:lines() do
		local event = M.parse_line(line)
		if event then
			table.insert(events, event)
		end
	end
	f:close()

	return events
end

--- Fold a list of events (oldest first) into per-task execution state.
--- @param events table[] Array of { timestamp, verb, id }
--- @return table { states = { [id] = "STARTED"|"PAUSED"|"DONE" }, active = id|nil }
function M.reduce(events)
	local states = {}
	local active = nil

	for _, event in ipairs(events or {}) do
		if event.verb == "START" then
			if active and active ~= event.id then
				states[active] = "PAUSED"
			end
			states[event.id] = "STARTED"
			active = event.id
		elseif event.verb == "PAUSE" then
			states[event.id] = "PAUSED"
			if active == event.id then
				active = nil
			end
		elseif event.verb == "DONE" then
			states[event.id] = "DONE"
			if active == event.id then
				active = nil
			end
		end
	end

	return { states = states, active = active }
end

--- Convenience: read the log at `path` and reduce it in one call.
--- @param path string Already-expanded filesystem path
--- @return table { states = table, active = id|nil }
function M.derive(path)
	return M.reduce(M.read_events(path))
end

return M
