-- Compatibility shim for pure vim-stdlib helpers.
--
-- Neovim exposes a handful of pure-Lua utilities as `vim.*` globals that plain
-- luajit lacks (`vim.trim`, `vim.pesc`, `vim.deepcopy`, `vim.tbl_islist`,
-- `vim.tbl_contains`, `vim.log.levels`). Core modules route through this shim so
-- they behave identically in-editor and under the standalone CLI.
--
-- Unlike `platform` (which wraps IO/side-effects), everything here is a pure
-- value transform. When the `vim` global is present we delegate to it verbatim;
-- otherwise we fall back to faithful pure-Lua implementations. The module must
-- be require-able with no `vim` present (config.lua runs some of this at load).

local M = {}

local has_vim = _G.vim ~= nil

--- Strip leading and trailing whitespace.
---@param s string
---@return string
function M.trim(s)
	if has_vim then
		return vim.trim(s)
	end
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Escape Lua pattern magic characters so `s` matches literally.
--- Mirrors `vim.pesc`: escapes `().%+-*?[]^$`.
---@param s string
---@return string
function M.pesc(s)
	if has_vim then
		return vim.pesc(s)
	end
	return (s:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"))
end

--- Recursively copy a table (values and nested tables). Non-tables pass through.
--- Handles shared/cyclic references; metatables are intentionally not copied
--- (no caller relies on it).
---@generic T
---@param value T
---@return T
function M.deepcopy(value)
	if has_vim then
		return vim.deepcopy(value)
	end

	local function copy(v, seen)
		if type(v) ~= "table" then
			return v
		end
		if seen[v] then
			return seen[v]
		end
		local result = {}
		seen[v] = result
		for k, item in pairs(v) do
			result[copy(k, seen)] = copy(item, seen)
		end
		return result
	end

	return copy(value, {})
end

--- Report whether a table is a list (contiguous integer keys 1..n).
---@param t table
---@return boolean
function M.tbl_islist(t)
	if has_vim then
		return vim.tbl_islist(t)
	end

	local count = 0
	for k in pairs(t) do
		if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k then
			return false
		end
		count = count + 1
	end
	for i = 1, count do
		if t[i] == nil then
			return false
		end
	end
	return true
end

--- Report whether `value` is a member of list-like table `t`.
---@param t table
---@param value any
---@return boolean
function M.tbl_contains(t, value)
	if has_vim then
		return vim.tbl_contains(t, value)
	end

	for _, item in ipairs(t) do
		if item == value then
			return true
		end
	end
	return false
end

--- Log-level constants matching `vim.log.levels` numeric values.
--- Delegates to the real table in-editor so callers stay in lockstep.
---@type table<string, integer>
M.log_levels = has_vim and vim.log.levels or {
	TRACE = 0,
	DEBUG = 1,
	INFO = 2,
	WARN = 3,
	ERROR = 4,
	OFF = 5,
}

return M
