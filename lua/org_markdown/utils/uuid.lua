--- Pure-Lua RFC-4122 version 4 UUID generator
--- No dependency on `vim`, so this module works both inside Neovim and in the
--- standalone CLI runtime (bin/org).

local M = {}

-- Seed the PRNG once at module load using the highest-resolution clock
-- available, mixed with os.time() so repeated process starts within the
-- same second still diverge.
local seeded = false
local function ensure_seeded()
	if seeded then
		return
	end
	seeded = true
	local clock = os.clock() * 1000000
	math.randomseed(os.time() + math.floor(clock))
end

--- Generate a random RFC-4122 version 4 UUID string.
--- Format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
--- where x is any hex digit, the version nibble is fixed to 4, and the
--- variant nibble (y) is one of 8, 9, a, or b.
--- @return string uuid Lowercase 36-character UUID
function M.generate()
	ensure_seeded()

	local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
	local result = template:gsub("[xy]", function(c)
		local n
		if c == "x" then
			n = math.random(0, 15)
		else
			-- Variant bits must be "10xx", i.e. one of 8, 9, a, b
			n = math.random(8, 11)
		end
		return string.format("%x", n)
	end)

	return result
end

return M
