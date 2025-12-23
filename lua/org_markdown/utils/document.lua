--- Document tree model for org-markdown
--- Enables parse → edit → serialize → diff workflow
--- Properties like COMPLETED_AT live in node content, not heading line

local tree = require("org_markdown.utils.tree")
local parser = require("org_markdown.utils.parser")

local M = {}

-- ============================================================================
-- Node Class
-- ============================================================================

---@class Node
---@field type string "document" | "heading"
---@field level number|nil Heading level (1-6)
---@field raw_heading string|nil Original heading line
---@field parsed table|nil Parsed heading data
---@field content_lines string[] Body text
---@field properties table<string, string> Key-value properties
---@field children Node[] Child nodes
---@field start_line number Original line number
---@field end_line number End line number
---@field dirty boolean Whether modified
---@field is_open boolean|nil Whether fold is open (runtime-only, not serialized)
local Node = {}
Node.__index = Node

--- Create a new Node instance
---@param opts table
---@return Node
function Node.new(opts)
	local self = setmetatable({}, Node)
	self.type = opts.type or "heading"
	self.level = opts.level
	self.raw_heading = opts.raw_heading
	self.parsed = opts.parsed
	self.content_lines = {}
	self.properties = {}
	self.children = {}
	self.start_line = opts.start_line or 0
	self.end_line = opts.end_line or 0
	self.dirty = false
	self.is_open = true -- Default to open (runtime-only, not serialized)
	return self
end

--- Get completed_at date from properties
---@return string|nil ISO date string
function Node:get_completed_at()
	return self.properties.COMPLETED_AT
end

--- Get completed_at as date table
---@return table|nil {year, month, day}
function Node:get_completed_at_date()
	local date_str = self:get_completed_at()
	if not date_str then
		return nil
	end

	local year, month, day = date_str:match(parser.PATTERNS.iso_date)
	if not (year and month and day) then
		return nil
	end

	return {
		year = tonumber(year),
		month = tonumber(month),
		day = tonumber(day),
	}
end

--- Set state with auto-COMPLETED_AT handling
---@param new_state string
function Node:set_state(new_state)
	local old_state = self.parsed and self.parsed.state
	if self.parsed then
		self.parsed.state = new_state
	end
	self.dirty = true

	-- Auto-add COMPLETED_AT when transitioning to DONE
	local archive = require("org_markdown.archive")
	if new_state == "DONE" and old_state ~= "DONE" and archive.is_enabled() then
		local datetime = require("org_markdown.utils.datetime")
		local today = datetime.today()
		self.properties.COMPLETED_AT = datetime.to_iso_string(today)
	end

	-- Remove COMPLETED_AT when transitioning away from DONE
	if new_state ~= "DONE" and old_state == "DONE" then
		self.properties.COMPLETED_AT = nil
	end
end

--- Set a property
---@param key string
---@param value string|nil
function Node:set_property(key, value)
	self.properties[key] = value
	self.dirty = true
end

--- Get a property
---@param key string
---@return string|nil
function Node:get_property(key)
	return self.properties[key]
end

--- Check if node is a heading
---@return boolean
function Node:is_heading()
	return self.type == "heading"
end

--- Check if node has state
---@param state string
---@return boolean
function Node:has_state(state)
	return self.parsed and self.parsed.state == state
end

--- Check if this node has any children
---@return boolean
function Node:has_children()
	return #self.children > 0
end

--- Get fold states available for this node
--- Leaf nodes: folded <-> expanded
--- Parent nodes: folded -> children -> subtree -> expanded -> folded
---@return string[] Array of valid fold states
function Node:get_fold_states()
	if self:has_children() then
		return { "folded", "children", "subtree", "expanded" }
	else
		return { "folded", "expanded" }
	end
end

--- Get next fold state in cycle
---@param current_state string Current fold state
---@return string Next fold state
function Node:get_next_fold_state(current_state)
	local states = self:get_fold_states()
	for i, state in ipairs(states) do
		if state == current_state then
			return states[(i % #states) + 1]
		end
	end
	-- Default to first state if current not found
	return states[1]
end

-- ============================================================================
-- Parsing Helpers
-- ============================================================================

--- Parse property line
---@param line string
---@return string|nil, string|nil key, value
local function parse_property_line(line)
	return line:match(parser.PATTERNS.property)
end

--- Parse content lines, extracting properties
---@param lines string[]
---@return string[], table<string, string>
local function parse_content_with_properties(lines)
	local content = {}
	local properties = {}

	for _, line in ipairs(lines) do
		local key, value = parse_property_line(line)
		if key then
			properties[key] = value
		else
			table.insert(content, line)
		end
	end

	return content, properties
end

--- Find where content ends (before first child heading)
---@param lines string[]
---@param start_idx number
---@param heading_level number
---@return number
local function find_content_end(lines, start_idx, heading_level)
	for i = start_idx, #lines do
		local level = tree.get_level(lines[i])
		if level then
			return i - 1
		end
	end
	return #lines
end

--- Parse a heading and its subtree recursively
---@param lines string[]
---@param start_idx number
---@param level number
---@return Node, number
local function parse_heading(lines, start_idx, level)
	local heading_line = lines[start_idx]
	local block_end = tree.find_end(lines, start_idx, level)

	local node = Node.new({
		type = "heading",
		level = level,
		raw_heading = heading_line,
		parsed = parser.parse_headline(heading_line),
		start_line = start_idx,
		end_line = block_end,
	})

	-- Find where content ends (before first child)
	local content_end = find_content_end(lines, start_idx + 1, level)

	-- Collect content lines
	local raw_content = {}
	for i = start_idx + 1, content_end do
		table.insert(raw_content, lines[i])
	end
	node.content_lines, node.properties = parse_content_with_properties(raw_content)

	-- Parse children recursively
	local i = content_end + 1
	while i <= block_end do
		local child_level = tree.get_level(lines[i])
		if child_level and child_level > level then
			local child, next_idx = parse_heading(lines, i, child_level)
			table.insert(node.children, child)
			i = next_idx
		else
			i = i + 1
		end
	end

	return node, block_end + 1
end

-- ============================================================================
-- Document Module Functions
-- ============================================================================

--- Parse document into tree structure
---@param lines string[]
---@return Node Root document node
function M.parse(lines)
	local root = Node.new({
		type = "document",
		start_line = 1,
		end_line = #lines,
	})

	local i = 1
	while i <= #lines do
		local line = lines[i]
		local level = tree.get_level(line)

		if level then
			local node, next_idx = parse_heading(lines, i, level)
			table.insert(root.children, node)
			i = next_idx
		else
			table.insert(root.content_lines, line)
			i = i + 1
		end
	end

	return root
end

--- Serialize property to line
---@param key string
---@param value string
---@return string
local function serialize_property(key, value)
	return string.format("%s: [%s]", key, value)
end

--- Reconstruct heading line from parsed data
---@param node Node
---@return string
local function reconstruct_heading(node)
	if not node.dirty then
		return node.raw_heading
	end

	local parts = {}
	local p = node.parsed

	table.insert(parts, string.rep("#", node.level))

	if p.state then
		table.insert(parts, p.state)
	end

	if p.priority then
		table.insert(parts, string.format("[#%s]", p.priority))
	end

	if p.text and p.text ~= "" then
		table.insert(parts, p.text)
	end

	if p.tracked then
		local date_str = "<" .. p.tracked
		if p.start_time then
			date_str = date_str .. " " .. p.start_time
			if p.end_time then
				date_str = date_str .. "-" .. p.end_time
			end
		end
		date_str = date_str .. ">"
		table.insert(parts, date_str)
	end

	if p.untracked then
		table.insert(parts, "[" .. p.untracked .. "]")
	end

	if p.tags and #p.tags > 0 then
		table.insert(parts, ":" .. table.concat(p.tags, ":") .. ":")
	end

	return table.concat(parts, " ")
end

--- Serialize node to lines (recursive)
---@param node Node
---@param output string[]
local function serialize_node(node, output)
	if node.type == "heading" then
		table.insert(output, reconstruct_heading(node))

		for _, line in ipairs(node.content_lines) do
			table.insert(output, line)
		end

		-- Add properties at end of content (sorted for determinism)
		local keys = {}
		for key in pairs(node.properties) do
			table.insert(keys, key)
		end
		table.sort(keys)
		for _, key in ipairs(keys) do
			table.insert(output, serialize_property(key, node.properties[key]))
		end
	end

	for _, child in ipairs(node.children) do
		serialize_node(child, output)
	end
end

--- Serialize document tree to lines
---@param root Node
---@return string[]
function M.serialize(root)
	local output = {}

	for _, line in ipairs(root.content_lines) do
		table.insert(output, line)
	end

	for _, child in ipairs(root.children) do
		serialize_node(child, output)
	end

	return output
end

--- Calculate diff between original and modified lines
---@param original string[]
---@param modified string[]
---@return table[]
function M.diff(original, modified)
	local changes = {}
	local i, j = 1, 1
	local orig_len, mod_len = #original, #modified

	while i <= orig_len or j <= mod_len do
		if i > orig_len then
			local insert_lines = {}
			for k = j, mod_len do
				table.insert(insert_lines, modified[k])
			end
			table.insert(changes, { op = "insert", line = i, lines = insert_lines })
			break
		elseif j > mod_len then
			table.insert(changes, { op = "delete", line = i, count = orig_len - i + 1 })
			break
		elseif original[i] == modified[j] then
			i = i + 1
			j = j + 1
		else
			local found_orig, found_mod = nil, nil

			for k = i + 1, math.min(i + 50, orig_len) do
				if original[k] == modified[j] then
					found_orig = k
					break
				end
			end

			for k = j + 1, math.min(j + 50, mod_len) do
				if modified[k] == original[i] then
					found_mod = k
					break
				end
			end

			if found_orig and (not found_mod or found_orig - i <= found_mod - j) then
				table.insert(changes, { op = "delete", line = i, count = found_orig - i })
				i = found_orig
			elseif found_mod then
				local insert_lines = {}
				for k = j, found_mod - 1 do
					table.insert(insert_lines, modified[k])
				end
				table.insert(changes, { op = "insert", line = i, lines = insert_lines })
				j = found_mod
			else
				table.insert(changes, { op = "replace", line = i, lines = { modified[j] } })
				i = i + 1
				j = j + 1
			end
		end
	end

	return changes
end

--- Apply changes to buffer
---@param bufnr number
---@param changes table[]
function M.apply_to_buffer(bufnr, changes)
	for idx = #changes, 1, -1 do
		local change = changes[idx]
		local line = change.line - 1

		if change.op == "delete" then
			vim.api.nvim_buf_set_lines(bufnr, line, line + change.count, false, {})
		elseif change.op == "insert" then
			vim.api.nvim_buf_set_lines(bufnr, line, line, false, change.lines)
		elseif change.op == "replace" then
			vim.api.nvim_buf_set_lines(bufnr, line, line + 1, false, change.lines)
		end
	end
end

--- Find node at line number
---@param root Node
---@param line number
---@return Node|nil
function M.find_node_at_line(root, line)
	if line <= #root.content_lines then
		return root
	end

	for _, child in ipairs(root.children) do
		if line >= child.start_line and line <= child.end_line then
			if line == child.start_line then
				return child
			end

			local found = M.find_node_at_line(child, line)
			if found then
				return found
			end

			return child
		end
	end

	return nil
end

-- ============================================================================
-- Node Creation and Manipulation
-- ============================================================================

--- Create a new heading node with proper defaults
---@param opts table {level, text, state?, priority?, tags?, tracked?, untracked?, content_lines?}
---@return Node
function M.create_node(opts)
	local node = Node.new({
		type = "heading",
		level = opts.level or 1,
		start_line = 0,
		end_line = 0,
	})

	-- Build parsed data
	node.parsed = {
		state = opts.state,
		priority = opts.priority,
		text = opts.text or "",
		tags = opts.tags or {},
		tracked = opts.tracked,
		untracked = opts.untracked,
	}

	-- Set content lines if provided
	if opts.content_lines then
		node.content_lines = vim.deepcopy(opts.content_lines)
	end

	-- Mark as dirty so it will be reconstructed on serialize
	node.dirty = true

	return node
end

--- Insert a child node into parent's children
---@param parent Node The parent node
---@param child Node The child node to insert
---@param position number|nil Position (1-indexed, nil = append at end)
---@return Node The inserted child
function M.insert_child(parent, child, position)
	if position then
		table.insert(parent.children, position, child)
	else
		table.insert(parent.children, child)
	end

	parent.dirty = true
	return child
end

--- Remove a child node from parent's children
---@param parent Node The parent node
---@param child Node The child node to remove
---@return boolean True if removed, false if not found
function M.remove_child(parent, child)
	for i, c in ipairs(parent.children) do
		if c == child then
			table.remove(parent.children, i)
			parent.dirty = true
			return true
		end
	end
	return false
end

--- Find the parent of a node (recursive search)
---@param root Node Document root
---@param target Node The node to find the parent of
---@return Node|nil The parent node, or nil if target is root or not found
function M.find_parent(root, target)
	for _, child in ipairs(root.children) do
		if child == target then
			return root
		end
		local parent = M.find_parent(child, target)
		if parent then
			return parent
		end
	end
	return nil
end

--- Find a heading by text (recursive search)
---@param root Node Document root or parent node
---@param text string Heading text to find
---@return Node|nil
function M.find_heading_by_text(root, text)
	for _, child in ipairs(root.children) do
		if child.type == "heading" then
			if child.parsed and child.parsed.text == text then
				return child
			end
			-- Search in children recursively
			local found = M.find_heading_by_text(child, text)
			if found then
				return found
			end
		end
	end
	return nil
end

--- Adjust heading levels for a node and all its children
---@param node Node Node to adjust
---@param base_level number Level offset to add
function M.adjust_node_levels(node, base_level)
	if node.type == "heading" and node.level then
		node.level = node.level + base_level
		node.dirty = true
	end

	for _, child in ipairs(node.children) do
		M.adjust_node_levels(child, base_level)
	end
end

-- ============================================================================
-- File I/O
-- ============================================================================

--- Read file and parse into document tree
---@param filepath string Path to read from
---@return Node Document root
function M.read_from_file(filepath)
	local utils = require("org_markdown.utils.utils")
	local expanded = vim.fn.expand(filepath)
	local lines = utils.read_lines(expanded)
	return M.parse(lines)
end

--- Serialize document tree and write to file
---@param filepath string Path to write to
---@param root Node Document root
function M.write_to_file(filepath, root)
	local utils = require("org_markdown.utils.utils")
	local lines = M.serialize(root)
	utils.write_lines(filepath, lines)
end

-- Export Node class for direct use if needed
M.Node = Node

return M
