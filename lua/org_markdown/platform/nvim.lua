-- Neovim platform backend: delegates to the editor runtime (vim.uv / vim.fn).
-- Selected by platform/init.lua whenever a `vim` global with libuv is present.

local M = {}

M.fs = {}
M.path = {}

--- List a directory's immediate entries via libuv.
--- A missing/unreadable dir yields an empty list (callers skip it gracefully).
---@param dir string
---@return { name: string, type: string }[] entries
function M.fs.scandir(dir)
	local entries = {}
	local handle = vim.uv.fs_scandir(dir)
	if not handle then
		return entries
	end

	while true do
		local name, type_ = vim.uv.fs_scandir_next(handle)
		if not name then
			break
		end
		entries[#entries + 1] = { name = name, type = type_ }
	end

	return entries
end

--- Current working directory.
---@return string
function M.fs.cwd()
	return vim.uv.cwd()
end

--- Read an entire file into a string.
---@param path string
---@return string|nil content, string|nil err
function M.fs.read_file(path)
	local file, err = io.open(path, "r")
	if not file then
		return nil, err
	end
	local content = file:read("*a")
	file:close()
	return content
end

--- Write a string to a file, replacing any existing content.
---@param path string
---@param content string
---@return boolean ok, string|nil err
function M.fs.write_file(path, content)
	local file, err = io.open(path, "w")
	if not file then
		return false, err
	end
	file:write(content)
	file:close()
	return true
end

--- Append a string to a file, creating it when absent. Existing content is
--- never rewritten, which is what the append-only event log relies on.
---@param path string
---@param content string
---@return boolean ok, string|nil err
function M.fs.append_file(path, content)
	local file, err = io.open(path, "a")
	if not file then
		return false, err
	end
	file:write(content)
	file:close()
	return true
end

--- Create a directory and any missing parents. A directory that already exists
--- is left alone.
---@param dir string
---@return boolean ok, string|nil err
function M.fs.mkdirp(dir)
	if vim.fn.isdirectory(dir) == 1 then
		return true
	end

	local ok, err = pcall(vim.fn.mkdir, dir, "p")
	if not ok then
		return false, tostring(err)
	end
	return true
end

--- Expand `~` and environment variables via `vim.fn.expand`.
---@param p string
---@return string
function M.path.expand(p)
	return vim.fn.expand(p)
end

--- Final path component (`fnamemodify(p, ":t")`).
---@param p string
---@return string
function M.path.basename(p)
	return vim.fn.fnamemodify(p, ":t")
end

--- Path relative to cwd/home (`fnamemodify(p, ":~:.")`).
---@param p string
---@return string
function M.path.relative(p)
	return vim.fn.fnamemodify(p, ":~:.")
end

--- Emit a notification through the editor.
---@param msg string
---@param level? integer
function M.notify(msg, level)
	vim.notify(msg, level)
end

return M
