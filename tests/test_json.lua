local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local json = require("org_markdown.utils.json")

-- Primitives
T["encode - strings escape quotes and backslashes"] = function()
	MiniTest.expect.equality(json.encode('a"b\\c'), '"a\\"b\\\\c"')
end

T["encode - strings escape control chars"] = function()
	MiniTest.expect.equality(json.encode("line1\nline2\ttab"), '"line1\\nline2\\ttab"')
end

T["encode - other control chars use \\u escape"] = function()
	MiniTest.expect.equality(json.encode("\1"), '"\\u0001"')
end

T["encode - integers have no decimal point"] = function()
	MiniTest.expect.equality(json.encode(42), "42")
	MiniTest.expect.equality(json.encode(-7), "-7")
end

T["encode - booleans"] = function()
	MiniTest.expect.equality(json.encode(true), "true")
	MiniTest.expect.equality(json.encode(false), "false")
end

T["encode - nil is null"] = function()
	MiniTest.expect.equality(json.encode(nil), "null")
end

-- Arrays vs objects
T["encode - contiguous list is an array"] = function()
	MiniTest.expect.equality(json.encode({ 1, 2, 3 }), "[1,2,3]")
end

T["encode - array of strings"] = function()
	MiniTest.expect.equality(json.encode({ "a", "b" }), '["a","b"]')
end

T["encode - empty table is object"] = function()
	MiniTest.expect.equality(json.encode({}), "{}")
end

T["encode - json.array marks empty table as array"] = function()
	MiniTest.expect.equality(json.encode(json.array({})), "[]")
end

T["encode - json.array marks non-empty table as array"] = function()
	MiniTest.expect.equality(json.encode(json.array({ "a", "b" })), '["a","b"]')
end

T["encode - unmarked empty table still encodes as object"] = function()
	MiniTest.expect.equality(json.encode({}), "{}")
end

T["encode - marked array nested inside object"] = function()
	local out = json.encode({ tags = json.array({}), name = "x" })
	MiniTest.expect.equality(out, '{"name":"x","tags":[]}')
end

T["encode - object keys are sorted deterministically"] = function()
	local out = json.encode({ b = 2, a = 1, c = 3 })
	MiniTest.expect.equality(out, '{"a":1,"b":2,"c":3}')
end

T["encode - nested structure round-trips through vim.json.decode"] = function()
	local value = {
		view_id = "tasks",
		groups = {
			{ key = "TODO", items = { { title = "x", tags = { "work" } } } },
		},
	}
	local encoded = json.encode(value)
	local decoded = vim.json.decode(encoded)
	MiniTest.expect.equality(decoded.view_id, "tasks")
	MiniTest.expect.equality(decoded.groups[1].key, "TODO")
	MiniTest.expect.equality(decoded.groups[1].items[1].title, "x")
	MiniTest.expect.equality(decoded.groups[1].items[1].tags[1], "work")
end

T["encode - determinism: same input yields identical bytes"] = function()
	local value = { z = 1, a = { 3, 2, 1 }, m = "hi" }
	MiniTest.expect.equality(json.encode(value), json.encode(value))
end

return T
