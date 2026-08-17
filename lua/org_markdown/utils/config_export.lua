-- Serialize the live resolved config to a Lua-chunk file for the standalone CLI.
--
-- The `org` CLI runs under plain luajit with no `vim` global and, by itself,
-- only knows the DEFAULT config. To make CLI output match the in-editor agenda,
-- the editor exports its resolved config here and passes the file path via
-- `$ORG_MARKDOWN_CONFIG` (see `config.ENV_CONFIG`) when spawning the CLI. The
-- CLI's `config.setup()` then loads it as the base user config.
--
-- A Lua chunk (`return { ... }`) is emitted rather than JSON so the CLI loads it
-- with a bare `loadfile` -- no standalone JSON decoder needed. Non-serializable
-- values (functions, userdata, threads) are dropped: the agenda pipeline reads
-- only plain data (paths, view defs, patterns), so nothing it needs is lost.

local compat = require("org_markdown.compat.vim")
local platform = require("org_markdown.platform")

local M = {}

--- Serialize a string/number key into bracket form (`["k"]` / `[1]`).
--- Bracket form is always valid Lua, sidestepping reserved words like `end`.
---@param k any
---@return string|nil
local function serialize_key(k)
	if type(k) == "string" then
		return "[" .. string.format("%q", k) .. "]"
	elseif type(k) == "number" then
		return "[" .. tostring(k) .. "]"
	end
	return nil
end

--- Serialize a Lua value into a loadable Lua literal.
--- Returns nil for values with no Lua-literal form (functions/userdata/thread);
--- callers drop such entries.
---@param value any
---@return string|nil
local function serialize(value)
	local t = type(value)
	if t == "string" then
		return string.format("%q", value)
	elseif t == "number" or t == "boolean" then
		return tostring(value)
	elseif t == "nil" then
		return "nil"
	elseif t == "table" then
		local parts = {}
		if compat.tbl_islist(value) then
			for _, v in ipairs(value) do
				local sv = serialize(v)
				if sv ~= nil then
					parts[#parts + 1] = sv
				end
			end
		else
			-- Deterministic key order keeps the output byte-stable (testable).
			local keys = {}
			for k in pairs(value) do
				if type(k) == "string" or type(k) == "number" then
					keys[#keys + 1] = k
				end
			end
			table.sort(keys, function(a, b)
				return tostring(a) < tostring(b)
			end)
			for _, k in ipairs(keys) do
				local sv = serialize(value[k])
				local sk = serialize_key(k)
				if sv ~= nil and sk ~= nil then
					parts[#parts + 1] = sk .. " = " .. sv
				end
			end
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	-- Unsupported type (function/userdata/thread): no literal form.
	return nil
end

--- Serialize a config table into a loadable `return { ... }` chunk.
---@param cfg table
---@return string
function M.serialize(cfg)
	return "return " .. (serialize(cfg) or "{}") .. "\n"
end

--- Write the resolved config to a temp Lua-chunk file for the CLI to load.
--- Defaults to `config._runtime` (the live merged config) when none is given.
---@param cfg? table
---@return string|nil path, string|nil err
function M.write_temp(cfg)
	cfg = cfg or require("org_markdown.config")._runtime
	if type(cfg) ~= "table" then
		return nil, "no resolved config to export"
	end

	local path = os.tmpname()
	local ok, err = platform.fs.write_file(path, M.serialize(cfg))
	if not ok then
		return nil, "could not write config export: " .. tostring(err)
	end
	return path
end

return M
