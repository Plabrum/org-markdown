local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local editing = require("org_markdown.utils.editing")

local default_checkbox_states = { " ", "-", "X" }

-- Basic transitions
T["[ ] becomes [-]"] = function()
	local line = "- [ ] Write plugin"
	local result = editing.cycle_checkbox_inline(line, default_checkbox_states)
	MiniTest.expect.equality(result[1], "- [-] Write plugin")
end

T["[-] becomes [X]"] = function()
	local line = "- [-] Write plugin"
	local result = editing.cycle_checkbox_inline(line, default_checkbox_states)
	MiniTest.expect.equality(result[1], "- [X] Write plugin")
end

T["[X] becomes [ ] (wraparound)"] = function()
	local line = "- [X] Write plugin"
	local result = editing.cycle_checkbox_inline(line, default_checkbox_states)
	MiniTest.expect.equality(result[1], "- [ ] Write plugin")
end

-- Skip lines with no checkbox
T["Line with no checkbox is untouched"] = function()
	local line = "This is just a bullet"
	local result = editing.cycle_checkbox_inline(line, default_checkbox_states)
	MiniTest.expect.equality(result, nil)
end

-- Unknown checkbox states are skipped
T["Unknown checkbox state returns nil"] = function()
	local line = "- [?] Confused"
	local result = editing.cycle_checkbox_inline(line, default_checkbox_states)
	MiniTest.expect.equality(result, nil)
end

--  First match only
T["Only the first checkbox is cycled"] = function()
	local line = "- [ ] First [ ] Second"
	local result = editing.cycle_checkbox_inline(line, default_checkbox_states)
	MiniTest.expect.equality(result[1], "- [-] First [ ] Second")
end

-- Status cycling tests
local default_status_states = { "TODO", "IN_PROGRESS", "DONE" }

T["TODO becomes IN_PROGRESS"] = function()
	local line = "## TODO Write tests"
	local result = editing.cycle_status_inline(line, default_status_states)
	MiniTest.expect.equality(result[1], "## IN_PROGRESS Write tests")
end

T["Status cycling preserves priority"] = function()
	local line = "## TODO [#C] Make kanban view for list endpoint :feature:"
	local result = editing.cycle_status_inline(line, default_status_states)
	MiniTest.expect.equality(result[1], "## IN_PROGRESS [#C] Make kanban view for list endpoint :feature:")
end

T["Status cycling with high priority"] = function()
	local line = "## TODO [#A] Critical bug"
	local result = editing.cycle_status_inline(line, default_status_states)
	MiniTest.expect.equality(result[1], "## IN_PROGRESS [#A] Critical bug")
end

return T
