-- Derived execution state: the reducer over the append-only log.
--
-- Nothing about execution is stored on the heading, so "what state is this task
-- in?" is answered by folding the log (`execution/log.lua`) in write order. The
-- last event mentioning a task is its current state; a task the log has never
-- mentioned has no state at all, which is what makes an empty log a valid start.
--
-- The STARTED slot is single-occupancy: at most one task is running at a time,
-- so the fold tracks it separately from the per-task states. Entering STARTED
-- claims the slot, and leaving it releases the slot only if that task still
-- holds it. A well-formed log pauses the running task before starting another;
-- if one does not, the most recent start wins the slot.

local log = require("org_markdown.execution.log")
local platform = require("org_markdown.platform")

local M = {}

-- The state that marks the one task currently being worked on.
M.STARTED = "STARTED"

--- Read every event in the log, oldest first. A log that does not exist yet is
--- an empty log, not an error; unparseable lines are skipped.
---@param path? string defaults to the configured log file
---@return table[] events
function M.read_events(path)
	local content = platform.fs.read_file(path or log.log_path())
	if not content then
		return {}
	end

	local events = {}
	for line in content:gmatch("[^\n]+") do
		local event = log.parse_event(line)
		if event then
			events[#events + 1] = event
		end
	end
	return events
end

--- Fold an ordered event stream into current state.
--- Each entry is `{ task, state, since, from }`, where `since` is the timestamp
--- of the transition that produced the state and `from` the state it replaced.
---@param events table[]
---@return { tasks: table<string, table>, started: string|nil } snapshot
function M.fold(events)
	local tasks = {}
	local started = nil

	for _, event in ipairs(events) do
		tasks[event.task] = {
			task = event.task,
			state = event.to,
			since = event.timestamp,
			from = event.from,
		}

		if event.to == M.STARTED then
			started = event.task
		elseif started == event.task then
			started = nil
		end
	end

	return { tasks = tasks, started = started }
end

--- Current state of every task, folded from the log on disk.
---@param path? string defaults to the configured log file
---@return { tasks: table<string, table>, started: string|nil } snapshot
function M.snapshot(path)
	return M.fold(M.read_events(path))
end

--- Current state of one task, or nil when the log has never mentioned it.
--- Pass a `snapshot` to answer for many tasks without re-reading the log.
---@param task string|table task id, or an item/headline carrying file + heading
---@param snapshot? table
---@return string|nil state, table|nil entry
function M.state_of(task, snapshot)
	local id = log.task_id(task)
	if not id then
		return nil
	end

	local entry = (snapshot or M.snapshot()).tasks[id]
	if not entry then
		return nil
	end
	return entry.state, entry
end

--- The single task currently STARTED, or nil when nothing is running.
---@param snapshot? table
---@return string|nil task, table|nil entry
function M.started_task(snapshot)
	snapshot = snapshot or M.snapshot()
	if not snapshot.started then
		return nil
	end
	return snapshot.started, snapshot.tasks[snapshot.started]
end

return M
