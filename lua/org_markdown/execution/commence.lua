-- Commencing a focus block: choosing the work it is for.
--
-- A focus block (`execution/focus.lua`) is time reserved before the work is
-- named. Commencement is the moment it stops being empty: the user is shown the
-- tasks that could be started right now, picks one, and that task is driven to
-- STARTED. Starting a task inside the block is the binding -- the block is not
-- rewritten to name it, because the log already says what was running and when,
-- and a second record of the same fact could only disagree with the first.
--
-- WHAT "COULD BE STARTED" MEANS: a task in scope that is not finished, not
-- blocked, and not already done in the system it came from -- narrowed to the
-- highest priority tier that has anything in it. The narrowing is the point: a
-- block is a single stretch of work, and offering the C-priority tasks
-- alongside the A-priority ones invites picking the wrong one.
--
-- Two of those exclusions are not fully knowable yet, so each is a single named
-- predicate (`is_blocked`, `is_externally_done`) rather than an inline test --
-- the seam is where the answer lands when there is one to give.
--
-- Everything but `begin` is vim-free, so the CLI can list the same eligible
-- tasks and commence the same way.

local complete = require("org_markdown.sync.complete")
local datetime = require("org_markdown.utils.datetime")
local focus = require("org_markdown.execution.focus")
local heading = require("org_markdown.execution.heading")
local machine = require("org_markdown.execution.machine")
local picker = require("org_markdown.utils.picker")
local pipeline = require("org_markdown.agenda.pipeline")

local M = {}

-- The states in which a task is waiting on something else. These are what the
-- trackers map their blocked and waiting columns onto.
M.BLOCKED_STATES = { BLOCKED = true, WAITING = true }

-- Priority tiers, best first. A task with no priority is its own, lowest tier.
M.PRIORITY_RANK = { A = 1, B = 2, C = 3 }
local NO_PRIORITY = 99

--- Whether a task is waiting on something else and so cannot be picked up.
---
--- SEAM: the state says so explicitly today. Blocking expressed as a link to
--- the task being waited on -- "this cannot start until that is done" -- has
--- nowhere to be read from yet, since nothing writes a dependency link; it
--- belongs here when it does.
---@param item table agenda item
---@return boolean
function M.is_blocked(item)
	return M.BLOCKED_STATES[item.state] == true
end

--- Whether the source this task was promoted from has since reported it done.
---
--- SEAM: a source's completion reaches the heading through the sync sweep
--- (`sync/complete.lua`), which marks it DONE in place -- so an
--- externally-completed task whose sweep has run is already excluded as
--- finished. Asking the source directly, for a task whose sweep has not run
--- yet, needs a live query of that source; it belongs here when there is one.
---@param item table agenda item
---@return boolean
function M.is_externally_done(item)
	return false
end

--- Whether a task is finished: by the state on the heading, or by the execution
--- log having taken it to DONE.
---@param item table agenda item
---@return boolean
function M.is_complete(item)
	return complete.DONE_STATES[item.state] == true or item.execution == machine.DONE
end

--- Whether a task could be started right now, before priority is considered.
---@param item table agenda item
---@return boolean
function M.is_eligible(item)
	if not item.state then
		return false
	end
	return not M.is_complete(item) and not M.is_blocked(item) and not M.is_externally_done(item)
end

--- Every task in scope, flattened out of the agenda's hierarchy and annotated
--- with its execution state -- a sub-task is work like any other, and the log is
--- read once for the lot.
---@param opts? table `{ file_patterns = string[], snapshot = table }`
---@return table[] tasks agenda items
function M.tasks(opts)
	opts = opts or {}
	local items = pipeline.apply_execution_state(pipeline.scan_files(opts.file_patterns).tasks, opts.snapshot)
	local tasks = {}

	local function collect(item)
		if item.state then
			tasks[#tasks + 1] = item
		end
		for _, child in ipairs(item.children or {}) do
			collect(child)
		end
	end

	for _, item in ipairs(items) do
		collect(item)
	end

	return tasks
end

---@param item table
---@return number
local function rank(item)
	return M.PRIORITY_RANK[item.priority] or NO_PRIORITY
end

--- The best-ranked tier that has anything in it, earliest date first. Which
--- tier that is depends on what is available: with no A-priority task open, the
--- B-priority ones are the top tier.
---@param tasks table[]
---@return table[]
function M.top_tier(tasks)
	local best = NO_PRIORITY
	for _, task in ipairs(tasks) do
		best = math.min(best, rank(task))
	end

	local tier = {}
	for _, task in ipairs(tasks) do
		if rank(task) == best then
			tier[#tier + 1] = task
		end
	end

	table.sort(tier, function(a, b)
		local date_a, date_b = a.date or "9999-99-99", b.date or "9999-99-99"
		if date_a ~= date_b then
			return date_a < date_b
		end
		return (a.title or "") < (b.title or "")
	end)

	return tier
end

--- The tasks to offer when a block commences.
---@param opts? table as `M.tasks` takes them
---@return table[] tasks agenda items
function M.eligible(opts)
	local eligible = {}
	for _, task in ipairs(M.tasks(opts)) do
		if M.is_eligible(task) then
			eligible[#eligible + 1] = task
		end
	end
	return M.top_tier(eligible)
end

--- The focus block covering a moment, or nil when none does. A block with no
--- span covers its whole day, and one with a start but no end runs to the end
--- of it.
---@param when? table `{ date = <ISO date>, time = "HH:MM" }`, defaulting to now
---@return table|nil block agenda item
function M.block_at(when)
	when = when or {}
	local date = when.date or datetime.to_iso_string(datetime.today(true))
	local time = when.time or os.date("%H:%M")

	for _, block in ipairs(focus.blocks({ date = date })) do
		if time >= (block.start_time or "00:00") and time <= (block.end_time or "23:59") then
			return block
		end
	end
end

--- Bind a task to the block that is commencing by starting it. Whatever else
--- was running is auto-paused, as it is for any other start.
---@param task table|string agenda item, or a task id
---@param opts? table passed through to `machine.transition`
---@return table[]|nil events, string|nil err
function M.commence(task, opts)
	return machine.transition(task, machine.STARTED, opts)
end

--- How a block reads in a message: its title and the span it runs for.
---@param block table
---@return string
local function block_label(block)
	local span = block.start_time
	if span and block.end_time then
		span = span .. "-" .. block.end_time
	end
	return span and (block.title .. " " .. span) or block.title
end

--- Commence the current focus block from the editor: pick one of the eligible
--- tasks and start it.
function M.begin()
	local block = M.block_at()
	local tasks = M.eligible()

	if #tasks == 0 then
		vim.notify("No eligible tasks to start", vim.log.levels.WARN)
		return
	end

	picker.pick(tasks, {
		prompt = block and ("Start in " .. block_label(block) .. ":") or "Start:",
		kind = "generic",
		format_item = function(item)
			local priority = item.priority and ("[#" .. item.priority .. "] ") or ""
			return {
				{ priority .. item.title, "Directory" },
				{ "  (" .. item.source .. ")", "Comment" },
			}
		end,
		on_confirm = function(item)
			local events, err = M.commence(item)
			if not events then
				vim.notify(err, vim.log.levels.WARN)
				return
			end

			local message = heading.summarize(events)
			if block then
				message = message .. " in " .. block_label(block)
			end
			vim.notify(message, vim.log.levels.INFO)
		end,
	})
end

return M
