local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local uuid = require("org_markdown.utils.uuid")

local UUID_V4 = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

T["generate - returns a 36-character string"] = function()
	local id = uuid.generate()
	MiniTest.expect.equality(type(id), "string")
	MiniTest.expect.equality(#id, 36)
end

T["generate - matches the RFC-4122 v4 layout"] = function()
	MiniTest.expect.equality(uuid.generate():match(UUID_V4) ~= nil, true)
end

T["generate - is lowercase hex and hyphens only"] = function()
	local id = uuid.generate()
	MiniTest.expect.equality(id, id:lower())
	MiniTest.expect.equality(id:match("[^%x%-]"), nil)
end

T["generate - version and variant nibbles are fixed"] = function()
	for _ = 1, 200 do
		local id = uuid.generate()
		MiniTest.expect.equality(id:sub(15, 15), "4")
		MiniTest.expect.equality(id:sub(20, 20):match("[89ab]") ~= nil, true)
	end
end

T["generate - stays well-formed and collision-free in bulk"] = function()
	local seen, count = {}, 10000
	local unique = 0
	for _ = 1, count do
		local id = uuid.generate()
		MiniTest.expect.equality(id:match(UUID_V4) ~= nil, true)
		if not seen[id] then
			seen[id] = true
			unique = unique + 1
		end
	end
	MiniTest.expect.equality(unique, count)
end

return T
