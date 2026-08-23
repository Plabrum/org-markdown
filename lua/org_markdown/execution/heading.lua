-- Driving execution state from the heading the cursor is on.
--
-- The state machine speaks in task ids; a user speaks in "this task, the one I
-- am looking at". This layer is the translation: find the heading at or above
-- the cursor, turn it into the same `<file>::<heading text>` identity the agenda
-- and the log use, and hand it to `execution/machine.lua`.
--
-- Locating the heading and phrasing the outcome are buffer-free (`task_at`,
-- `summarize`), so the CLI can reuse them; only `start`/`pause`/`done` touch the
-- editor. The summary names the auto-paused task whenever starting one task
-- displaced another -- the single-STARTED invariant is silent otherwise, and a
-- user who cannot see their previous task stop has no reason to trust it.

local machine = require("org_markdown.execution.machine")
local parser = require("org_markdown.utils.parser")
local tree = require("org_markdown.utils.tree")

local M = {}

--- The readable half of a task id: the heading text, without the file it lives in.
---@param id string
---@return string
local function label(id)
	return id:match("::(.*)$") or id
end

--- The task owning `row`: the nearest heading on or above it. Body lines belong
--- to the heading above them, so a cursor anywhere inside a task's block works.
---@param lines string[]
---@param row number 1-based line number
---@param file? string
---@return table|nil task `{ file, text, line }`, string|nil err
function M.task_at(lines, row, file)
	for i = math.min(row, #lines), 1, -1 do
		if tree.is_heading(lines[i]) then
			local text = parser.parse_text(lines[i])
			if text == "" then
				return nil, "heading on line " .. i .. " has no text"
			end
			return { file = file, text = text, line = i }
		end
	end

	return nil, "no heading at or above the cursor"
end

--- Phrase what a transition did, naming the task auto-paused to make room for a
--- start so the displacement is visible rather than merely logged.
---@param events table[] as `machine.transition` returns them, oldest first
---@return string
function M.summarize(events)
	local moved = events[#events]
	local message = moved.to .. " " .. label(moved.task)

	local displaced = #events > 1 and events[#events - 1] or nil
	if displaced then
		message = message .. " (paused " .. label(displaced.task) .. ")"
	end

	return message
end

--- Move the task under the cursor to `target`, reporting the outcome.
---@param target string
function M.transition(target)
	local buf = vim.api.nvim_get_current_buf()
	local file = vim.api.nvim_buf_get_name(buf)
	local row = vim.api.nvim_win_get_cursor(0)[1]

	local task, err = M.task_at(vim.api.nvim_buf_get_lines(buf, 0, -1, false), row, file ~= "" and file or nil)
	if not task then
		vim.notify(err, vim.log.levels.WARN)
		return
	end

	local events, transition_err = machine.transition(task, target)
	if not events then
		vim.notify(transition_err, vim.log.levels.WARN)
		return
	end

	vim.notify(M.summarize(events), vim.log.levels.INFO)
end

--- Start the task under the cursor, pausing whatever was running.
function M.start()
	M.transition(machine.STARTED)
end

--- Pause the task under the cursor.
function M.pause()
	M.transition(machine.PAUSED)
end

--- Finish the task under the cursor.
function M.done()
	M.transition(machine.DONE)
end

return M
