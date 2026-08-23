-- Pure-Lua RFC-4122 version 4 UUID generator.
--
-- Deliberately free of `vim.*` so identifiers can be minted from the standalone
-- CLI (bin/org) as well as in-editor, without going through the platform shim:
-- a UUID needs no filesystem or editor primitive, only a PRNG.

local M = {}

-- The PRNG is seeded once per process. `os.time()` alone repeats for every
-- process started within the same second, so it is mixed with `os.clock()`
-- (sub-second, process-local) to keep short-lived CLI invocations distinct.
local seeded = false

local function ensure_seeded()
	if seeded then
		return
	end
	math.randomseed(os.time() + math.floor(os.clock() * 1000000))
	seeded = true
end

-- `x` is any hex digit; the version nibble is literally 4; `y` carries the
-- RFC-4122 variant bits `10xx`, i.e. one of 8, 9, a, b.
local TEMPLATE = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"

--- Generate a random RFC-4122 version 4 UUID.
--- @return string uuid Lowercase 36-character UUID
function M.generate()
	ensure_seeded()

	local uuid = TEMPLATE:gsub("[xy]", function(c)
		local nibble = c == "x" and math.random(0, 15) or math.random(8, 11)
		return string.format("%x", nibble)
	end)

	return uuid
end

return M
