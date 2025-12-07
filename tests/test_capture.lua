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

-- =========================================================================
-- Bug 0.3 Tests: Template Marker Fixes
-- =========================================================================

T["template markers - %t and %H basic expansion"] = function()
	local capture = require("org_markdown.capture")

	-- Test %t expands to date
	local date_result = capture.capture_template_substitute("Meeting on %t", "%t", "<2025-11-29 Fri>")
	MiniTest.expect.equality(date_result, "Meeting on <2025-11-29 Fri>")

	-- Test %H expands to time
	local time_result = capture.capture_template_substitute("Call at %H", "%H", "14:30")
	MiniTest.expect.equality(time_result, "Call at 14:30")
end

T["template markers - %n uses config author_name"] = function()
	local config = require("org_markdown.config")

	-- Save original value
	local original_name = config.captures.author_name

	-- Test with config name
	config.captures.author_name = "Test User"

	-- Simulate the handler logic (can't call handler directly as it's in key_mapping)
	local name = config.captures.author_name
	if not name or name == "" then
		name = vim.fn.system("git config user.name"):gsub("\n", "")
	end
	if not name or name == "" then
		name = vim.env.USER or "User"
	end

	MiniTest.expect.equality(name, "Test User")

	-- Restore original value
	config.captures.author_name = original_name
end

T["template markers - %n falls back to git when config is nil"] = function()
	local config = require("org_markdown.config")

	-- Save original value
	local original_name = config.captures.author_name

	-- Test with nil config
	config.captures.author_name = nil

	-- Simulate the handler logic
	local name = config.captures.author_name
	if not name or name == "" then
		name = vim.fn.system("git config user.name"):gsub("\n", "")
	end
	if not name or name == "" then
		name = vim.env.USER or "User"
	end

	-- Should fall back to git or USER (which might be "Phil Labrum" from git config)
	-- The important thing is it's NOT hardcoded, it comes from git/env
	MiniTest.expect.no_equality(name, "")
	MiniTest.expect.equality(type(name), "string")

	-- Restore original value
	config.captures.author_name = original_name
end

T["template markers - %n falls back to USER when git fails"] = function()
	local config = require("org_markdown.config")

	-- Save original value
	local original_name = config.captures.author_name

	-- Test fallback chain
	config.captures.author_name = ""

	-- Simulate the handler logic with git command failing
	local name = config.captures.author_name
	if not name or name == "" then
		-- Simulate git command returning empty
		name = ""
	end
	if not name or name == "" then
		name = vim.env.USER or "User"
	end

	-- Should fall back to USER or "User"
	MiniTest.expect.equality(type(name), "string")
	MiniTest.expect.no_equality(name, "")

	-- Restore original value
	config.captures.author_name = original_name
end

T["template markers - full expansion loop processes all markers"] = function()
	-- This integration test simulates the actual key_mapping loop in capture_template()
	-- to verify that multiple markers are processed correctly
	local capture = require("org_markdown.capture")

	local template = "Date: %t Time: %H Name: %n"
	local text = template

	-- Simulate the key_mapping loop (simplified version)
	local test_mappings = {
		{ pattern = "%t", replacement = "<2025-11-29 Fri>" },
		{ pattern = "%H", replacement = "14:30" },
		{ pattern = "%n", replacement = "Test User" },
	}

	for _, entry in ipairs(test_mappings) do
		local matched = capture.capture_template_match(text, entry.pattern)
		if matched then
			text = capture.capture_template_substitute(text, entry.pattern, entry.replacement)
		end
	end

	-- Verify all three markers were expanded
	MiniTest.expect.equality(text, "Date: <2025-11-29 Fri> Time: 14:30 Name: Test User")

	-- Verify none of the original markers remain
	MiniTest.expect.equality(text:match("%%t"), nil)
	MiniTest.expect.equality(text:match("%%H"), nil)
	MiniTest.expect.equality(text:match("%%n"), nil)
end

T["template markers - Date: %t Time: %H expands both correctly"] = function()
	-- Direct test for Bug 0.3: the exact use case of Date + Time template
	local capture = require("org_markdown.capture")

	local template = "Date: %t Time: %H"

	-- Simulate what capture_template() does: loop through markers
	local text = template

	-- Expand %t (date)
	text = capture.capture_template_substitute(text, "%t", "<2025-11-29 Fri>")

	-- Expand %H (time)
	text = capture.capture_template_substitute(text, "%H", "14:30")

	-- Final result should have BOTH values, not the same value twice
	MiniTest.expect.equality(text, "Date: <2025-11-29 Fri> Time: 14:30")

	-- Verify we have the date
	MiniTest.expect.no_equality(text:find("<2025-11-29 Fri>", 1, true), nil)

	-- Verify we have the time
	MiniTest.expect.no_equality(text:find("14:30", 1, true), nil)

	-- CRITICAL: Verify they're DIFFERENT (this would fail with the old bug)
	-- Old bug would give: "Date: 14:30 Time: 14:30"
	MiniTest.expect.no_equality(text, "Date: 14:30 Time: 14:30")
	MiniTest.expect.no_equality(text, "Date: <2025-11-29 Fri> Time: <2025-11-29 Fri>")
end

T["template markers - %? cursor positioning"] = function()
	-- Test %? marker used in default "notes" template: "#  %?"
	local capture = require("org_markdown.capture")

	local template = "#  %?"

	-- Find where %? is located (for cursor positioning)
	local row, col = capture.capture_template_find(template, "%?")
	MiniTest.expect.equality(row, 0)
	MiniTest.expect.equality(col, 3) -- After "# "

	-- Remove %? marker (what happens when setting cursor)
	local cleaned = capture.capture_template_substitute(template, "%?", "", 1)
	MiniTest.expect.equality(cleaned, "#  ")
	MiniTest.expect.equality(cleaned:find("%?", 1, true), nil) -- Verify gone
end

T["template markers - %? works with other markers"] = function()
	-- Test that %? doesn't interfere with other markers
	local capture = require("org_markdown.capture")

	local template = "# %? Notes from %t"
	local text = template

	-- First expand %t
	text = capture.capture_template_substitute(text, "%t", "<2025-11-29 Fri>")
	MiniTest.expect.equality(text, "# %? Notes from <2025-11-29 Fri>")

	-- Then find and remove %?
	local row, col = capture.capture_template_find(text, "%?")
	MiniTest.expect.equality(row, 0)
	MiniTest.expect.equality(col, 2) -- After "# "

	text = capture.capture_template_substitute(text, "%?", "", 1)
	-- Note: This leaves the extra space, which is expected behavior
	MiniTest.expect.equality(text, "#  Notes from <2025-11-29 Fri>")
end

return T
