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

return T
