-- Append-only execution log: the sole record of task state transitions.
--
-- STORAGE LOCUS: one central log file (`config.execution.log_file`), not a
-- per-task section under the heading. A heading-local log would mean rewriting
-- a user's markdown on every transition, which is exactly the "never
-- overwritten" property the engine depends on; a single file also gives the
-- reducer one ordered stream to fold, so the globally-STARTED task is readable
-- without scanning every file. The log is plain text, one event per line, and
-- carries a `.log` extension so agenda/refile scans (which only look at `.md`
-- and `.markdown`) never pick it up.
--
-- RECORD FORMAT: four tab-separated fields, terminated by a newline.
--
--   <ISO-8601 UTC timestamp>\t<from state>\t<to state>\t<task id>
--   2026-08-23T18:04:11Z	TODO	STARTED	/home/me/org/work.md::Write the report
--
-- The task id is `<file>::<heading text>` (heading text alone when the task
-- carries no file). `from` is `-` for a task with no prior state. Tabs,
-- newlines and backslashes inside a field are backslash-escaped so an event is
-- always exactly one line and always round-trips.

local compat = require("org_markdown.compat.vim")
local platform = require("org_markdown.platform")

local M = {}

-- Placeholder for an absent `from` state (the first event of a task).
local NO_STATE = "-"

local ESCAPES = { ["\\"] = "\\\\", ["\t"] = "\\t", ["\n"] = "\\n", ["\r"] = "\\r" }
local UNESCAPES = { ["\\"] = "\\", t = "\t", n = "\n", r = "\r" }

--- Escape the separator and line-break characters inside a single field.
---@param value string
---@return string
local function escape_field(value)
	return (value:gsub("[\\\t\n\r]", ESCAPES))
end

--- Reverse `escape_field`. Unknown escapes keep their literal character.
---@param value string
---@return string
local function unescape_field(value)
	return (value:gsub("\\(.)", function(c)
		return UNESCAPES[c] or c
	end))
end

--- Absolute path of the event log.
---@return string
function M.log_path()
	local config = require("org_markdown.config")
	return platform.path.expand(config.execution.log_file)
end

--- Current time as an ISO-8601 UTC timestamp.
---@return string
function M.now()
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

--- Build the stable identity of a task.
--- Accepts an already-built id string, or an item/headline table carrying a
--- `file` and its heading text (`title` from agenda items, `text` from the parser).
---@param task string|table
---@return string|nil id, string|nil err
function M.task_id(task)
	if type(task) == "string" then
		local id = compat.trim(task)
		if id == "" then
			return nil, "task id is empty"
		end
		return id
	end

	if type(task) ~= "table" then
		return nil, "task must be a string id or a table"
	end

	local text = compat.trim(task.title or task.text or "")
	if text == "" then
		return nil, "task has no heading text"
	end

	if task.file and task.file ~= "" then
		return task.file .. "::" .. text
	end
	return text
end

--- Render an event as its single log line (no trailing newline).
---@param event { timestamp: string, from: string|nil, to: string, task: string }
---@return string
function M.format_event(event)
	return table.concat({
		escape_field(event.timestamp),
		escape_field(event.from or NO_STATE),
		escape_field(event.to),
		escape_field(event.task),
	}, "\t")
end

--- Parse one log line back into an event. Blank lines and malformed lines
--- yield nil so a partially written or hand-edited log stays readable.
---@param line string
---@return table|nil event
function M.parse_event(line)
	if not line then
		return nil
	end

	local timestamp, from, to, task = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
	if not timestamp or timestamp == "" or to == "" or task == "" then
		return nil
	end

	from = unescape_field(from)
	return {
		timestamp = unescape_field(timestamp),
		from = from ~= NO_STATE and from or nil,
		to = unescape_field(to),
		task = unescape_field(task),
	}
end

--- Build the event a transition records, without writing it.
---@param task string|table
---@param transition { from: string|nil, to: string, at: string|nil }
---@return table|nil event, string|nil err
local function build_event(task, transition)
	local id, err = M.task_id(task)
	if not id then
		return nil, err
	end

	if type(transition) ~= "table" or transition.to == nil or transition.to == "" then
		return nil, "transition requires a `to` state"
	end

	return {
		timestamp = transition.at or M.now(),
		from = transition.from,
		to = transition.to,
		task = id,
	}
end

--- Append one transition to the log. Existing entries are never rewritten.
--- `transition` is `{ from = <state|nil>, to = <state>, at = <ISO timestamp|nil> }`;
--- `at` defaults to now and exists so callers (and tests) can supply a fixed time.
---@param task string|table
---@param transition { from: string|nil, to: string, at: string|nil }
---@return table|nil event, string|nil err
function M.append_event(task, transition)
	local events, err = M.append_events({ { task = task, transition = transition } })
	if not events then
		return nil, err
	end
	return events[1]
end

--- Append several transitions as a single write, so a run of events that only
--- makes sense together (auto-pausing one task to start another) can never land
--- half-written. Each entry is `{ task = <task>, transition = <transition> }`.
---@param entries { task: string|table, transition: table }[]
---@return table[]|nil events, string|nil err
function M.append_events(entries)
	local events, lines = {}, {}
	for _, entry in ipairs(entries) do
		local event, err = build_event(entry.task, entry.transition)
		if not event then
			return nil, err
		end
		events[#events + 1] = event
		lines[#lines + 1] = M.format_event(event) .. "\n"
	end

	if #lines == 0 then
		return events
	end

	local path = M.log_path()
	local ok, write_err = platform.fs.append_file(path, table.concat(lines))
	if not ok then
		return nil, "could not append to " .. path .. ": " .. (write_err or "unknown error")
	end

	return events
end

return M
