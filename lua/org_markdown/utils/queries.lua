local async = require("org_markdown.utils.async")
local config = require("org_markdown.config")

local M = {}

local function is_markdown(file)
	return file:match("%.md$") or file:match("%.markdown$")
end

local function scan_dir_sync(dir, collected)
	local handle = vim.uv.fs_scandir(dir)
	if not handle then
		return
	end

	while true do
		local name, type_ = vim.uv.fs_scandir_next(handle)
		if not name then
			break
		end

		local full_path = dir .. "/" .. name
		if type_ == "file" and is_markdown(name) then
			table.insert(collected, full_path)
		elseif type_ == "directory" then
			scan_dir_sync(full_path, collected)
		end
	end
end

--- Public sync markdown file finder
---@param opts? { use_cwd?: boolean }
---@return string[] markdown_files
function M.find_markdown_files(opts)
	opts = opts or {}
	local use_cwd = opts.use_cwd or false

	local roots = {}
	if use_cwd then
		table.insert(roots, vim.uv.cwd())
	else
		for _, path in ipairs(config.refile_paths or {}) do
			table.insert(roots, vim.fn.expand(path))
		end
	end

	local all_files = {}
	for _, root in ipairs(roots) do
		scan_dir_sync(root, all_files)
	end

	return all_files
end

return M
