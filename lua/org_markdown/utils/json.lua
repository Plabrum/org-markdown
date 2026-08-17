-- Minimal, dependency-free JSON encoder.
--
-- The standalone CLI runs under plain luajit where neither `vim.json` nor any
-- external json library is available, so we ship our own encoder. Only `encode`
-- is provided: the in-editor consumer (a later ticket) decodes CLI output with
-- `vim.json.decode`, so no pure-Lua decoder is needed here.
--
-- Output is DETERMINISTIC: object keys are emitted in sorted order so encoded
-- values are byte-stable and therefore testable. List-like tables (contiguous
-- 1..n integer keys, per `compat.tbl_islist`) encode as JSON arrays; every other
-- table encodes as a JSON object; an empty table encodes as `{}`.

local compat = require("org_markdown.compat.vim")

local M = {}

-- Shared sentinel metatable marking a table as "always encode as a JSON array".
-- Without this, an empty Lua table is ambiguous and defaults to `{}` (object);
-- marking it forces `[]` so array-typed fields stay arrays even when empty.
local ARRAY_MT = {}

--- Tag a table so `encode` always emits it as a JSON array (even when empty).
--- Returns the same table for convenient inline use.
---@generic T: table
---@param t T
---@return T
function M.array(t)
	return setmetatable(t, ARRAY_MT)
end

--- Report whether a table was tagged with `M.array`.
---@param t table
---@return boolean
local function is_marked_array(t)
	return getmetatable(t) == ARRAY_MT
end

-- Escape map for characters that must be escaped inside a JSON string.
local ESCAPES = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\b"] = "\\b",
	["\f"] = "\\f",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

--- Encode a Lua string as a quoted JSON string, escaping control chars.
---@param s string
---@return string
local function encode_string(s)
	local out = s:gsub('[%z\1-\31"\\]', function(c)
		local mapped = ESCAPES[c]
		if mapped then
			return mapped
		end
		-- Remaining control characters: emit as \u00XX.
		return string.format("\\u%04x", string.byte(c))
	end)
	return '"' .. out .. '"'
end

--- Encode a number, rejecting NaN/inf (not representable in JSON).
---@param n number
---@return string
local function encode_number(n)
	if n ~= n or n == math.huge or n == -math.huge then
		error("json: cannot encode non-finite number")
	end
	-- Integers print without a trailing ".0"; %.14g keeps floats compact.
	if math.floor(n) == n and math.abs(n) < 1e15 then
		return string.format("%d", n)
	end
	return string.format("%.14g", n)
end

local encode_value

--- Encode a list-like table as a JSON array.
---@param t table
---@param seen table
---@return string
local function encode_array(t, seen)
	local parts = {}
	for i = 1, #t do
		parts[i] = encode_value(t[i], seen)
	end
	return "[" .. table.concat(parts, ",") .. "]"
end

--- Encode a table as a JSON object with keys emitted in sorted order.
---@param t table
---@param seen table
---@return string
local function encode_object(t, seen)
	local keys = {}
	for k in pairs(t) do
		if type(k) ~= "string" and type(k) ~= "number" then
			error("json: object keys must be strings or numbers")
		end
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)

	local parts = {}
	for _, k in ipairs(keys) do
		local encoded_key = encode_string(tostring(k))
		parts[#parts + 1] = encoded_key .. ":" .. encode_value(t[k], seen)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

--- Encode any supported Lua value into JSON.
---@param value any
---@param seen table Guards against cyclic tables.
---@return string
encode_value = function(value, seen)
	local t = type(value)
	if value == nil then
		return "null"
	elseif t == "boolean" then
		return value and "true" or "false"
	elseif t == "number" then
		return encode_number(value)
	elseif t == "string" then
		return encode_string(value)
	elseif t == "table" then
		if seen[value] then
			error("json: cannot encode table with cycles")
		end
		seen[value] = true

		local result
		if is_marked_array(value) then
			-- Explicitly tagged via M.array: always an array, even when empty.
			result = encode_array(value, seen)
		elseif next(value) == nil then
			-- Empty (untagged) table: encode as an object per the documented contract.
			result = "{}"
		elseif compat.tbl_islist(value) then
			result = encode_array(value, seen)
		else
			result = encode_object(value, seen)
		end

		seen[value] = nil
		return result
	else
		error("json: cannot encode value of type " .. t)
	end
end

--- Encode a Lua value to a JSON string (deterministic key ordering).
---@param value any
---@return string
function M.encode(value)
	return encode_value(value, {})
end

return M
