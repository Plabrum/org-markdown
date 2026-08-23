-- The execution state machine: the only sanctioned way to write to the log.
--
-- `execution/log.lua` will append any transition it is handed and
-- `execution/state.lua` will fold whatever it finds; neither judges. This layer
-- sits over both and decides what a task is allowed to do next, so an illegal
-- move is refused before it reaches the log rather than fixed up afterwards.
--
-- LEGAL MOVES: TODO -> STARTED -> PAUSED -> DONE, plus PAUSED -> STARTED to
-- resume and STARTED -> DONE to finish without pausing first. DONE is terminal.
-- A task the log has never mentioned is implicitly TODO, which is what lets a
-- fresh heading be started without seeding it with an event first.
--
-- SINGLE-STARTED INVARIANT: at most one task is STARTED. Starting a task while
-- another is running auto-pauses the running one, and both events are appended
-- in a single write so the log can never be caught with two tasks started or
-- with a pause that lost its start.

local log = require("org_markdown.execution.log")
local state = require("org_markdown.execution.state")

local M = {}

M.TODO = "TODO"
M.STARTED = state.STARTED
M.PAUSED = "PAUSED"
M.DONE = "DONE"

-- Which states each state may move to. Absence from a row means "not allowed".
M.TRANSITIONS = {
	[M.TODO] = { [M.STARTED] = true },
	[M.STARTED] = { [M.PAUSED] = true, [M.DONE] = true },
	[M.PAUSED] = { [M.STARTED] = true, [M.DONE] = true },
	[M.DONE] = {},
}

--- Whether a task in `from` may move to `to`. An unmentioned task (`from` nil)
--- counts as TODO.
---@param from string|nil
---@param to string
---@return boolean
function M.can(from, to)
	local row = M.TRANSITIONS[from or M.TODO]
	return row ~= nil and row[to] == true
end

--- Move a task to `target`, refusing illegal moves and keeping the STARTED slot
--- single-occupancy. Returns the events that were appended, oldest first: the
--- auto-pause of the previously running task comes before the start it made room
--- for. `opts` may carry `at` (a fixed ISO timestamp) and `snapshot` (state
--- already folded by the caller).
---@param task string|table task id, or an item/headline carrying file + heading
---@param target string
---@param opts? { at: string|nil, snapshot: table|nil }
---@return table[]|nil events, string|nil err
function M.transition(task, target, opts)
	opts = opts or {}

	local id, err = log.task_id(task)
	if not id then
		return nil, err
	end

	if M.TRANSITIONS[target] == nil then
		return nil, "unknown execution state `" .. tostring(target) .. "`"
	end

	local snapshot = opts.snapshot or state.snapshot()
	local current = state.state_of(id, snapshot)
	if not M.can(current, target) then
		return nil, string.format("cannot move `%s` from %s to %s", id, current or M.TODO, target)
	end

	local at = opts.at or log.now()
	local entries = {}

	if target == M.STARTED then
		local running = state.started_task(snapshot)
		if running and running ~= id then
			entries[#entries + 1] = { task = running, transition = { from = M.STARTED, to = M.PAUSED, at = at } }
		end
	end

	entries[#entries + 1] = { task = id, transition = { from = current, to = target, at = at } }

	return log.append_events(entries)
end

return M
