local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local parser = require("org_markdown.utils.parser")

local ID = "2b7f1c8e-9a4d-4f6b-8c21-0d3e5a7b9c11"

T["parse_link - extracts id and display text"] = function()
	local link = parser.parse_link("[Weekly review](id:" .. ID .. ")")
	MiniTest.expect.equality(link.id, ID)
	MiniTest.expect.equality(link.text, "Weekly review")
end

T["parse_link - reports the byte range of the link"] = function()
	local line = "see [Weekly review](id:" .. ID .. ") for details"
	local link = parser.parse_link(line)
	MiniTest.expect.equality(link.from, 5)
	MiniTest.expect.equality(line:sub(link.from, link.to), "[Weekly review](id:" .. ID .. ")")
end

T["parse_link - ignores plain markdown links"] = function()
	MiniTest.expect.equality(parser.parse_link("[Notes](./notes.md)"), nil)
end

T["parse_link - ignores a target that is not a uuid"] = function()
	MiniTest.expect.equality(parser.parse_link("[Notes](id:not-a-uuid)"), nil)
end

T["parse_link - no link returns nil"] = function()
	MiniTest.expect.equality(parser.parse_link("# TODO Write tests :work:"), nil)
end

T["parse_links - collects every link in order"] = function()
	local other = "9c4a7e10-2b3d-4a5f-9e88-71c0d6b2f345"
	local links = parser.parse_links("[First](id:" .. ID .. ") then [Second](id:" .. other .. ")")
	MiniTest.expect.equality(#links, 2)
	MiniTest.expect.equality(links[1].text, "First")
	MiniTest.expect.equality(links[2].id, other)
end

T["serialize_link - renders the markdown form"] = function()
	MiniTest.expect.equality(
		parser.serialize_link({ id = ID, text = "Weekly review" }),
		"[Weekly review](id:" .. ID .. ")"
	)
end

T["round trip - parse then serialize reproduces the link"] = function()
	local original = "[Weekly review](id:" .. ID .. ")"
	MiniTest.expect.equality(parser.serialize_link(parser.parse_link(original)), original)
end

T["round trip - serialize then parse reproduces id and text"] = function()
	local link = parser.parse_link(parser.serialize_link({ id = ID, text = "Project Apollo" }))
	MiniTest.expect.equality(link.id, ID)
	MiniTest.expect.equality(link.text, "Project Apollo")
end

return T
