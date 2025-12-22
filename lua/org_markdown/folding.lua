local M = {}
local tree = require("org_markdown.utils.tree")

-- Helper: Check if a line is a heading
-- @param lnum number: Line number (1-indexed)
-- @param bufnr number|nil: Buffer number (defaults to current buffer)
-- @return boolean: true if line is a heading
function M.is_heading_line(lnum, bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)
	if #lines == 0 then
		return false
	end
	return tree.is_heading(lines[1])
end

-- Helper: Get heading level from a line
-- @param line string: The line text
-- @return number|nil: Number of # characters, or nil if not a heading
function M.get_heading_level(line)
	return tree.get_level(line)
end

-- Fold expression: Calculate fold level for a line
-- This is called by Neovim for every line when foldmethod='expr'
-- Must be fast - no file I/O or expensive operations
-- @param lnum number: Line number (1-indexed)
-- @return string: Fold level indicator (">N" for headings, "=" for content)
function M.get_fold_level(lnum)
	local line = vim.fn.getline(lnum)
	local level = M.get_heading_level(line)

	if level then
		-- Return ">N" to start a fold at level N
		-- Each heading starts its own fold
		return ">" .. level
	else
		-- Return "=" to inherit fold level from previous line
		return "="
	end
end

-- Helper: Get fold state for a heading
-- @param bufnr number: Buffer number
-- @param lnum number: Line number
-- @return string|nil: Fold state ("folded"|"children"|"subtree"|"expanded"), or nil
function M.get_fold_state(bufnr, lnum)
	local states = vim.b[bufnr].org_markdown_fold_states
	if not states then
		return nil
	end
	return states[lnum]
end

-- Helper: Set fold state for a heading
-- @param bufnr number: Buffer number
-- @param lnum number: Line number
-- @param state string: Fold state ("folded"|"children"|"subtree"|"expanded")
function M.set_fold_state(bufnr, lnum, state)
	-- Get the states table, modify it, and set it back
	-- (vim.b accessor doesn't support direct nested modifications)
	local states = vim.b[bufnr].org_markdown_fold_states or {}
	states[lnum] = state
	vim.b[bufnr].org_markdown_fold_states = states
end

-- Helper: Find all child headings of a given heading
-- @param bufnr number: Buffer number
-- @param start_lnum number: Line number of parent heading
-- @param parent_level number: Level of parent heading
-- @return table: Array of {lnum, level} for child headings
local function find_child_headings(bufnr, start_lnum, parent_level)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local children = tree.find_children(lines, start_lnum, parent_level)
	-- tree.find_children returns {line, level}, but callers expect {lnum, level}
	local result = {}
	for _, child in ipairs(children) do
		table.insert(result, { lnum = child.line, level = child.level })
	end
	return result
end

-- Helper: Find end line of a heading's subtree
-- @param bufnr number: Buffer number
-- @param start_lnum number: Line number of heading
-- @param heading_level number: Level of heading
-- @return number: Last line number of subtree
local function find_subtree_end(bufnr, start_lnum, heading_level)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	return tree.find_end(lines, start_lnum, heading_level)
end

-- Cycle fold state for heading under cursor
-- Cycles: folded → children → subtree → expanded → folded
-- @return boolean: true if cursor was on a heading and fold was cycled
function M.cycle_heading_fold()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local lnum = cursor[1]

	-- Check if cursor is on a heading
	if not M.is_heading_line(lnum) then
		return false
	end

	local line = vim.fn.getline(lnum)
	local heading_level = M.get_heading_level(line)
	if not heading_level then
		return false
	end

	-- Get current state - detect from actual fold if not tracked
	local current_state = M.get_fold_state(bufnr, lnum)
	if not current_state then
		-- Detect actual fold state from Neovim
		local foldclosed = vim.fn.foldclosed(lnum)
		if foldclosed == lnum then
			-- This heading's fold is closed
			current_state = "folded"
		else
			current_state = "expanded"
		end
	end

	-- Cycle to next state
	local next_state
	if current_state == "expanded" then
		next_state = "folded"
	elseif current_state == "folded" then
		next_state = "children"
	elseif current_state == "children" then
		next_state = "subtree"
	else -- subtree
		next_state = "expanded"
	end

	-- Apply the fold state
	if next_state == "folded" then
		-- Close the fold at cursor
		vim.cmd("normal! zc")
	elseif next_state == "children" then
		-- Open this fold, close all child folds
		vim.cmd("normal! zo")

		-- Check if fold actually opened, try zO if not
		if vim.fn.foldclosed(lnum) ~= -1 then
			vim.cmd("normal! zO")
		end

		-- Find and close all direct children
		local children = find_child_headings(bufnr, lnum, heading_level)
		for _, child in ipairs(children) do
			-- Move to child heading and close it
			vim.api.nvim_win_set_cursor(0, { child.lnum, 0 })
			vim.cmd("normal! zc")
		end

		-- Return cursor to original heading
		vim.api.nvim_win_set_cursor(0, cursor)
	elseif next_state == "subtree" or next_state == "expanded" then
		-- Open all folds in entire subtree
		local subtree_end = find_subtree_end(bufnr, lnum, heading_level)

		-- Open this fold (try zO if zo doesn't work)
		vim.cmd("normal! zo")
		if vim.fn.foldclosed(lnum) ~= -1 then
			vim.cmd("normal! zO")
		end

		-- Open all folds in the subtree range
		for i = lnum + 1, subtree_end do
			if M.is_heading_line(i) then
				vim.api.nvim_win_set_cursor(0, { i, 0 })
				vim.cmd("normal! zo")
				if vim.fn.foldclosed(i) ~= -1 then
					vim.cmd("normal! zO")
				end
			end
		end

		-- Return cursor to original heading
		vim.api.nvim_win_set_cursor(0, cursor)
	end

	-- Update state tracking
	M.set_fold_state(bufnr, lnum, next_state)

	return true
end

-- Cycle global fold level for entire buffer
-- Cycles: level 0 (all folded) → level 1 → level 2 → ... → level 99 (all expanded) → level 0
function M.cycle_global_fold()
	local bufnr = vim.api.nvim_get_current_buf()

	-- Get current global fold level (default to 99 if not tracked)
	local current_level = vim.b[bufnr].org_markdown_global_fold_level or 99

	-- Find max heading level in buffer to determine cycle range
	local max_level = 0
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	for lnum = 1, line_count do
		local line = vim.fn.getline(lnum)
		local level = M.get_heading_level(line)
		if level and level > max_level then
			max_level = level
		end
	end

	-- If no headings, do nothing
	if max_level == 0 then
		return
	end

	-- Cycle to next level
	local next_level
	if current_level >= max_level then
		-- All expanded, go back to all folded
		next_level = 0
	else
		-- Go to next level
		next_level = current_level + 1
	end

	-- Apply the fold level
	vim.opt_local.foldlevel = next_level

	-- Update state tracking
	vim.b[bufnr].org_markdown_global_fold_level = next_level

	-- Clear per-heading states since we're in global mode now
	vim.b[bufnr].org_markdown_fold_states = {}
end

-- Setup folding for a buffer
-- @param bufnr number: Buffer number
function M.setup_buffer_folding(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- Find a window displaying this buffer (or use current window if it's the buffer)
	local winid = vim.fn.bufwinid(bufnr)
	if winid == -1 then
		-- Buffer not displayed in any window, can't set fold options
		-- Just initialize state and return
		vim.b[bufnr].org_markdown_fold_states = {}
		return
	end

	-- Set fold method to expression (window-local)
	vim.wo[winid].foldmethod = "expr"

	-- Set fold expression to our function (window-local)
	vim.wo[winid].foldexpr = 'v:lua.require("org_markdown.folding").get_fold_level(v:lnum)'

	-- Initialize state tracking (buffer-local)
	vim.b[bufnr].org_markdown_fold_states = {}

	-- Set initial fold level based on config
	local config = require("org_markdown.config")
	local folding_config = config.folding or {}

	if folding_config.auto_fold_on_open then
		-- Find the minimum heading level in the buffer
		-- This allows us to show all top-level headings while folding their content
		local min_level = 99
		local line_count = vim.api.nvim_buf_line_count(bufnr)
		for lnum = 1, line_count do
			local line = vim.fn.getline(lnum)
			local level = M.get_heading_level(line)
			if level and level < min_level then
				min_level = level
			end
		end

		-- Set foldlevel to show all top-level headings (min_level) but fold their content
		-- foldlevel = min_level - 1 means headings at min_level are visible but folded
		local initial_foldlevel = min_level > 1 and (min_level - 1) or 0
		vim.wo[winid].foldlevel = initial_foldlevel
		vim.b[bufnr].org_markdown_global_fold_level = initial_foldlevel
	else
		-- Start with all headings expanded
		vim.wo[winid].foldlevel = 99
		vim.b[bufnr].org_markdown_global_fold_level = 99
	end

	-- Set up autocmds to clean up state and window options
	local augroup = vim.api.nvim_create_augroup("OrgMarkdownFolding_" .. bufnr, { clear = true })

	-- Clean up buffer-local state on unload
	vim.api.nvim_create_autocmd("BufUnload", {
		group = augroup,
		buffer = bufnr,
		callback = function()
			vim.b[bufnr].org_markdown_fold_states = nil
			vim.b[bufnr].org_markdown_global_fold_level = nil
		end,
	})

	-- Reset window-local folding options when leaving markdown buffer
	vim.api.nvim_create_autocmd("BufWinLeave", {
		group = augroup,
		buffer = bufnr,
		callback = function()
			local current_winid = vim.api.nvim_get_current_win()
			-- Reset to Neovim defaults
			vim.wo[current_winid].foldmethod = "manual"
			vim.wo[current_winid].foldexpr = "0"
			vim.wo[current_winid].foldlevel = 0
		end,
	})
end

return M
