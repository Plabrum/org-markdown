local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local capture = require("org_markdown.capture")

-- Prompt Template Label Extraction
T["extract_label_from_prompt_template - simple label"] = function()
	local label = capture.extract_label_from_prompt_template("%^{Project Name}")
	MiniTest.expect.equality(label, "Project Name")
end

T["extract_label_from_prompt_template - no match"] = function()
	local label = capture.extract_label_from_prompt_template("No label here")
	MiniTest.expect.equality(label, nil)
end

-- capture_template_match
T["capture_template_match - matches existing marker"] = function()
	local matched = capture.capture_template_match("Hello %^{Name}", "%^{Name}")
	MiniTest.expect.equality(matched, "%^{Name}")
end

T["capture_template_match - no match for missing marker"] = function()
	local matched = capture.capture_template_match("Hello %^{Name}", "%^{NotThere}")
	MiniTest.expect.equality(matched, nil)
end

-- capture_template_substitute
T["capture_template_substitute - replaces marker once"] = function()
	local result = capture.capture_template_substitute("Hello %^{Name}", "%^{Name}", "Phil")
	MiniTest.expect.equality(result, "Hello Phil")
end

T["capture_template_substitute - replaces marker multiple times"] = function()
	local result = capture.capture_template_substitute("%^{Name} meets %^{Name}", "%^{Name}", "Phil", 2)
	MiniTest.expect.equality(result, "Phil meets Phil")
end

T["capture_template_substitute - limit replacement count"] = function()
	local result = capture.capture_template_substitute("%^{Name} meets %^{Name}", "%^{Name}", "Phil", 1)
	MiniTest.expect.equality(result, "Phil meets %^{Name}")
end

T["capture_template_substitute - no marker match"] = function()
	local result = capture.capture_template_substitute("Hello there", "%^{Name}", "Phil")
	MiniTest.expect.equality(result, "Hello there")
end

T["capture_template_substitute - escaped marker is respected"] = function()
	-- Ensure % is properly escaped and replaced
	local result = capture.capture_template_substitute("Check %t now", "%t", "12:00 PM")
	MiniTest.expect.equality(result, "Check 12:00 PM now")
end

T["capture_template_find - finds byte position of unescaped marker"] = function()
	local template = [[
  first line
  Event: %? at the park
  second line
  ]]

	local marker = "%?"
	local row, col = capture.capture_template_find(template, marker)

	MiniTest.expect.equality(row, 1)
	MiniTest.expect.equality(col, 9)
end

return T
