-- Lazily minted node identity.
--
-- A node is a file or a heading, and both carry a stable UUID in their
-- metadata: a file keeps `id` in its frontmatter, a heading keeps an `ID`
-- property directly under its heading line. Links (Epic B) resolve through
-- these ids rather than through paths, so a target survives being renamed or
-- refiled.
--
-- MINTED ON DEMAND: `get` only reads, and `ensure` writes exactly once — the
-- first time someone actually needs the id. A second `ensure` returns the
-- stored id and leaves the file untouched, so asking for an identity is safe to
-- repeat and never churns a user's markdown.
--
-- All IO goes through the platform shim, so ids can be minted from the
-- standalone CLI (bin/org) as well as in-editor.

local compat = require("org_markdown.compat.vim")
local platform = require("org_markdown.platform")
local document = require("org_markdown.utils.document")
local frontmatter = require("org_markdown.utils.frontmatter")
local uuid = require("org_markdown.utils.uuid")

local M = {}

-- Where the identity lives for each kind of node.
M.FILE_FIELD = "id"
M.HEADING_PROPERTY = "ID"

--- Normalize a target into `{ file = <expanded path>, heading = <text|nil> }`.
--- Accepts a bare path for a file node, or a table carrying a `file` and the
--- heading text (`heading`, or `title`/`text` as agenda items and the parser
--- name it) for a heading node.
---@param target string|table
---@return table|nil node, string|nil err
local function resolve(target)
	if type(target) == "string" then
		target = { file = target }
	end

	if type(target) ~= "table" then
		return nil, "target must be a file path or a table"
	end

	if not target.file or target.file == "" then
		return nil, "target has no file"
	end

	local heading = target.heading or target.title or target.text
	heading = heading and compat.trim(heading) or nil

	return {
		file = platform.path.expand(target.file),
		heading = heading ~= "" and heading or nil,
	}
end

--- Read a file into lines, dropping the empty field a trailing newline yields
--- so writing the lines back reproduces the file verbatim.
---@param path string
---@return string[]|nil lines, string|nil err
local function read_lines(path)
	local content, err = platform.fs.read_file(path)
	if not content then
		return nil, "could not read " .. path .. ": " .. (err or "unknown error")
	end

	local lines = compat.split(content, "\n")
	if lines[#lines] == "" then
		table.remove(lines)
	end
	return lines
end

---@param path string
---@param lines string[]
---@return boolean ok, string|nil err
local function write_lines(path, lines)
	local ok, err = platform.fs.write_file(path, table.concat(lines, "\n") .. "\n")
	if not ok then
		return false, "could not write " .. path .. ": " .. (err or "unknown error")
	end
	return true
end

--- Locate the heading node carrying an identity.
---@param lines string[]
---@param heading string
---@return table|nil node, table|nil root, string|nil err
local function find_heading(lines, heading)
	local root = document.parse(lines)
	local node = document.find_heading_by_text(root, heading)
	if not node then
		return nil, nil, "no heading matching '" .. heading .. "'"
	end
	return node, root
end

--- Read the id of a node without minting one.
---@param target string|table
---@return string|nil id, string|nil err
function M.get(target)
	local node, err = resolve(target)
	if not node then
		return nil, err
	end

	local lines, read_err = read_lines(node.file)
	if not lines then
		return nil, read_err
	end

	if not node.heading then
		return frontmatter.get_field(lines, M.FILE_FIELD)
	end

	local heading, _, heading_err = find_heading(lines, node.heading)
	if not heading then
		return nil, heading_err
	end
	return heading:get_property(M.HEADING_PROPERTY)
end

--- Return the id of a node, minting and storing one when it has none.
--- Idempotent: an already-identified node is read, not written.
---@param target string|table
---@return string|nil id, string|nil err
function M.ensure(target)
	local node, err = resolve(target)
	if not node then
		return nil, err
	end

	local lines, read_err = read_lines(node.file)
	if not lines then
		return nil, read_err
	end

	if not node.heading then
		local existing = frontmatter.get_field(lines, M.FILE_FIELD)
		if existing then
			return existing
		end

		local id = uuid.generate()
		local ok, write_err = write_lines(node.file, frontmatter.set_field(lines, M.FILE_FIELD, id))
		if not ok then
			return nil, write_err
		end
		return id
	end

	local heading, root, heading_err = find_heading(lines, node.heading)
	if not heading then
		return nil, heading_err
	end

	local existing = heading:get_property(M.HEADING_PROPERTY)
	if existing then
		return existing
	end

	local id = uuid.generate()
	heading:set_property(M.HEADING_PROPERTY, id)
	local ok, write_err = write_lines(node.file, document.serialize(root))
	if not ok then
		return nil, write_err
	end
	return id
end

return M
