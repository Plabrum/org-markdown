-- Editing keybindings and inline operations
-- Responsibilities:
-- - Setup buffer-local keybindings for editing operations
-- - Inline checkbox state cycling (without document model)
-- - Inline status cycling (simple text replacement)
-- - Document-based status cycling (with COMPLETED_AT handling)
-- - Heading promotion/demotion (with children adjustment)
-- - Todo list continuation on Enter

local config = require("org_markdown.config")
local M = {}

function M.cycle_checkbox_inline(line, states)
	local pattern = "%- %[(.)%]"
	local current = line:match(pattern)

	-- early return if no checkbox found
	if not current then
		return nil
	end

	local index
	for i, state in ipairs(states) do
		if state == current then -- compare raw
			index = i
			break
		end
	end

	if not index then
		return nil
	end

	local next_state = states[(index % #states) + 1]
	local new_line = line:gsub(pattern, "- [" .. next_state .. "]", 1)
	return { new_line }
end

function M.cycle_status_inline(line, states)
	local heading_pattern = "^(#+)%s+(%u[%u_%-]*)%s*(.*)$"
	local hashes, current, rest = line:match(heading_pattern)

	if not (hashes and current) then
		return nil
	end

	local index
	for i, state in ipairs(states) do
		if state == current then
			index = i
			break
		end
	end

	if not index then
		return nil
	end

	local next_state = states[(index % #states) + 1]

	-- Preserve spacing: if rest starts with content, add a space; otherwise keep as-is
	local new_rest = rest
	if rest and rest ~= "" and not rest:match("^%s") then
		new_rest = " " .. rest
	end

	local new_line = string.format("%s %s%s", hashes, next_state, new_rest)

	-- Note: COMPLETED_AT is now handled by cycle_status_with_document
	-- which adds it at the bottom of the node content

	return { new_line }
end

--- Cycle status using document tree model
--- Automatically adds COMPLETED_AT at bottom of node content when cycling to DONE
--- @param bufnr number Buffer number (0 for current)
--- @return boolean success
function M.cycle_status_with_document(bufnr)
	bufnr = bufnr or 0
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local current_line = cursor[1]

	-- Parse document into tree
	local document = require("org_markdown.utils.document")
	local root = document.parse(lines)

	-- Find node at cursor
	local node = document.find_node_at_line(root, current_line)
	if not node or node.type ~= "heading" then
		return false
	end

	-- Get current state
	local current_state = node.parsed.state
	if not current_state then
		return false
	end

	-- Find next state in cycle
	local states = config.status_states
	local index = nil
	for i, state in ipairs(states) do
		if state == current_state then
			index = i
			break
		end
	end

	if not index then
		return false
	end

	local next_state = states[(index % #states) + 1]

	-- Mutate node (this auto-handles COMPLETED_AT)
	node:set_state(next_state)

	-- Serialize and diff
	local new_lines = document.serialize(root)
	local changes = document.diff(lines, new_lines)

	-- Apply minimal changes
	document.apply_to_buffer(bufnr, changes)

	return true
end

--- Promote heading (decrease level) using document tree model
--- Adjusts the heading and all children recursively
--- @param bufnr number Buffer number (0 for current)
--- @return boolean success
function M.promote_heading(bufnr)
	bufnr = bufnr or 0
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local current_line = cursor[1]

	-- Parse document into tree
	local document = require("org_markdown.utils.document")
	local root = document.parse(lines)

	-- Find node at cursor
	local node = document.find_node_at_line(root, current_line)
	if not node or node.type ~= "heading" then
		return false
	end

	-- Check if we can promote (level must be > 1)
	if node.level <= 1 then
		return false
	end

	-- Adjust level (decrease by 1)
	document.adjust_node_levels(node, -1)

	-- Serialize and diff
	local new_lines = document.serialize(root)
	local changes = document.diff(lines, new_lines)

	-- Apply minimal changes
	document.apply_to_buffer(bufnr, changes)

	return true
end

--- Demote heading (increase level) using document tree model
--- Adjusts the heading and all children recursively
--- @param bufnr number Buffer number (0 for current)
--- @return boolean success
function M.demote_heading(bufnr)
	bufnr = bufnr or 0
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local current_line = cursor[1]

	-- Parse document into tree
	local document = require("org_markdown.utils.document")
	local root = document.parse(lines)

	-- Find node at cursor
	local node = document.find_node_at_line(root, current_line)
	if not node or node.type ~= "heading" then
		return false
	end

	-- Check if we can demote (level must be < 6)
	if node.level >= 6 then
		return false
	end

	-- Adjust level (increase by 1)
	document.adjust_node_levels(node, 1)

	-- Serialize and diff
	local new_lines = document.serialize(root)
	local changes = document.diff(lines, new_lines)

	-- Apply minimal changes
	document.apply_to_buffer(bufnr, changes)

	return true
end

--- Continue a bullet/checkbox list on Enter, splitting the line at the cursor
--- when Enter is pressed mid-line instead of always appending an empty bullet.
--- @param line string The current line content
--- @param col number|nil Byte offset of the cursor (0-indexed, like nvim_win_get_cursor col). Defaults to end of line.
--- @return string[]|nil new_lines, number|nil cursor_col
function M.continue_todo(line, col)
	col = col or #line

	-- Try checkbox pattern first, then plain bullet pattern
	local indent, marker, contents = line:match("^(%s*)(%- %[.%] )(.*)$")
	local continuation = marker and "- [ ] " or nil

	if not indent then
		indent, marker, contents = line:match("^(%s*)(%- )(.*)$")
		continuation = marker and "- " or nil
	end

	if not indent then
		-- Not a bullet line
		return nil
	end

	local marker_end = #indent + #marker

	if col >= #line then
		-- Cursor at end of line: preserve existing continuation behavior
		if contents == "" or contents == " " then
			return { "" } -- Remove empty bullet
		end
		local new_bullet = indent .. continuation
		return { line, new_bullet }, #new_bullet
	end

	if col <= marker_end then
		-- Cursor is within the indent/marker itself (with content after) - defer to default <CR>
		return nil
	end

	-- Cursor mid-line: split the line, carrying the tail onto a new bullet
	local before = line:sub(1, col)
	local after = line:sub(col + 1)
	local new_line = indent .. continuation .. after
	return { before, new_line }, #indent + #continuation
end

function M.edit_line_at_cursor(modifier_fn, update_cursor)
	local row = vim.fn.line(".") - 1
	local col = vim.fn.col(".") - 1
	local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]
	local new_lines, cursor_col = modifier_fn(line, col)

	if new_lines then
		vim.api.nvim_buf_set_lines(0, row, row + 1, false, new_lines)
		if update_cursor then
			vim.api.nvim_win_set_cursor(0, { row + #new_lines, cursor_col or #new_lines[#new_lines] })
		end
		return true
	else
		return false
	end
end

local function already_set(buf)
	return vim.b[buf].org_markdown_keys_set == true
end

local function mark_set(buf)
	vim.b[buf].org_markdown_keys_set = true
end
function M.setup_editing_keybinds(bufnr)
	bufnr = bufnr or 0
	if already_set(bufnr) then
		return
	end

	-- NORMAL: <CR> cycles checkbox/status, else fall back to default <CR>
	vim.keymap.set("n", "<CR>", function()
		-- Try checkbox first (simple inline edit)
		local did = M.edit_line_at_cursor(function(line)
			return M.cycle_checkbox_inline(line, config.checkbox_states)
		end)
		if did then
			return
		end

		-- Try status cycling with document model (handles COMPLETED_AT at node bottom)
		did = M.cycle_status_with_document(bufnr)
		if did then
			return
		end

		-- Fall back to default <CR>
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
	end, { desc = "org-markdown: cycle or enter", buffer = bufnr })

	-- NORMAL: <Tab> cycles heading folds (ONLY - no fallback to todo cycling)
	local folding_config = config.folding or {}
	if folding_config.enabled and folding_config.fold_on_tab then
		local filepath = vim.api.nvim_buf_get_name(bufnr)
		local folding = require("org_markdown.folding")
		if folding.should_enable_folding_for_file(filepath) then
			vim.keymap.set("n", "<Tab>", function()
				folding.cycle_heading_fold()
				-- No fallback - Tab is for folding only, Enter is for todo cycling
			end, { desc = "org-markdown: cycle fold", buffer = bufnr })
		end
	end

	-- NORMAL: <S-Tab> cycles global fold level
	if folding_config.enabled and folding_config.global_fold_on_shift_tab then
		local filepath = vim.api.nvim_buf_get_name(bufnr)
		local folding = require("org_markdown.folding")
		if folding.should_enable_folding_for_file(filepath) then
			vim.keymap.set("n", "<S-Tab>", function()
				folding.cycle_global_fold()
			end, { desc = "org-markdown: cycle global fold level", buffer = bufnr })
		end
	end

	-- INSERT: <CR> continues todos, else default <CR>
	vim.keymap.set("i", "<CR>", function()
		local edited = M.edit_line_at_cursor(M.continue_todo, true)
		if not edited then
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
		end
	end, { desc = "org-markdown: continue todo", buffer = bufnr })

	-- NORMAL: << promotes heading (decrease level, shift left)
	vim.keymap.set("n", "<<", function()
		M.promote_heading(bufnr)
	end, { desc = "org-markdown: promote heading", buffer = bufnr, silent = true })

	-- NORMAL: >> demotes heading (increase level, shift right)
	vim.keymap.set("n", ">>", function()
		M.demote_heading(bufnr)
	end, { desc = "org-markdown: demote heading", buffer = bufnr, silent = true })

	mark_set(bufnr)
end

return M
