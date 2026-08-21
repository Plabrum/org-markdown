local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local uuid = require("org_markdown.utils.uuid")

local UUID_V4_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

T["generate - returns a string of length 36"] = function()
	local id = uuid.generate()
	MiniTest.expect.equality(type(id), "string")
	MiniTest.expect.equality(#id, 36)
end

T["generate - matches RFC-4122 v4 pattern"] = function()
	local id = uuid.generate()
	MiniTest.expect.equality(id:match(UUID_V4_PATTERN) ~= nil, true)
end

T["generate - hyphens in correct positions"] = function()
	local id = uuid.generate()
	MiniTest.expect.equality(id:sub(9, 9), "-")
	MiniTest.expect.equality(id:sub(14, 14), "-")
	MiniTest.expect.equality(id:sub(19, 19), "-")
	MiniTest.expect.equality(id:sub(24, 24), "-")
end

T["generate - version nibble is always 4"] = function()
	for _ = 1, 100 do
		local id = uuid.generate()
		MiniTest.expect.equality(id:sub(15, 15), "4")
	end
end

T["generate - variant nibble is always 8, 9, a, or b"] = function()
	for _ = 1, 100 do
		local id = uuid.generate()
		local variant = id:sub(20, 20)
		local ok = variant == "8" or variant == "9" or variant == "a" or variant == "b"
		MiniTest.expect.equality(ok, true)
	end
end

T["generate - is lowercase hex"] = function()
	local id = uuid.generate()
	MiniTest.expect.equality(id, id:lower())
	MiniTest.expect.equality(id:match("[^%x%-]") == nil, true)
end

T["generate - produces well-formed, collision-free UUIDs in bulk"] = function()
	local seen = {}
	local count = 10000
	for _ = 1, count do
		local id = uuid.generate()
		MiniTest.expect.equality(id:match(UUID_V4_PATTERN) ~= nil, true)
		MiniTest.expect.equality(seen[id], nil)
		seen[id] = true
	end

	local total = 0
	for _ in pairs(seen) do
		total = total + 1
	end
	MiniTest.expect.equality(total, count)
end

return T
