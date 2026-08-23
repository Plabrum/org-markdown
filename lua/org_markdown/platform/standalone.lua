-- Standalone platform backend: pure Lua (luajit, no `vim` global).
-- Used when the CLI runs outside Neovim. Filesystem scanning shells out to
-- `ls` via io.popen so we stay dependency-free; only macOS/Linux is targeted.

local M = {}

M.fs = {}
M.path = {}

-- Wrap a path in single quotes so it survives the shell verbatim.
local function shell_quote(str)
	return "'" .. str:gsub("'", "'\\''") .. "'"
end

--- List a directory's immediate entries (including dotfiles, excluding . and ..).
--- `ls -p` suffixes directories with `/`, which is all we need to classify type.
---@param dir string
---@return { name: string, type: string }[] entries
function M.fs.scandir(dir)
	local entries = {}
	local handle = io.popen("ls -1Ap -- " .. shell_quote(dir) .. " 2>/dev/null")
	if not handle then
		return entries
	end

	for line in handle:lines() do
		if line ~= "" then
			if line:sub(-1) == "/" then
				entries[#entries + 1] = { name = line:sub(1, -2), type = "directory" }
			else
				entries[#entries + 1] = { name = line, type = "file" }
			end
		end
	end

	handle:close()
	return entries
end

--- Current working directory.
---@return string
function M.fs.cwd()
	local handle = io.popen("pwd")
	if not handle then
		return "."
	end
	local dir = handle:read("*l") or "."
	handle:close()
	return dir
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
--- is left alone (`mkdir -p` is already idempotent).
---@param dir string
---@return boolean ok, string|nil err
function M.fs.mkdirp(dir)
	local ok = os.execute("mkdir -p -- " .. shell_quote(dir))
	if ok == true or ok == 0 then
		return true
	end
	return false, "could not create " .. dir
end

--- Expand a leading `~` and `$VAR`/`${VAR}` environment references.
---@param p string
---@return string
function M.path.expand(p)
	local home = os.getenv("HOME") or ""
	if p == "~" then
		p = home
	else
		p = p:gsub("^~/", home .. "/")
	end

	p = p:gsub("%${([%w_]+)}", function(name)
		return os.getenv(name) or ""
	end)
	p = p:gsub("%$([%w_]+)", function(name)
		return os.getenv(name) or ""
	end)

	return p
end

--- Final path component (matches `fnamemodify(p, ":t")`; trailing slash -> "").
---@param p string
---@return string
function M.path.basename(p)
	return p:match("[^/]*$") or p
end

--- Path relative to cwd, else to `~`, else unchanged (matches `:~:.`).
---@param p string
---@return string
function M.path.relative(p)
	local cwd = M.fs.cwd()
	if p == cwd then
		return "."
	end
	if p:sub(1, #cwd + 1) == cwd .. "/" then
		return p:sub(#cwd + 2)
	end

	local home = os.getenv("HOME")
	if home and p:sub(1, #home + 1) == home .. "/" then
		return "~/" .. p:sub(#home + 2)
	end

	return p
end

--- Emit a notification. Standalone has no UI, so route to stderr.
---@param msg string
---@param _level? integer
function M.notify(msg, _level)
	io.stderr:write(msg .. "\n")
end

return M
