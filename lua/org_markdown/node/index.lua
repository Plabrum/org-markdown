-- The id-to-location index.
--
-- Links (Epic B) point at a node's UUID rather than at its path, so resolving
-- one means answering "where does this id live right now?". That answer is
-- derived, never stored: the index is built by scanning the configured
-- `refile_paths` with `utils/queries.lua` and reading the ids that
-- `node/id.lua` minted into frontmatter and heading properties.
--
-- SCAN AND REBUILD: every build walks the files afresh, so a rename or a refile
-- is picked up simply by rebuilding. Keeping the index up to date incrementally
-- as buffers change is ORGMD-1's job.
--
-- All IO goes through the platform shim, so the index can be built from the
-- standalone CLI (bin/org) as well as in-editor.

local compat = require("org_markdown.compat.vim")
local document = require("org_markdown.utils.document")
local frontmatter = require("org_markdown.utils.frontmatter")
local id = require("org_markdown.node.id")
local platform = require("org_markdown.platform")
local queries = require("org_markdown.utils.queries")

local M = {}

--- Record every identified heading in a parsed document, depth first, so a
--- parent is indexed before the children nested under it.
---@param node table document or heading node
---@param file string
---@param index table<string, table>
local function collect_headings(node, file, index)
	for _, child in ipairs(node.children) do
		local heading_id = child:get_property(id.HEADING_PROPERTY)
		if heading_id and not index[heading_id] then
			index[heading_id] = {
				id = heading_id,
				file = file,
				heading = child.parsed and child.parsed.text,
				line = child.start_line,
			}
		end
		collect_headings(child, file, index)
	end
end

--- Index one file: its own id, then the id of every heading inside it.
---@param file string
---@param index table<string, table>
local function collect_file(file, index)
	local content = platform.fs.read_file(file)
	if not content then
		return
	end

	local lines = compat.split(content, "\n")
	if lines[#lines] == "" then
		table.remove(lines)
	end

	local file_id = frontmatter.get_field(lines, id.FILE_FIELD)
	if file_id and not index[file_id] then
		index[file_id] = { id = file_id, file = file }
	end

	collect_headings(document.parse(lines), file, index)
end

--- Build the index by scanning every markdown file in scope.
--- A location is `{ id, file }` for a file node, and additionally carries
--- `heading` and `line` for a heading node. When the same id appears twice the
--- first one scanned wins, so a stray copy never displaces the original.
---@param opts? { use_cwd?: boolean, include_patterns?: table, ignore_patterns?: table }
---@return table<string, table> index
function M.build(opts)
	local index = {}
	for _, file in ipairs(queries.find_markdown_files(opts)) do
		collect_file(file, index)
	end
	return index
end

--- Where a node lives now, or nil when no file in scope carries that id.
--- Pass an `index` to resolve many ids without rescanning.
---@param node_id string
---@param index? table<string, table>
---@return table|nil location
function M.lookup(node_id, index)
	if not node_id or node_id == "" then
		return nil
	end
	return (index or M.build())[node_id]
end

return M
