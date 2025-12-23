local M = {}
local tree = require("org_markdown.utils.tree")
local document = require("org_markdown.utils.document")

-- ============================================================================
-- Document Caching
-- ============================================================================

-- Module-level cache to preserve metatables (vim.b serializes and loses them)
local document_cache = {}

--- Get or parse the cached document tree for a buffer
---@param bufnr number Buffer number
---@return Node|nil Root document node
local function get_document(bufnr)
	local cached = document_cache[bufnr]
	if cached then
		return cached
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local root = document.parse(lines)
	document_cache[bufnr] = root
	return root
end

--- Invalidate cached document (call on text changes)
---@param bufnr number Buffer number
local function invalidate_document(bufnr)
	document_cache[bufnr] = nil
end

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

-- ============================================================================
-- Fold Application Helpers
-- ============================================================================

--- Recursively open all folds in a subtree
---@param node Node The node whose subtree to open
local function open_subtree_folds(node)
	if node.type == "heading" then
		local lnum = node.start_line
		vim.api.nvim_win_set_cursor(0, { lnum, 0 })
		vim.cmd("normal! zo")
		if vim.fn.foldclosed(lnum) ~= -1 then
			vim.cmd("normal! zO")
		end
		node.is_open = true
	end

	for _, child in ipairs(node.children) do
		open_subtree_folds(child)
	end
end

--- Apply a fold state to a node
---@param node Node The heading node
---@param state string The fold state to apply ("folded", "children", "subtree", "expanded")
---@param original_cursor table Original cursor position to restore
local function apply_fold_state(node, state, original_cursor)
	local lnum = node.start_line
	local winid = vim.api.nvim_get_current_win()

	if state == "folded" then
		vim.cmd("normal! zc")
		node.is_open = false
	elseif state == "children" then
		-- Open all folds first with zR, then close children
		vim.cmd("normal! zR")
		node.is_open = true

		-- Close all direct child folds
		for _, child in ipairs(node.children) do
			if child.type == "heading" then
				vim.api.nvim_win_set_cursor(0, { child.start_line, 0 })
				vim.cmd("normal! zc")
				child.is_open = false
			end
		end

		vim.api.nvim_win_set_cursor(0, original_cursor)
	elseif state == "subtree" or state == "expanded" then
		-- Set foldlevel high to open all folds
		vim.wo[winid].foldlevel = 99

		-- Open all folds recursively
		open_subtree_folds(node)
		vim.api.nvim_win_set_cursor(0, original_cursor)
	end
end

-- Cycle fold state for heading under cursor
-- Smart cycling: leaf nodes cycle folded ↔ expanded
--                parent nodes cycle folded → children → subtree → expanded → folded
-- @return boolean: true if cursor was on a heading and fold was cycled
function M.cycle_heading_fold()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local lnum = cursor[1]

	-- Get cached document tree
	local root = get_document(bufnr)
	if not root then
		return false
	end

	-- Find node at cursor
	local node = document.find_node_at_line(root, lnum)
	if not node or node.type ~= "heading" then
		return false
	end

	-- Ensure we're on the heading line itself, not content
	if lnum ~= node.start_line then
		return false
	end

	-- Get current state - detect from actual fold if not tracked
	local current_state = M.get_fold_state(bufnr, lnum)
	if not current_state then
		-- Detect actual fold state from Neovim
		local foldclosed = vim.fn.foldclosed(lnum)
		if foldclosed == lnum then
			current_state = "folded"
		else
			current_state = "expanded"
		end
	end

	-- Smart cycle based on whether node has children
	local next_state = node:get_next_fold_state(current_state)

	-- Apply the fold state
	apply_fold_state(node, next_state, cursor)

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
			document_cache[bufnr] = nil
		end,
	})

	-- Invalidate document cache on text changes
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = augroup,
		buffer = bufnr,
		callback = function()
			invalidate_document(bufnr)
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
