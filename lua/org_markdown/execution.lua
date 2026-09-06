-- Execution state machine for driving task progress from the heading under
-- the cursor.
-- Responsibilities:
-- - start(bufnr): transition the heading at the cursor to IN_PROGRESS,
--   auto-pausing whatever task was previously started (in this buffer or
--   another file) back to TODO
-- - pause(bufnr): transition the heading at the cursor back to TODO
-- - done(bufnr): transition the heading at the cursor to DONE
--
-- Uses the document tree model (utils/document.lua) for all mutations, the
-- same parse -> mutate -> serialize -> diff -> apply_to_buffer flow used by
-- utils/editing.lua, so property handling (e.g. COMPLETED_AT) stays
-- consistent with the rest of the plugin.

local document = require("org_markdown.utils.document")

local M = {}

-- Tracks the single task most recently moved to IN_PROGRESS via M.start, so
-- that starting a different task can auto-pause it back to TODO.
-- Shape: { file = string (buffer name / absolute path), text = string (heading text) } | nil
M._current = nil

--- Reset in-memory tracking of the currently started task.
--- Exposed primarily for test isolation between runs.
function M.reset()
	M._current = nil
end

--- Find the heading node under the cursor in the given buffer.
--- @param bufnr number
--- @return table|nil node, string[]|nil lines, table|nil root
local function heading_at_cursor(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local root = document.parse(lines)
	local node = document.find_node_at_line(root, cursor[1])

	if not node or node.type ~= "heading" or not node.parsed or not node.parsed.state then
		return nil, nil, nil
	end

	return node, lines, root
end

--- Serialize the (mutated) root and apply the minimal diff to the buffer.
--- @param bufnr number
--- @param lines string[] Original lines
--- @param root table Mutated document root
local function commit(bufnr, lines, root)
	local new_lines = document.serialize(root)
	local changes = document.diff(lines, new_lines)
	document.apply_to_buffer(bufnr, changes)
end

--- Pause a previously-started task by heading text, whether it lives in an
--- already-loaded buffer or only on disk. No-ops if the heading can't be
--- found or is no longer IN_PROGRESS.
--- @param filepath string
--- @param heading_text string
--- @return boolean paused
local function pause_task_in_file(filepath, heading_text)
	local bufnr = vim.fn.bufnr(filepath)

	if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		local root = document.parse(lines)
		local node = document.find_heading_by_text(root, heading_text)
		if not node or not node:has_state("IN_PROGRESS") then
			return false
		end
		node:set_state("TODO")
		commit(bufnr, lines, root)
		return true
	end

	local root = document.read_from_file(filepath)
	local node = document.find_heading_by_text(root, heading_text)
	if not node or not node:has_state("IN_PROGRESS") then
		return false
	end
	node:set_state("TODO")
	document.write_to_file(filepath, root)
	return true
end

--- Start (or resume) the task under the cursor: sets it to IN_PROGRESS and
--- auto-pauses whatever task was previously started elsewhere.
--- @param bufnr number|nil Buffer number (0/nil for current)
--- @return boolean success
function M.start(bufnr)
	bufnr = bufnr or 0
	local filepath = vim.api.nvim_buf_get_name(bufnr)

	local node, lines, root = heading_at_cursor(bufnr)
	if not node then
		return false
	end

	local target_text = node.parsed.text
	local is_already_current = M._current and M._current.file == filepath and M._current.text == target_text

	local paused
	if M._current and not is_already_current then
		if M._current.file == filepath then
			-- Previous task lives in this same buffer/document: pause it within
			-- the same parse so we only commit one set of buffer changes.
			local prev_node = document.find_heading_by_text(root, M._current.text)
			if prev_node and prev_node:has_state("IN_PROGRESS") then
				prev_node:set_state("TODO")
				paused = M._current
			end
		else
			-- Previous task lives elsewhere: pause it out-of-band first.
			if pause_task_in_file(M._current.file, M._current.text) then
				paused = M._current
			end
		end
	end

	node:set_state("IN_PROGRESS")
	commit(bufnr, lines, root)

	M._current = { file = filepath, text = target_text }

	if paused then
		vim.notify(
			string.format("OrgMarkdown: auto-paused '%s', started '%s'", paused.text, target_text),
			vim.log.levels.INFO
		)
	else
		vim.notify("OrgMarkdown: started '" .. target_text .. "'", vim.log.levels.INFO)
	end

	return true
end

--- Pause the task under the cursor (transition IN_PROGRESS -> TODO).
--- @param bufnr number|nil Buffer number (0/nil for current)
--- @return boolean success
function M.pause(bufnr)
	bufnr = bufnr or 0
	local filepath = vim.api.nvim_buf_get_name(bufnr)

	local node, lines, root = heading_at_cursor(bufnr)
	if not node or not node:has_state("IN_PROGRESS") then
		return false
	end

	node:set_state("TODO")
	commit(bufnr, lines, root)

	if M._current and M._current.file == filepath and M._current.text == node.parsed.text then
		M._current = nil
	end

	vim.notify("OrgMarkdown: paused '" .. node.parsed.text .. "'", vim.log.levels.INFO)

	return true
end

--- Mark the task under the cursor as DONE.
--- @param bufnr number|nil Buffer number (0/nil for current)
--- @return boolean success
function M.done(bufnr)
	bufnr = bufnr or 0
	local filepath = vim.api.nvim_buf_get_name(bufnr)

	local node, lines, root = heading_at_cursor(bufnr)
	if not node then
		return false
	end

	node:set_state("DONE")
	commit(bufnr, lines, root)

	if M._current and M._current.file == filepath and M._current.text == node.parsed.text then
		M._current = nil
	end

	vim.notify("OrgMarkdown: completed '" .. node.parsed.text .. "'", vim.log.levels.INFO)

	return true
end

return M
